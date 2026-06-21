-- ============================================================================
-- Fase 7 — Tratos avanzados · RPCs (crear, aceptar, rechazar, contraofertar, cancelar, resolver host).
-- Estados: pending → (acepta contraparte) → host_review (si procede) → executed; con countered (contraoferta),
-- rejected, cancelled, invalidated. Idempotencia (_p2_idem/_p2_save), version (game_runtime), ejecución atómica.
-- ============================================================================

-- ── Crear propuesta (el creador prepara ambos lados; la contraparte debe responder) ──
create or replace function public.create_trade_proposal(
  p_game uuid, p_to_ref text, p_from_money bigint, p_to_money bigint,
  p_from_props text[], p_to_props text[], p_from_cards text[], p_to_cards text[], p_agreement text, p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; r public.game_trade_proposals; v_host boolean; v_agree text;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  if rt.runtime_status='paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_agree := nullif(btrim(coalesce(p_agreement,'')),'');
  -- Trato no vacío.
  if p_from_money=0 and p_to_money=0 and coalesce(array_length(p_from_props,1),0)=0 and coalesce(array_length(p_to_props,1),0)=0
     and coalesce(array_length(p_from_cards,1),0)=0 and coalesce(array_length(p_to_cards,1),0)=0 and v_agree is null then
    raise exception 'EMPTY_TRADE';
  end if;
  perform public._p7_check(p_game, me.public_ref, p_to_ref, coalesce(p_from_money,0), coalesce(p_to_money,0),
                           p_from_props, p_to_props, p_from_cards, p_to_cards, null);
  v_host := public._p7_needs_host(p_from_props, p_to_props, p_from_cards, p_to_cards, v_agree);
  insert into public.game_trade_proposals(game_id, from_ref, to_ref, from_money, to_money, agreement_text, requires_host, pending_party, status)
    values (p_game, me.public_ref, p_to_ref, coalesce(p_from_money,0), coalesce(p_to_money,0), v_agree, v_host, p_to_ref, 'pending')
    returning * into r;
  if p_from_props is not null then insert into public.game_trade_items(proposal_id, side, item_type, ref) select r.id,'from','property',x from unnest(p_from_props) x; end if;
  if p_to_props   is not null then insert into public.game_trade_items(proposal_id, side, item_type, ref) select r.id,'to','property',x   from unnest(p_to_props)   x; end if;
  if p_from_cards is not null then insert into public.game_trade_items(proposal_id, side, item_type, ref) select r.id,'from','card',x     from unnest(p_from_cards) x; end if;
  if p_to_cards   is not null then insert into public.game_trade_items(proposal_id, side, item_type, ref) select r.id,'to','card',x       from unnest(p_to_cards)   x; end if;
  perform public._audit(p_game, 'trade_created', auth.uid(), me.id, null, null,
    jsonb_build_object('trade', r.public_ref, 'to', p_to_ref, 'requires_host', v_host), null, false);
  perform public._emit_active_signal(p_game);
  perform public._p2_save(p_game, p_request_id, 'create_trade', jsonb_build_object('trade_ref', r.public_ref, 'status','pending','requires_host', v_host));
  return jsonb_build_object('trade_ref', r.public_ref, 'status','pending','requires_host', v_host);
end $$;

-- ── Lee los 4 arrays de ítems de una propuesta ──
create or replace function public._p7_items(p_proposal_id uuid, out fp text[], out tp text[], out fc text[], out tc text[])
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(array_agg(ref) filter (where side='from' and item_type='property'),'{}'),
         coalesce(array_agg(ref) filter (where side='to'   and item_type='property'),'{}'),
         coalesce(array_agg(ref) filter (where side='from' and item_type='card'),'{}'),
         coalesce(array_agg(ref) filter (where side='to'   and item_type='card'),'{}')
  from public.game_trade_items where proposal_id = p_proposal_id;
$$;

-- ── Ejecuta una propuesta válida (revalida; si cambió el estado → invalidated). Devuelve jsonb resultado. ──
create or replace function public._p7_run(p_proposal_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare pr public.game_trade_proposals; it record; v_ver bigint;
begin
  select * into pr from public.game_trade_proposals where id = p_proposal_id;
  it := public._p7_items(p_proposal_id);
  begin
    perform public._p7_check(pr.game_id, pr.from_ref, pr.to_ref, pr.from_money, pr.to_money, it.fp, it.tp, it.fc, it.tc, pr.id);
  exception when others then
    update public.game_trade_proposals set status='invalidated', resolved_at=now(), updated_at=now() where id=pr.id;
    perform public._audit(pr.game_id, 'trade_invalidated', auth.uid(), null, null, null, jsonb_build_object('trade', pr.public_ref, 'reason', sqlerrm), null, false);
    perform public._emit_active_signal(pr.game_id);
    return jsonb_build_object('status','invalidated','reason', sqlerrm);
  end;
  perform public._p7_transfer(pr.id);
  v_ver := public._p2_bump(pr.game_id);
  update public.game_trade_proposals set status='executed', resolved_at=now(), updated_at=now(), result_seq=v_ver where id=pr.id;
  perform public._audit(pr.game_id, 'trade_executed', auth.uid(), null, null, null, jsonb_build_object('trade', pr.public_ref), null, false);
  perform public._emit_active_signal(pr.game_id);
  return jsonb_build_object('status','executed','runtime_version', v_ver);
end $$;

-- ── Aceptar: la parte a la que se espera acepta. Money-only → ejecuta; con host → pasa a host_review. ──
create or replace function public.accept_trade_proposal(p_request_ref text, p_expected_version bigint, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare pr public.game_trade_proposals; rt public.game_runtime; me public.players; v_idem jsonb; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into pr from public.game_trade_proposals where public_ref=p_request_ref for update;
  if not found then raise exception 'TRADE_NOT_FOUND' using errcode='P0002'; end if;
  rt := public._p2_lock(pr.game_id);
  if rt.runtime_status='paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(pr.game_id, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(pr.game_id);
  if pr.status not in ('pending','countered') then raise exception 'TRADE_NOT_PENDING'; end if;
  if me.public_ref <> pr.pending_party then raise exception 'NOT_TRADE_COUNTERPARTY'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if pr.requires_host then
    update public.game_trade_proposals set status='host_review', pending_party=null, updated_at=now() where id=pr.id;
    perform public._audit(pr.game_id, 'trade_accepted', auth.uid(), me.id, null, null, jsonb_build_object('trade', pr.public_ref, 'next','host_review'), null, false);
    perform public._emit_active_signal(pr.game_id);
    v_res := jsonb_build_object('trade_ref', pr.public_ref, 'status','host_review');
  else
    perform public._audit(pr.game_id, 'trade_accepted', auth.uid(), me.id, null, null, jsonb_build_object('trade', pr.public_ref, 'next','execute'), null, false);
    v_res := public._p7_run(pr.id) || jsonb_build_object('trade_ref', pr.public_ref);
  end if;
  perform public._p2_save(pr.game_id, p_request_id, 'accept_trade', v_res);
  return v_res;
end $$;

-- ── Rechazar: cualquier participante puede declinar. ──
create or replace function public.reject_trade_proposal(p_request_ref text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare pr public.game_trade_proposals; rt public.game_runtime; me public.players; v_idem jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into pr from public.game_trade_proposals where public_ref=p_request_ref for update;
  if not found then raise exception 'TRADE_NOT_FOUND' using errcode='P0002'; end if;
  rt := public._p2_lock(pr.game_id);
  v_idem := public._p2_idem(pr.game_id, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(pr.game_id);
  if pr.status not in ('pending','countered','host_review') then raise exception 'TRADE_NOT_PENDING'; end if;
  if me.public_ref <> pr.from_ref and me.public_ref <> pr.to_ref then raise exception 'NOT_TRADE_PARTICIPANT'; end if;
  update public.game_trade_proposals set status='rejected', resolved_at=now(), resolved_by_ref=me.public_ref, pending_party=null, updated_at=now() where id=pr.id;
  perform public._audit(pr.game_id, 'trade_rejected', auth.uid(), me.id, null, null, jsonb_build_object('trade', pr.public_ref), null, false);
  perform public._emit_active_signal(pr.game_id);
  perform public._p2_save(pr.game_id, p_request_id, 'reject_trade', jsonb_build_object('status','rejected'));
  return jsonb_build_object('status','rejected');
end $$;

-- ── Cancelar: solo el creador, antes de ejecutar. ──
create or replace function public.cancel_trade_proposal(p_request_ref text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare pr public.game_trade_proposals; rt public.game_runtime; me public.players; v_idem jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into pr from public.game_trade_proposals where public_ref=p_request_ref for update;
  if not found then raise exception 'TRADE_NOT_FOUND' using errcode='P0002'; end if;
  rt := public._p2_lock(pr.game_id);
  v_idem := public._p2_idem(pr.game_id, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(pr.game_id);
  if pr.status not in ('pending','countered','host_review') then raise exception 'TRADE_NOT_PENDING'; end if;
  if me.public_ref <> pr.from_ref then raise exception 'NOT_TRADE_CREATOR'; end if;
  update public.game_trade_proposals set status='cancelled', resolved_at=now(), resolved_by_ref=me.public_ref, pending_party=null, updated_at=now() where id=pr.id;
  perform public._audit(pr.game_id, 'trade_cancelled', auth.uid(), me.id, null, null, jsonb_build_object('trade', pr.public_ref), null, false);
  perform public._emit_active_signal(pr.game_id);
  perform public._p2_save(pr.game_id, p_request_id, 'cancel_trade', jsonb_build_object('status','cancelled'));
  return jsonb_build_object('status','cancelled');
end $$;

-- ── Contraoferta: la parte esperada modifica los términos; vuelve a la otra parte. ──
create or replace function public.counter_trade_proposal(
  p_request_ref text, p_from_money bigint, p_to_money bigint,
  p_from_props text[], p_to_props text[], p_from_cards text[], p_to_cards text[], p_agreement text, p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare pr public.game_trade_proposals; rt public.game_runtime; me public.players; v_idem jsonb; v_host boolean; v_agree text; v_next text; v_status public.trade_status;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into pr from public.game_trade_proposals where public_ref=p_request_ref for update;
  if not found then raise exception 'TRADE_NOT_FOUND' using errcode='P0002'; end if;
  rt := public._p2_lock(pr.game_id);
  if rt.runtime_status='paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(pr.game_id, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(pr.game_id);
  if pr.status not in ('pending','countered') then raise exception 'TRADE_NOT_PENDING'; end if;
  if me.public_ref <> pr.pending_party then raise exception 'NOT_TRADE_COUNTERPARTY'; end if;
  v_agree := nullif(btrim(coalesce(p_agreement,'')),'');
  if p_from_money=0 and p_to_money=0 and coalesce(array_length(p_from_props,1),0)=0 and coalesce(array_length(p_to_props,1),0)=0
     and coalesce(array_length(p_from_cards,1),0)=0 and coalesce(array_length(p_to_cards,1),0)=0 and v_agree is null then
    raise exception 'EMPTY_TRADE';
  end if;
  perform public._p7_check(pr.game_id, pr.from_ref, pr.to_ref, coalesce(p_from_money,0), coalesce(p_to_money,0),
                           p_from_props, p_to_props, p_from_cards, p_to_cards, pr.id);
  v_host := public._p7_needs_host(p_from_props, p_to_props, p_from_cards, p_to_cards, v_agree);
  -- La próxima acción la tiene la OTRA parte.
  if me.public_ref = pr.from_ref then v_next := pr.to_ref; v_status := 'pending'; else v_next := pr.from_ref; v_status := 'countered'; end if;
  update public.game_trade_proposals set from_money=coalesce(p_from_money,0), to_money=coalesce(p_to_money,0),
         agreement_text=v_agree, requires_host=v_host, pending_party=v_next, status=v_status, updated_at=now() where id=pr.id;
  delete from public.game_trade_items where proposal_id=pr.id;
  if p_from_props is not null then insert into public.game_trade_items(proposal_id, side, item_type, ref) select pr.id,'from','property',x from unnest(p_from_props) x; end if;
  if p_to_props   is not null then insert into public.game_trade_items(proposal_id, side, item_type, ref) select pr.id,'to','property',x   from unnest(p_to_props)   x; end if;
  if p_from_cards is not null then insert into public.game_trade_items(proposal_id, side, item_type, ref) select pr.id,'from','card',x     from unnest(p_from_cards) x; end if;
  if p_to_cards   is not null then insert into public.game_trade_items(proposal_id, side, item_type, ref) select pr.id,'to','card',x       from unnest(p_to_cards)   x; end if;
  perform public._audit(pr.game_id, 'trade_countered', auth.uid(), me.id, null, null, jsonb_build_object('trade', pr.public_ref, 'next', v_next), null, false);
  perform public._emit_active_signal(pr.game_id);
  perform public._p2_save(pr.game_id, p_request_id, 'counter_trade', jsonb_build_object('trade_ref', pr.public_ref, 'status', v_status));
  return jsonb_build_object('trade_ref', pr.public_ref, 'status', v_status);
end $$;

-- ── Resolver (anfitrión): aprobar/rechazar un trato en host_review. ──
create or replace function public.resolve_trade_proposal(p_request_ref text, p_accept boolean, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare pr public.game_trade_proposals; g public.games; rt public.game_runtime; v_host_ref text; v_res jsonb;
begin
  select * into pr from public.game_trade_proposals where public_ref=p_request_ref for update;
  if not found then raise exception 'TRADE_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(pr.game_id);
  select * into rt from public.game_runtime where game_id=g.id for update;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  if pr.status <> 'host_review' then return jsonb_build_object('status', pr.status::text, 'idempotent', true); end if;
  select public_ref into v_host_ref from public.players where id=g.host_player_id;
  if not p_accept then
    update public.game_trade_proposals set status='rejected', resolved_at=now(), resolved_by_ref=v_host_ref, pending_party=null, updated_at=now() where id=pr.id;
    perform public._audit(g.id, 'trade_host_rejected', auth.uid(), null, null, null, jsonb_build_object('trade', pr.public_ref), null, false);
    perform public._emit_active_signal(g.id);
    return jsonb_build_object('status','rejected');
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._audit(g.id, 'trade_host_approved', auth.uid(), null, null, null, jsonb_build_object('trade', pr.public_ref), null, false);
  v_res := public._p7_run(pr.id);
  if (v_res->>'status') = 'executed' then
    update public.game_trade_proposals set resolved_by_ref=v_host_ref where id=pr.id;
  end if;
  return v_res || jsonb_build_object('trade_ref', pr.public_ref);
end $$;

grant execute on function public.create_trade_proposal(uuid,text,bigint,bigint,text[],text[],text[],text[],text,uuid) to authenticated;
grant execute on function public.accept_trade_proposal(text,bigint,uuid) to authenticated;
grant execute on function public.reject_trade_proposal(text,uuid) to authenticated;
grant execute on function public.cancel_trade_proposal(text,uuid) to authenticated;
grant execute on function public.counter_trade_proposal(text,bigint,bigint,text[],text[],text[],text[],text,uuid) to authenticated;
grant execute on function public.resolve_trade_proposal(text,boolean,bigint) to authenticated;
revoke all on function public._p7_items(uuid) from public, anon, authenticated;
revoke all on function public._p7_run(uuid) from public, anon, authenticated;
revoke all on function public._p7_needs_host(text[],text[],text[],text[],text) from public, anon, authenticated;
revoke all on function public._p7_money_cap() from public, anon, authenticated;
