-- Fase 3 (corrección) — Abandono con aprobación del anfitrión + Bancarrota (a banca / a jugador)
-- con estado espectador. La expulsión por anfitrión (remove_active_player) ya existe y no cambia.

-- ── Estado de bancarrota en players (espectador; conserva fila e historial) ───────
alter table public.players add column if not exists bankrupt_at timestamptz null;
alter table public.players add column if not exists bankrupt_kind text null;          -- 'to_bank' | 'to_player'
alter table public.players add column if not exists bankrupt_creditor_ref text null;
create index if not exists players_bankrupt_idx on public.players (game_id) where bankrupt_at is not null;

-- Un jugador en bancarrota NO es miembro activo para actuar (sí puede consultar el snapshot).
create or replace function public._require_active_player(p_game uuid)
returns public.players language plpgsql security definer set search_path = public, pg_temp as $$
declare p public.players;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into p from public.players where game_id=p_game and auth_uid=auth.uid()
    and kicked_at is null and left_at is null and bankrupt_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  return p;
end $$;

-- ── Ledger: efectivo por bancarrota (a banca / a jugador). Propiedades = auditoría ─
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check check (kind in
  ('seed','bank_to_player','player_to_bank','player_to_player','host_player_transfer','host_adjust','host_revert','late_join_seed',
   'player_exit_to_bank','player_exit_distribution','player_exit_remainder_to_bank',
   'property_purchase','rent_payment','property_auction_purchase',
   'bankruptcy_cash_to_bank','bankruptcy_cash_to_player'));
alter table public.ledger drop constraint ledger_shape;
alter table public.ledger add constraint ledger_shape check (
  case kind
    when 'seed' then from_ref is null and to_ref is not null and reverts_ledger_id is null and request_id is null and before_balance is null and after_balance is null
    when 'late_join_seed' then from_ref is null and to_ref is not null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'bank_to_player' then from_ref is null and to_ref is not null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_bank' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_player' then from_ref is not null and to_ref is not null and from_ref <> to_ref and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'host_player_transfer' then from_ref is not null and to_ref is not null and from_ref <> to_ref and reason is not null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'host_adjust' then before_balance is not null and after_balance is not null and before_balance <> after_balance and amount = abs(after_balance - before_balance)
      and ((after_balance > before_balance and from_ref is null and to_ref is not null) or (after_balance < before_balance and from_ref is not null and to_ref is null))
      and reason is not null and reverts_ledger_id is null and request_id is not null
    when 'host_revert' then reverts_ledger_id is not null and reason is not null and request_id is not null and before_balance is null and after_balance is null
      and ( ((from_ref is null) <> (to_ref is null)) or (from_ref is not null and to_ref is not null and from_ref <> to_ref) )
    when 'player_exit_to_bank' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'player_exit_distribution' then from_ref is not null and to_ref is not null and from_ref <> to_ref and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'player_exit_remainder_to_bank' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'property_purchase' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'rent_payment' then from_ref is not null and to_ref is not null and from_ref <> to_ref and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'property_auction_purchase' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'bankruptcy_cash_to_bank' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'bankruptcy_cash_to_player' then from_ref is not null and to_ref is not null and from_ref <> to_ref and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    else false
  end
);

-- ── Helper: quita un ref del orden preservando current = turn_order_refs[turn_index] ─
create or replace function public._p3_drop_from_order(p_game uuid, p_player_ref text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; v_cur text; v_is_cur boolean; v_remaining text[]; v_new_cur text; v_new_idx int;
begin
  select * into rt from public.game_runtime where game_id=p_game for update;
  if not (p_player_ref = any(rt.turn_order_refs)) then return; end if;
  v_cur := rt.turn_order_refs[rt.turn_index];
  v_is_cur := (p_player_ref = v_cur);
  select array_agg(x order by ord) into v_remaining from unnest(rt.turn_order_refs) with ordinality as t(x,ord) where x <> p_player_ref;
  if coalesce(array_length(v_remaining,1),0) < 1 then raise exception 'NO_REMAINING_PLAYERS'; end if;
  if v_is_cur then v_new_cur := rt.turn_order_refs[(rt.turn_index % array_length(rt.turn_order_refs,1))+1]; else v_new_cur := v_cur; end if;
  v_new_idx := array_position(v_remaining, v_new_cur);
  if v_new_idx is null then v_new_idx := 1; end if;
  update public.game_runtime set turn_order_refs=v_remaining, turn_index=v_new_idx where game_id=p_game;
end $$;
revoke all on function public._p3_drop_from_order(uuid, text) from public, anon, authenticated;

-- ── Abandono con aprobación ──────────────────────────────────────────────────────
create table public.player_leave_requests (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null default public.gen_public_ref(),
  game_id uuid not null references public.games(id) on delete cascade,
  requester_ref text not null,
  status public.request_status not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  resolved_by_ref text null,
  resolution_mode text null
);
create unique index plr_pubref_key on public.player_leave_requests (public_ref);
create unique index plr_one_pending on public.player_leave_requests (game_id, requester_ref) where status='pending';
alter table public.player_leave_requests enable row level security;
revoke all on public.player_leave_requests from anon, authenticated;

-- El abandono directo ya no está disponible: ahora pasa por solicitud.
revoke execute on function public.leave_active_game(uuid, text, uuid, bigint) from public, anon, authenticated;

-- request_leave_active: si no tiene saldo NI propiedades -> salida directa auditada; si no, solicitud.
create or replace function public.request_leave_active(p_game uuid, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; me public.players; v_idem jsonb; v_bal bigint; v_props int; r public.player_leave_requests; v_existing public.player_leave_requests; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem_raw(p_game, p_request_id); if v_idem is not null then return v_idem; end if;  -- abandono permitido en pausa
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  me := public._require_active_player(p_game);
  select * into g from public.games where id=p_game;
  if me.id = g.host_player_id then raise exception 'HOST_CANNOT_LEAVE'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  select count(*) into v_props from public.property_ownership where game_id=p_game and owner_ref=me.public_ref and released_at is null;
  if coalesce(v_bal,0)=0 and v_props=0 then
    -- salida directa (auditada por _p2_remove_player)
    v_res := public._p2_remove_player(p_game, me, 'to_bank', 'abandono directo (sin saldo ni propiedades)', me.public_ref);
    perform public._p2_save(p_game, p_request_id, 'request_leave_active', jsonb_build_object('left',true,'direct',true));
    return jsonb_build_object('left',true,'direct',true);
  end if;
  select * into v_existing from public.player_leave_requests where game_id=p_game and requester_ref=me.public_ref and status='pending';
  if found then
    perform public._p2_save(p_game, p_request_id, 'request_leave_active', jsonb_build_object('request_ref',v_existing.public_ref,'status','pending'));
    return jsonb_build_object('request_ref',v_existing.public_ref,'status','pending');
  end if;
  insert into public.player_leave_requests(game_id, requester_ref) values (p_game, me.public_ref) returning * into r;
  perform public._audit(p_game,'player_leave_requested',auth.uid(),me.id,array[me.id],null,jsonb_build_object('request',r.public_ref),null,false);
  perform public._emit_active_signal(p_game);
  perform public._p2_save(p_game, p_request_id, 'request_leave_active', jsonb_build_object('request_ref',r.public_ref,'status','pending'));
  return jsonb_build_object('request_ref',r.public_ref,'status','pending');
end $$;

-- resolve_leave_active: el anfitrión aprueba (eligiendo destino del dinero) o rechaza.
create or replace function public.resolve_leave_active(p_request_ref text, p_accept boolean, p_resolution_mode text, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.player_leave_requests; g public.games; rt public.game_runtime; v_host_ref text; t public.players; v_mode text; v_res jsonb;
begin
  select * into r from public.player_leave_requests where public_ref=p_request_ref for update;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(r.game_id);
  select * into rt from public.game_runtime where game_id=g.id for update;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'idempotent', true); end if;
  select public_ref into v_host_ref from public.players where id=g.host_player_id;
  if not p_accept then
    update public.player_leave_requests set status='rejected', resolved_at=now(), resolved_by_ref=v_host_ref where id=r.id;
    perform public._audit(g.id,'player_leave_rejected',auth.uid(),null,null,null,jsonb_build_object('request',r.public_ref),null,false);
    perform public._emit_active_signal(g.id);
    return jsonb_build_object('status','rejected');
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  v_mode := coalesce(nullif(btrim(p_resolution_mode),''),'to_bank');
  if v_mode not in ('to_bank','distribute') then raise exception 'INVALID_RESOLUTION'; end if;
  select * into t from public.players where game_id=g.id and public_ref=r.requester_ref and kicked_at is null and left_at is null and bankrupt_at is null;
  if not found then raise exception 'TARGET_NOT_FOUND' using errcode='P0002'; end if;
  v_res := public._p2_remove_player(g.id, t, v_mode, 'abandono aprobado', v_host_ref);
  update public.player_leave_requests set status='approved', resolved_at=now(), resolved_by_ref=v_host_ref, resolution_mode=v_mode where id=r.id;
  perform public._audit(g.id,'player_leave_approved',auth.uid(),t.id,array[t.id],null,jsonb_build_object('request',r.public_ref,'mode',v_mode),null,false);
  perform public._emit_active_signal(g.id);
  return jsonb_build_object('status','approved','mode',v_mode,'result',v_res);
end $$;

-- ── Bancarrota ───────────────────────────────────────────────────────────────────
create table public.bankruptcy_requests (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null default public.gen_public_ref(),
  game_id uuid not null references public.games(id) on delete cascade,
  requester_ref text not null,
  kind text not null check (kind in ('to_bank','to_player')),
  creditor_ref text null,
  reason text null,
  status public.request_status not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  resolved_by_ref text null
);
create unique index br_pubref_key on public.bankruptcy_requests (public_ref);
create unique index br_one_pending on public.bankruptcy_requests (game_id, requester_ref) where status='pending';
alter table public.bankruptcy_requests enable row level security;
revoke all on public.bankruptcy_requests from anon, authenticated;

-- request_bankruptcy: el propio jugador la solicita.
create or replace function public.request_bankruptcy(p_game uuid, p_kind text, p_creditor_ref text, p_reason text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; me public.players; v_idem jsonb; r public.bankruptcy_requests; v_existing public.bankruptcy_requests;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if p_kind not in ('to_bank','to_player') then raise exception 'INVALID_BANKRUPTCY_KIND'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem_raw(p_game, p_request_id); if v_idem is not null then return v_idem; end if;  -- permitido en pausa
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  me := public._require_active_player(p_game);
  select * into g from public.games where id=p_game;
  if me.id = g.host_player_id then raise exception 'HOST_CANNOT_BANKRUPT'; end if;
  if p_kind='to_player' then
    if p_creditor_ref is null or p_creditor_ref = me.public_ref then raise exception 'INVALID_CREDITOR'; end if;
    perform 1 from public.players where game_id=p_game and public_ref=p_creditor_ref and kicked_at is null and left_at is null and bankrupt_at is null;
    if not found then raise exception 'INVALID_CREDITOR'; end if;
    if not (p_creditor_ref = any(rt.turn_order_refs)) then raise exception 'INVALID_CREDITOR'; end if;
  end if;
  select * into v_existing from public.bankruptcy_requests where game_id=p_game and requester_ref=me.public_ref and status='pending';
  if found then
    perform public._p2_save(p_game, p_request_id, 'request_bankruptcy', jsonb_build_object('request_ref',v_existing.public_ref,'status','pending'));
    return jsonb_build_object('request_ref',v_existing.public_ref,'status','pending');
  end if;
  insert into public.bankruptcy_requests(game_id, requester_ref, kind, creditor_ref, reason)
    values (p_game, me.public_ref, p_kind, case when p_kind='to_player' then p_creditor_ref else null end, nullif(btrim(coalesce(p_reason,'')),'')) returning * into r;
  perform public._audit(p_game,'bankruptcy_requested',auth.uid(),me.id,array[me.id],null,jsonb_build_object('request',r.public_ref,'kind',p_kind,'creditor',r.creditor_ref),p_reason,false);
  perform public._emit_active_signal(p_game);
  perform public._p2_save(p_game, p_request_id, 'request_bankruptcy', jsonb_build_object('request_ref',r.public_ref,'status','pending'));
  return jsonb_build_object('request_ref',r.public_ref,'status','pending');
end $$;

-- resolve_bankruptcy: el anfitrión aprueba/rechaza. Dinero + propiedades + estado espectador.
create or replace function public.resolve_bankruptcy(p_request_ref text, p_accept boolean, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.bankruptcy_requests; g public.games; rt public.game_runtime; v_host_ref text; t public.players;
        v_bal bigint; v_refs text[]; v_ver bigint; v_props jsonb;
begin
  select * into r from public.bankruptcy_requests where public_ref=p_request_ref for update;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(r.game_id);
  select * into rt from public.game_runtime where game_id=g.id for update;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'idempotent', true); end if;
  select public_ref into v_host_ref from public.players where id=g.host_player_id;
  if not p_accept then
    update public.bankruptcy_requests set status='rejected', resolved_at=now(), resolved_by_ref=v_host_ref where id=r.id;
    perform public._audit(g.id,'bankruptcy_rejected',auth.uid(),null,null,null,jsonb_build_object('request',r.public_ref),null,false);
    perform public._emit_active_signal(g.id);
    return jsonb_build_object('status','rejected');
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select * into t from public.players where game_id=g.id and public_ref=r.requester_ref and kicked_at is null and left_at is null and bankrupt_at is null;
  if not found then raise exception 'TARGET_NOT_FOUND' using errcode='P0002'; end if;
  if not (r.requester_ref = any(rt.turn_order_refs)) then raise exception 'TARGET_NOT_FOUND' using errcode='P0002'; end if;
  select balance into v_bal from public.player_balances where game_id=g.id and player_ref=r.requester_ref for update;
  v_bal := coalesce(v_bal,0);
  select array_agg(property_ref order by property_ref) into v_refs from public.property_ownership where game_id=g.id and owner_ref=r.requester_ref and released_at is null;
  v_props := coalesce(to_jsonb(v_refs), '[]'::jsonb);

  if r.kind='to_bank' then
    if v_bal > 0 then
      perform public._p2_post(g.id,'bankruptcy_cash_to_bank', r.requester_ref, null, v_bal, null,null,null, v_host_ref, null, gen_random_uuid());
      update public.player_balances set balance=0, updated_at=now() where game_id=g.id and player_ref=r.requester_ref;
    end if;
    update public.property_ownership set released_at=now(), released_reason='bankruptcy_to_bank' where game_id=g.id and owner_ref=r.requester_ref and released_at is null;
    perform public._audit(g.id,'bankruptcy_property_to_bank',auth.uid(),t.id,array[t.id],null,jsonb_build_object('properties',v_props),null,false);
  else  -- to_player
    -- revalidar acreedor
    perform 1 from public.players where game_id=g.id and public_ref=r.creditor_ref and kicked_at is null and left_at is null and bankrupt_at is null;
    if not found or not (r.creditor_ref = any(rt.turn_order_refs)) then raise exception 'INVALID_CREDITOR'; end if;
    if v_bal > 0 then
      perform public._p2_move(g.id, r.requester_ref, r.creditor_ref, v_bal);
      perform public._p2_post(g.id,'bankruptcy_cash_to_player', r.requester_ref, r.creditor_ref, v_bal, null,null,null, v_host_ref, null, gen_random_uuid());
    end if;
    update public.property_ownership set released_at=now(), released_reason='bankruptcy_to_player' where game_id=g.id and owner_ref=r.requester_ref and released_at is null;
    if v_refs is not null then
      insert into public.property_ownership(game_id, property_ref, owner_ref) select g.id, unnest(v_refs), r.creditor_ref;
    end if;
    perform public._audit(g.id,'bankruptcy_property_to_player',auth.uid(),t.id,array[t.id],null,jsonb_build_object('properties',v_props,'creditor',r.creditor_ref),null,false);
  end if;

  -- marcar espectador y sacar del orden
  update public.players set bankrupt_at=now(), bankrupt_kind=r.kind, bankrupt_creditor_ref=r.creditor_ref, row_version=row_version+1 where id=t.id;
  perform public._p3_drop_from_order(g.id, r.requester_ref);
  update public.bankruptcy_requests set status='approved', resolved_at=now(), resolved_by_ref=v_host_ref where id=r.id;
  v_ver := public._p2_bump(g.id);
  perform public._audit(g.id,'bankruptcy_approved',auth.uid(),t.id,array[t.id],jsonb_build_object('balance',v_bal),
    jsonb_build_object('kind',r.kind,'creditor',r.creditor_ref,'properties',v_props),null,false);
  perform public._emit_active_signal(g.id);
  return jsonb_build_object('status','approved','kind',r.kind,'creditor',r.creditor_ref,'runtime_version',v_ver);
end $$;

grant execute on function public.request_leave_active(uuid, uuid)                       to authenticated;
grant execute on function public.resolve_leave_active(text, boolean, text, bigint)       to authenticated;
grant execute on function public.request_bankruptcy(uuid, text, text, text, uuid)        to authenticated;
grant execute on function public.resolve_bankruptcy(text, boolean, bigint)               to authenticated;
