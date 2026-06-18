-- Fase 2 — Estado de ejecución de la partida activa: running / paused / finished.
-- Vive en game_runtime (no toca el enum histórico games.status). Pausada/finalizada
-- rechazan las mutaciones económicas y de turno; el snapshot sigue legible.

-- ── Estado autoritativo en game_runtime ──────────────────────────────────────────
alter table public.game_runtime
  add column runtime_status   text not null default 'running'
    constraint game_runtime_status_chk check (runtime_status in ('running', 'paused', 'finished')),
  add column paused_at        timestamptz null,
  add column paused_by_ref    text null,
  add column finished_at      timestamptz null,
  add column finished_by_ref  text null,
  add column status_reason    text null;

-- ── Guard de estado integrado en la idempotencia ────────────────────────────────
-- Orden requerido: 1) idempotencia (devolver resultado guardado) ANTES que 2) estado.
-- _p2_idem (usado por las 7 RPC de mutación) ahora: devuelve el resultado guardado si
-- existe; si no, valida runtime_status (GAME_PAUSED/GAME_FINISHED) y si todo va bien null.
-- El llamante ya mantiene game_runtime FOR UPDATE, así que la lectura es estable.
create or replace function public._p2_idem(p_game uuid, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v jsonb; v_status text;
begin
  select result into v from public.active_requests where game_id = p_game and request_id = p_request_id;
  if v is not null then return v; end if;                       -- reintento: idempotencia primero
  select runtime_status into v_status from public.game_runtime where game_id = p_game;
  if v_status = 'paused' then raise exception 'GAME_PAUSED'; end if;
  if v_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  return null;
end $$;

-- Variante SIN guard de estado para las RPC de control (que cambian el propio estado).
create or replace function public._p2_idem_raw(p_game uuid, p_request_id uuid)
returns jsonb language sql security definer set search_path = public, pg_temp as $$
  select result from public.active_requests where game_id = p_game and request_id = p_request_id
$$;

revoke all on function public._p2_idem(uuid, uuid), public._p2_idem_raw(uuid, uuid) from public, anon, authenticated;

-- ── pause_game_runtime: solo anfitrión; running -> paused ────────────────────────
create or replace function public.pause_game_runtime(p_game uuid, p_reason text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_ver bigint; v_host_ref text; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem_raw(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  if rt.runtime_status = 'paused' then  -- idempotente: ya pausada
    v_res := jsonb_build_object('changed', false, 'runtime_status', 'paused', 'runtime_version', rt.runtime_version);
    perform public._p2_save(p_game, p_request_id, 'pause_game_runtime', v_res);
    return v_res;
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select public_ref into v_host_ref from public.players where id = g.host_player_id;
  update public.game_runtime set runtime_status = 'paused', paused_at = now(), paused_by_ref = v_host_ref,
         status_reason = nullif(btrim(coalesce(p_reason, '')), '') where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'game_paused', auth.uid(), g.host_player_id, null,
            jsonb_build_object('runtime_status', 'running'), jsonb_build_object('runtime_status', 'paused'), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'runtime_status', 'paused', 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'pause_game_runtime', v_res);
  return v_res;
end $$;

-- ── resume_game_runtime: solo anfitrión; paused -> running ───────────────────────
create or replace function public.resume_game_runtime(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem_raw(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  if rt.runtime_status = 'running' then  -- idempotente: ya en curso
    v_res := jsonb_build_object('changed', false, 'runtime_status', 'running', 'runtime_version', rt.runtime_version);
    perform public._p2_save(p_game, p_request_id, 'resume_game_runtime', v_res);
    return v_res;
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  update public.game_runtime set runtime_status = 'running', paused_at = null, paused_by_ref = null, status_reason = null
    where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'game_resumed', auth.uid(), g.host_player_id, null,
            jsonb_build_object('runtime_status', 'paused'), jsonb_build_object('runtime_status', 'running'), null, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'runtime_status', 'running', 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'resume_game_runtime', v_res);
  return v_res;
end $$;

-- ── finish_game_runtime: solo anfitrión; running/paused -> finished (TERMINAL) ───
create or replace function public.finish_game_runtime(p_game uuid, p_reason text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_ver bigint; v_host_ref text; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem_raw(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  if rt.runtime_status = 'finished' then  -- idempotente: ya finalizada (terminal)
    v_res := jsonb_build_object('changed', false, 'runtime_status', 'finished', 'runtime_version', rt.runtime_version);
    perform public._p2_save(p_game, p_request_id, 'finish_game_runtime', v_res);
    return v_res;
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select public_ref into v_host_ref from public.players where id = g.host_player_id;
  update public.game_runtime set runtime_status = 'finished', finished_at = now(), finished_by_ref = v_host_ref,
         status_reason = nullif(btrim(coalesce(p_reason, '')), '') where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'game_finished', auth.uid(), g.host_player_id, null,
            jsonb_build_object('runtime_status', rt.runtime_status), jsonb_build_object('runtime_status', 'finished'), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'runtime_status', 'finished', 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'finish_game_runtime', v_res);
  return v_res;
end $$;

grant execute on function public.pause_game_runtime(uuid, text, uuid, bigint)  to authenticated;
grant execute on function public.resume_game_runtime(uuid, uuid, bigint)        to authenticated;
grant execute on function public.finish_game_runtime(uuid, text, uuid, bigint)  to authenticated;

-- ── Snapshot ampliado: runtime_status + metadatos de control (solo refs públicas) ─
create or replace function public.get_active_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; rt public.game_runtime; me public.players; v_cur text; v_players jsonb; v_ledger jsonb;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where code = upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode = 'P0002'; end if;
  if g.status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  select * into me from public.players where game_id = g.id and auth_uid = auth.uid() and kicked_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  select * into rt from public.game_runtime where game_id = g.id;
  v_cur := rt.turn_order_refs[rt.turn_index];

  select jsonb_agg(jsonb_build_object(
           'public_ref', p.public_ref, 'display_name', p.display_name, 'token_id', p.token_id,
           'balance', b.balance, 'is_current', p.public_ref = v_cur)
           order by array_position(rt.turn_order_refs, p.public_ref))
    into v_players
    from public.players p
    join public.player_balances b on b.game_id = p.game_id and b.player_ref = p.public_ref
    where p.game_id = g.id and p.public_ref = any(rt.turn_order_refs);

  select jsonb_agg(jsonb_build_object(
           'ledger_ref', l.ledger_ref, 'seq', l.seq, 'kind', l.kind, 'from_ref', l.from_ref, 'to_ref', l.to_ref,
           'amount', l.amount, 'before_balance', l.before_balance, 'after_balance', l.after_balance,
           'reason', l.reason, 'actor_ref', l.actor_ref,
           'reverts_ref', (select r.ledger_ref from public.ledger r where r.id = l.reverts_ledger_id),
           'created_at', l.created_at) order by l.seq desc)
    into v_ledger
    from (select * from public.ledger where game_id = g.id order by seq desc limit 25) l;

  return jsonb_build_object(
    'game', jsonb_build_object('code', g.code, 'status', g.status,
      'config', jsonb_build_object(
        'initial_money', coalesce((g.config->>'initial_money')::int, 3000),
        'min_players',   coalesce((g.config->>'min_players')::int, 6),
        'max_players',   coalesce((g.config->>'max_players')::int, 16))),
    'me', jsonb_build_object('public_ref', me.public_ref, 'is_host', me.id = g.host_player_id,
      'balance', (select balance from public.player_balances where game_id = g.id and player_ref = me.public_ref),
      'is_current', me.public_ref = v_cur),
    'turn', jsonb_build_object('turn_number', rt.turn_number, 'current_player_ref', v_cur,
      'order', to_jsonb(rt.turn_order_refs)),
    'players', coalesce(v_players, '[]'::jsonb),
    'ledger_recent', coalesce(v_ledger, '[]'::jsonb),
    'runtime_status', rt.runtime_status,
    'control', jsonb_build_object(
      'paused_by_ref', rt.paused_by_ref, 'finished_by_ref', rt.finished_by_ref, 'reason', rt.status_reason),
    'runtime_version', rt.runtime_version);
end $$;
