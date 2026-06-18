-- Fase 2 — RPC de la partida activa: turnos, banco, transferencias y correcciones.
-- Patrón común de cada mutación (idempotencia ANTES que versión; correcciones #9 y #10):
--   1) lock game_runtime FOR UPDATE  2) si request_id ya procesado -> devolver result
--   3) validar active  4) auth/host  5) validar runtime_version  6) aplicar
--   7) ledger + saldos + runtime_version+1 + _audit  8) guardar result  9) emitir señal.
-- Helpers internos: REVOKE de public/anon/authenticated (solo accesibles desde las RPC owner).

-- ── Helpers ──────────────────────────────────────────────────────────────────────
-- Serialización por partida: bloquea game_runtime FOR UPDATE y exige status='active'.
create or replace function public._p2_lock(p_game uuid)
returns public.game_runtime language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; v_status game_status;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select status into v_status from public.games where id = p_game;
  if v_status is null then raise exception 'GAME_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  select * into rt from public.game_runtime where game_id = p_game for update;   -- punto de serialización
  if not found then raise exception 'NOT_ACTIVE'; end if;
  return rt;
end $$;

create or replace function public._p2_idem(p_game uuid, p_request_id uuid)
returns jsonb language sql security definer set search_path = public, pg_temp as $$
  select result from public.active_requests where game_id = p_game and request_id = p_request_id
$$;

create or replace function public._p2_save(p_game uuid, p_request_id uuid, p_op text, p_result jsonb)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into public.active_requests(game_id, request_id, op, result) values (p_game, p_request_id, p_op, p_result)
$$;

-- Mueve saldos (banco = NULL). Bloquea las filas de balance afectadas. Lanza errores funcionales.
create or replace function public._p2_move(p_game uuid, p_from text, p_to text, p_amount bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_bal bigint;
begin
  if p_amount is null or p_amount <= 0 or p_amount > 10000000 then raise exception 'INVALID_AMOUNT'; end if;
  if p_from is not null then
    select balance into v_bal from public.player_balances where game_id = p_game and player_ref = p_from for update;
    if not found then raise exception 'UNKNOWN_PLAYER'; end if;
    if v_bal < p_amount then raise exception 'INSUFFICIENT_FUNDS'; end if;
    update public.player_balances set balance = balance - p_amount, updated_at = now()
      where game_id = p_game and player_ref = p_from;
  end if;
  if p_to is not null then
    select balance into v_bal from public.player_balances where game_id = p_game and player_ref = p_to for update;
    if not found then raise exception 'UNKNOWN_PLAYER'; end if;
    if v_bal + p_amount > 1000000000000 then raise exception 'BALANCE_LIMIT'; end if;
    update public.player_balances set balance = balance + p_amount, updated_at = now()
      where game_id = p_game and player_ref = p_to;
  end if;
end $$;

-- Inserta en ledger usando el contador bloqueado de game_runtime y devuelve ledger_ref.
create or replace function public._p2_post(
  p_game uuid, p_kind text, p_from text, p_to text, p_amount bigint,
  p_before bigint, p_after bigint, p_reason text, p_actor text, p_reverts uuid, p_request_id uuid
) returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v_seq bigint; v_ref text;
begin
  update public.game_runtime set ledger_seq = ledger_seq + 1 where game_id = p_game returning ledger_seq into v_seq;
  insert into public.ledger(ledger_ref, game_id, seq, kind, from_ref, to_ref, amount,
                            before_balance, after_balance, reason, actor_ref, reverts_ledger_id, request_id)
  values (public.gen_ledger_ref(p_game), p_game, v_seq, p_kind, p_from, p_to, p_amount,
          p_before, p_after, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_reverts, p_request_id)
  returning ledger_ref into v_ref;
  return v_ref;
end $$;

create or replace function public._p2_bump(p_game uuid)
returns bigint language sql security definer set search_path = public, pg_temp as $$
  update public.game_runtime set runtime_version = runtime_version + 1, updated_at = now()
    where game_id = p_game returning runtime_version
$$;

revoke all on function
  public._p2_lock(uuid), public._p2_idem(uuid, uuid), public._p2_save(uuid, uuid, text, jsonb),
  public._p2_move(uuid, text, text, bigint),
  public._p2_post(uuid, text, text, text, bigint, bigint, bigint, text, text, uuid, uuid),
  public._p2_bump(uuid)
from public, anon, authenticated;

-- ── Snapshot saneado (solo public_ref; sin ids internos / turn_order / auth_uid / secretos) ──
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
    'runtime_version', rt.runtime_version);
end $$;

-- ── end_turn: SOLO el jugador actual ─────────────────────────────────────────────
create or replace function public.end_turn(p_game uuid, p_expected_version bigint, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; n int; v_cur text; v_new int; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  n := array_length(rt.turn_order_refs, 1);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  v_new := (rt.turn_index % n) + 1;
  update public.game_runtime set turn_index = v_new, turn_number = turn_number + 1 where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'turn_ended', auth.uid(), me.id, null,
            jsonb_build_object('turn_index', rt.turn_index, 'turn_number', rt.turn_number),
            jsonb_build_object('turn_index', v_new, 'turn_number', rt.turn_number + 1), null, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'current_player_ref', rt.turn_order_refs[v_new],
             'turn_number', rt.turn_number + 1, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'end_turn', v_res);
  return v_res;
end $$;

-- ── bank_transfer: SOLO anfitrión (banca). Banco↔jugador ─────────────────────────
create or replace function public.bank_transfer(
  p_game uuid, p_player_ref text, p_direction text, p_amount bigint, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_ver bigint; v_bal bigint;
        v_from text; v_to text; v_kind text; v_host_ref text; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if p_direction not in ('to_player', 'from_player') then raise exception 'INVALID_DIRECTION'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  if not (p_player_ref = any(rt.turn_order_refs)) then raise exception 'UNKNOWN_PLAYER'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if p_direction = 'to_player' then v_from := null; v_to := p_player_ref; v_kind := 'bank_to_player';
  else v_from := p_player_ref; v_to := null; v_kind := 'player_to_bank'; end if;
  perform public._p2_move(p_game, v_from, v_to, p_amount);
  select public_ref into v_host_ref from public.players where id = g.host_player_id;
  perform public._p2_post(p_game, v_kind, v_from, v_to, p_amount, null, null, null, v_host_ref, null, p_request_id);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, v_kind, auth.uid(), g.host_player_id, null, null,
            jsonb_build_object('player', p_player_ref, 'amount', p_amount, 'direction', p_direction), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id = p_game and player_ref = p_player_ref;
  v_res := jsonb_build_object('changed', true, 'player_ref', p_player_ref, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'bank_transfer', v_res);
  return v_res;
end $$;

-- ── player_transfer: el pagador (JWT) paga a otro jugador, en cualquier momento ──
create or replace function public.player_transfer(
  p_game uuid, p_to_ref text, p_amount bigint, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  if p_to_ref = me.public_ref then raise exception 'SELF_TRANSFER'; end if;
  if not (p_to_ref = any(rt.turn_order_refs)) then raise exception 'UNKNOWN_PLAYER'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p2_move(p_game, me.public_ref, p_to_ref, p_amount);
  perform public._p2_post(p_game, 'player_to_player', me.public_ref, p_to_ref, p_amount, null, null, null, me.public_ref, null, p_request_id);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'player_to_player', auth.uid(), me.id, null, null,
            jsonb_build_object('to', p_to_ref, 'amount', p_amount), null, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'from_ref', me.public_ref, 'to_ref', p_to_ref, 'amount', p_amount, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'player_transfer', v_res);
  return v_res;
end $$;

-- ── host_player_transfer: corrección del anfitrión en nombre de otros (motivo obligatorio) ──
create or replace function public.host_player_transfer(
  p_game uuid, p_from_ref text, p_to_ref text, p_amount bigint, p_reason text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_ver bigint; v_host_ref text; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'REASON_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  if p_from_ref = p_to_ref then raise exception 'SELF_TRANSFER'; end if;
  if not (p_from_ref = any(rt.turn_order_refs)) or not (p_to_ref = any(rt.turn_order_refs)) then raise exception 'UNKNOWN_PLAYER'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p2_move(p_game, p_from_ref, p_to_ref, p_amount);
  select public_ref into v_host_ref from public.players where id = g.host_player_id;
  perform public._p2_post(p_game, 'host_player_transfer', p_from_ref, p_to_ref, p_amount, null, null, p_reason, v_host_ref, null, p_request_id);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'host_player_transfer', auth.uid(), g.host_player_id, null, null,
            jsonb_build_object('from', p_from_ref, 'to', p_to_ref, 'amount', p_amount), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'from_ref', p_from_ref, 'to_ref', p_to_ref, 'amount', p_amount, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'host_player_transfer', v_res);
  return v_res;
end $$;

-- ── host_adjust_balance: fija saldo (motivo); no-op idempotente si coincide ───────
create or replace function public.host_adjust_balance(
  p_game uuid, p_target_ref text, p_new_balance bigint, p_reason text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_ver bigint; v_cur bigint;
        v_delta bigint; v_from text; v_to text; v_host_ref text; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'REASON_REQUIRED'; end if;
  if p_new_balance is null or p_new_balance < 0 then raise exception 'NEGATIVE_NOT_ALLOWED'; end if;
  if p_new_balance > 1000000000000 then raise exception 'BALANCE_LIMIT'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  if not (p_target_ref = any(rt.turn_order_refs)) then raise exception 'UNKNOWN_PLAYER'; end if;
  select balance into v_cur from public.player_balances where game_id = p_game and player_ref = p_target_ref for update;
  if not found then raise exception 'UNKNOWN_PLAYER'; end if;
  -- Orden (corrección): idempotencia (arriba) -> VERSIÓN -> después no-op. Una solicitud NUEVA
  -- con versión obsoleta da VERSION_CONFLICT aunque resultara un no-op; un reintento ya
  -- registrado se resolvió antes por _p2_idem.
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  -- No-op: si coincide, NO toca versión/ledger/broadcast; resultado estable e idempotente.
  if p_new_balance = v_cur then
    v_res := jsonb_build_object('changed', false, 'balance', v_cur, 'runtime_version', rt.runtime_version);
    perform public._p2_save(p_game, p_request_id, 'host_adjust_balance', v_res);
    return v_res;
  end if;
  v_delta := p_new_balance - v_cur;
  if abs(v_delta) > 10000000 then raise exception 'INVALID_AMOUNT'; end if;          -- tope por operación
  if v_delta > 0 then v_from := null; v_to := p_target_ref; else v_from := p_target_ref; v_to := null; end if;
  update public.player_balances set balance = p_new_balance, updated_at = now()
    where game_id = p_game and player_ref = p_target_ref;
  select public_ref into v_host_ref from public.players where id = g.host_player_id;
  perform public._p2_post(p_game, 'host_adjust', v_from, v_to, abs(v_delta), v_cur, p_new_balance, p_reason, v_host_ref, null, p_request_id);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'host_adjust', auth.uid(), g.host_player_id, array[]::uuid[],
            jsonb_build_object('player', p_target_ref, 'balance', v_cur),
            jsonb_build_object('player', p_target_ref, 'balance', p_new_balance), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'target_ref', p_target_ref, 'balance', p_new_balance, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'host_adjust_balance', v_res);
  return v_res;
end $$;

-- ── host_set_turn: el anfitrión fija el turno a cualquier jugador del orden (motivo) ──
create or replace function public.host_set_turn(
  p_game uuid, p_target_ref text, p_reason text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_ver bigint; v_idx int; v_cur text; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'REASON_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  v_idx := array_position(rt.turn_order_refs, p_target_ref);
  if v_idx is null then raise exception 'UNKNOWN_PLAYER'; end if;
  v_cur := rt.turn_order_refs[rt.turn_index];
  -- No-op si ya es el actual (no incrementa versión).
  if p_target_ref = v_cur then
    v_res := jsonb_build_object('changed', false, 'current_player_ref', v_cur, 'runtime_version', rt.runtime_version);
    perform public._p2_save(p_game, p_request_id, 'host_set_turn', v_res);
    return v_res;
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  update public.game_runtime set turn_index = v_idx where game_id = p_game;   -- NO incrementa turn_number
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'host_set_turn', auth.uid(), g.host_player_id, null,
            jsonb_build_object('current', v_cur), jsonb_build_object('current', p_target_ref), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'current_player_ref', p_target_ref, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'host_set_turn', v_res);
  return v_res;
end $$;

-- ── host_revert_movement: reversión compensatoria de un movimiento EXPLÍCITO ──────
create or replace function public.host_revert_movement(
  p_game uuid, p_ledger_ref text, p_reason text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_ver bigint; m public.ledger;
        v_from text; v_to text; v_bal bigint; v_host_ref text; v_comp text; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'REASON_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  select * into m from public.ledger where game_id = p_game and ledger_ref = p_ledger_ref;
  if not found then raise exception 'UNKNOWN_LEDGER'; end if;
  if m.kind in ('seed', 'host_revert') then raise exception 'CANNOT_REVERT_SEED'; end if;
  if exists (select 1 from public.ledger where game_id = p_game and reverts_ledger_id = m.id) then raise exception 'ALREADY_REVERTED'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  -- Compensación inversa: intercambia from/to (banco = NULL se conserva).
  v_from := m.to_ref; v_to := m.from_ref;
  -- Bloquea y comprueba el lado que perderá dinero (no debe quedar negativo).
  if v_from is not null then
    select balance into v_bal from public.player_balances where game_id = p_game and player_ref = v_from for update;
    if v_bal < m.amount then raise exception 'WOULD_GO_NEGATIVE'; end if;
  end if;
  perform public._p2_move(p_game, v_from, v_to, m.amount);
  select public_ref into v_host_ref from public.players where id = g.host_player_id;
  v_comp := public._p2_post(p_game, 'host_revert', v_from, v_to, m.amount, null, null, p_reason, v_host_ref, m.id, p_request_id);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'host_revert', auth.uid(), g.host_player_id, null,
            jsonb_build_object('reverts', m.ledger_ref), jsonb_build_object('compensation', v_comp), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'reverted_ref', m.ledger_ref, 'compensation_ref', v_comp, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'host_revert_movement', v_res);
  return v_res;
end $$;

-- ── Grants: solo las RPC públicas; los helpers quedan revocados arriba ────────────
grant execute on function public.get_active_snapshot_by_code(text)                                   to authenticated;
grant execute on function public.end_turn(uuid, bigint, uuid)                                        to authenticated;
grant execute on function public.bank_transfer(uuid, text, text, bigint, uuid, bigint)               to authenticated;
grant execute on function public.player_transfer(uuid, text, bigint, uuid, bigint)                   to authenticated;
grant execute on function public.host_player_transfer(uuid, text, text, bigint, text, uuid, bigint)  to authenticated;
grant execute on function public.host_adjust_balance(uuid, text, bigint, text, uuid, bigint)         to authenticated;
grant execute on function public.host_set_turn(uuid, text, text, uuid, bigint)                       to authenticated;
grant execute on function public.host_revert_movement(uuid, text, text, uuid, bigint)                to authenticated;
