-- Fase 2 — Salida/expulsión de jugador durante partida activa.
-- Un jugador puede abandonar (leave_active_game, solo él) o el anfitrión puede sacarlo
-- (remove_active_player, solo host). Conserva la fila y el historial: marca left_at/left_reason/
-- removed_by_ref. Resuelve el dinero de forma controlada (a la banca por defecto; reparto entero
-- entre restantes con resto a la banca solo si lo autoriza el anfitrión). Quita del orden de turnos
-- preservando la invariante current = turn_order_refs[turn_index]. Se integra con running/paused/finished
-- (en finished -> GAME_FINISHED; en paused permitido por ser gestión administrativa).
-- NO toca games.status. NO implementa propiedades ni cartas (Fase 3): esa regla queda solo documentada.

-- ── 1) Marca de salida en players (conserva fila e historial) ────────────────────
alter table public.players add column if not exists left_at        timestamptz null;
alter table public.players add column if not exists left_reason    text        null;
alter table public.players add column if not exists removed_by_ref text        null;  -- public_ref del anfitrión, o el propio en abandono
create index if not exists players_left_idx on public.players (game_id) where left_at is not null;

-- Un jugador "fuera de partida" deja de ser miembro activo: lo excluimos en TODAS las RPC activas
-- que identifican al llamante por este helper, y en el snapshot. (En lobby left_at es siempre null.)
create or replace function public._require_active_player(p_game uuid)
returns public.players language plpgsql security definer set search_path = public, pg_temp as $$
declare p public.players;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into p from public.players where game_id=p_game and auth_uid=auth.uid() and kicked_at is null and left_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  return p;
end $$;

-- ── 2) Tipos de ledger de salida (reconciliables: saldo = entradas - salidas) ─────
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check check (kind in
  ('seed','bank_to_player','player_to_bank','player_to_player','host_player_transfer','host_adjust','host_revert','late_join_seed',
   'player_exit_to_bank','player_exit_distribution','player_exit_remainder_to_bank'));
alter table public.ledger drop constraint ledger_shape;
alter table public.ledger add constraint ledger_shape check (
  case kind
    when 'seed' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is null and before_balance is null and after_balance is null
    when 'late_join_seed' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'bank_to_player' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_bank' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_player' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'host_player_transfer' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reason is not null and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'host_adjust' then
      before_balance is not null and after_balance is not null
      and before_balance <> after_balance
      and amount = abs(after_balance - before_balance)
      and ((after_balance > before_balance and from_ref is null     and to_ref is not null)
        or (after_balance < before_balance and from_ref is not null and to_ref is null))
      and reason is not null and reverts_ledger_id is null and request_id is not null
    when 'host_revert' then
      reverts_ledger_id is not null and reason is not null and request_id is not null
      and before_balance is null and after_balance is null
      and ( ((from_ref is null) <> (to_ref is null))
         or (from_ref is not null and to_ref is not null and from_ref <> to_ref) )
    when 'player_exit_to_bank' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'player_exit_distribution' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'player_exit_remainder_to_bank' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    else false
  end
);

-- ── 3) Helper común: resuelve dinero, orden de turnos, marca de salida, versión, auditoría, broadcast ──
-- El llamante ya mantiene game_runtime FOR UPDATE (vía _p2_lock) y ha validado estado/permisos/versión.
-- p_mode: 'to_bank' (por defecto) | 'distribute'. p_removed_by: public_ref del actor (host o el propio).
create or replace function public._p2_remove_player(
  p_game uuid, p_target public.players, p_mode text, p_reason text, p_removed_by text
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; v_bal bigint; v_remaining text[]; n int;
        v_quotient bigint; v_remainder bigint := 0; r text;
        v_cur text; v_left_is_cur boolean; v_new_cur text; v_new_idx int; v_ver bigint;
begin
  select * into rt from public.game_runtime where game_id = p_game for update;     -- reafirma el bloqueo
  if not (p_target.public_ref = any(rt.turn_order_refs)) then raise exception 'TARGET_NOT_IN_GAME'; end if;
  v_cur := rt.turn_order_refs[rt.turn_index];
  v_left_is_cur := (p_target.public_ref = v_cur);

  -- Saldo del saliente (bloquea su fila).
  select balance into v_bal from public.player_balances
    where game_id = p_game and player_ref = p_target.public_ref for update;
  v_bal := coalesce(v_bal, 0);

  -- Restantes activos, en el mismo orden relativo (sin el saliente).
  select array_agg(x order by ord) into v_remaining
    from unnest(rt.turn_order_refs) with ordinality as t(x, ord)
    where x <> p_target.public_ref;
  n := coalesce(array_length(v_remaining, 1), 0);
  if n < 1 then raise exception 'NO_REMAINING_PLAYERS'; end if;   -- el anfitrión siempre permanece

  -- Resolución del dinero (reconciliable; banco = NULL).
  if p_mode = 'distribute' then
    v_quotient := v_bal / n;                       -- división entera
    v_remainder := v_bal - v_quotient * n;         -- resto -> banca
    if v_quotient > 0 then
      foreach r in array v_remaining loop
        update public.player_balances set balance = balance + v_quotient, updated_at = now()
          where game_id = p_game and player_ref = r;
        perform public._p2_post(p_game, 'player_exit_distribution', p_target.public_ref, r, v_quotient,
                                null, null, null, p_removed_by, null, gen_random_uuid());
      end loop;
    end if;
    if v_remainder > 0 then
      perform public._p2_post(p_game, 'player_exit_remainder_to_bank', p_target.public_ref, null, v_remainder,
                              null, null, null, p_removed_by, null, gen_random_uuid());
    end if;
  else  -- 'to_bank' (por defecto)
    if v_bal > 0 then
      perform public._p2_post(p_game, 'player_exit_to_bank', p_target.public_ref, null, v_bal,
                              null, null, null, p_removed_by, null, gen_random_uuid());
    end if;
  end if;
  update public.player_balances set balance = 0, updated_at = now()
    where game_id = p_game and player_ref = p_target.public_ref;

  -- Orden de turnos: quitar al saliente preservando current = turn_order_refs[turn_index].
  if v_left_is_cur then
    v_new_cur := rt.turn_order_refs[(rt.turn_index % array_length(rt.turn_order_refs, 1)) + 1];  -- siguiente válido
  else
    v_new_cur := v_cur;                                                                          -- el actual no cambia
  end if;
  v_new_idx := array_position(v_remaining, v_new_cur);
  if v_new_idx is null then v_new_idx := 1; end if;   -- salvaguarda
  update public.game_runtime set turn_order_refs = v_remaining, turn_index = v_new_idx
    where game_id = p_game;   -- turn_number intacto

  -- Marca de salida (conserva fila e historial; deja de ser participante activo).
  update public.players set left_at = now(), left_reason = nullif(btrim(coalesce(p_reason,'')),''),
         removed_by_ref = p_removed_by, row_version = row_version + 1
    where id = p_target.id;

  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'player_left', auth.uid(), p_target.id, array[p_target.id],
            jsonb_build_object('balance', v_bal, 'was_current', v_left_is_cur),
            jsonb_build_object('mode', p_mode, 'removed_by', p_removed_by, 'remaining', n,
                               'distributed', case when p_mode='distribute' then v_bal - v_remainder else 0 end,
                               'remainder_to_bank', v_remainder), p_reason, false);
  perform public._emit_active_signal(p_game);
  return jsonb_build_object('left_ref', p_target.public_ref, 'mode', p_mode,
                            'amount', v_bal, 'runtime_version', v_ver);
end $$;
revoke all on function public._p2_remove_player(uuid, public.players, text, text, text) from public, anon, authenticated;

-- ── 4) leave_active_game: SOLO el propio jugador; saldo siempre a la banca ────────
create or replace function public.leave_active_game(
  p_game uuid, p_resolution_mode text, p_request_id uuid, p_expected_version bigint
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; me public.players; v_idem jsonb; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);                                   -- 1) idempotencia/2) bloqueo
  v_idem := public._p2_idem_raw(p_game, p_request_id);             --    (control: sin guard de pausa)
  if v_idem is not null then return v_idem; end if;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;   -- 3) estado: terminal bloquea
  -- 5) permisos: el propio jugador (puede estar pausada: gestión administrativa permitida)
  select * into me from public.players where game_id = p_game and auth_uid = auth.uid() and kicked_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  if me.left_at is not null then                                   -- ya fuera: idempotente
    v_res := jsonb_build_object('left', true, 'idempotent', true, 'runtime_version', rt.runtime_version);
    perform public._p2_save(p_game, p_request_id, 'leave_active_game', v_res);
    return v_res;
  end if;
  select * into g from public.games where id = p_game;
  if me.id = g.host_player_id then raise exception 'HOST_CANNOT_LEAVE'; end if;     -- el anfitrión no abandona
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;  -- 4) versión
  -- 6) efecto: abandono voluntario -> saldo a la banca (el reparto solo lo autoriza el anfitrión)
  v_res := public._p2_remove_player(p_game, me, 'to_bank', 'abandono voluntario', me.public_ref);
  perform public._p2_save(p_game, p_request_id, 'leave_active_game', v_res);
  return v_res;
end $$;

-- ── 5) remove_active_player: SOLO anfitrión; a la banca (def.) o reparto entre restantes ──
create or replace function public.remove_active_player(
  p_game uuid, p_target_ref text, p_resolution_mode text, p_reason text, p_request_id uuid, p_expected_version bigint
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; t public.players; v_idem jsonb; v_res jsonb; v_host_ref text; v_mode text;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  v_mode := coalesce(nullif(btrim(p_resolution_mode), ''), 'to_bank');
  if v_mode not in ('to_bank', 'distribute') then raise exception 'INVALID_RESOLUTION'; end if;
  rt := public._p2_lock(p_game);                                   -- 1) idempotencia/2) bloqueo
  v_idem := public._p2_idem_raw(p_game, p_request_id);
  if v_idem is not null then return v_idem; end if;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;   -- 3) estado
  g := public._require_host(p_game);                               -- 5) permisos: solo anfitrión
  select * into t from public.players where game_id = p_game and public_ref = p_target_ref;
  if not found then raise exception 'TARGET_NOT_FOUND' using errcode = 'P0002'; end if;
  if t.left_at is not null or t.kicked_at is not null then         -- ya fuera: idempotente (no recargable)
    v_res := jsonb_build_object('left', true, 'idempotent', true, 'runtime_version', rt.runtime_version);
    perform public._p2_save(p_game, p_request_id, 'remove_active_player', v_res);
    return v_res;
  end if;
  if t.id = g.host_player_id then raise exception 'CANNOT_REMOVE_HOST'; end if;     -- no dejar la partida sin control
  if not (p_target_ref = any(rt.turn_order_refs)) then raise exception 'TARGET_NOT_FOUND' using errcode = 'P0002'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;  -- 4) versión
  select public_ref into v_host_ref from public.players where id = g.host_player_id;
  -- 6) efecto
  v_res := public._p2_remove_player(p_game, t, v_mode, coalesce(nullif(btrim(p_reason),''),'expulsado por el anfitrión'), v_host_ref);
  perform public._p2_save(p_game, p_request_id, 'remove_active_player', v_res);
  return v_res;
end $$;

grant execute on function public.leave_active_game(uuid, text, uuid, bigint)                 to authenticated;
grant execute on function public.remove_active_player(uuid, text, text, text, uuid, bigint)  to authenticated;

-- ── 6) Snapshot: el jugador "fuera de partida" deja de ser miembro activo (me excluye left_at) ──
-- La lista de players ya excluye a los salientes porque se quitan de turn_order_refs.
create or replace function public.get_active_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; rt public.game_runtime; me public.players; v_cur text; v_players jsonb; v_ledger jsonb;
        v_is_host boolean; v_late jsonb;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where code = upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode = 'P0002'; end if;
  if g.status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  select * into me from public.players where game_id = g.id and auth_uid = auth.uid() and kicked_at is null and left_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  select * into rt from public.game_runtime where game_id = g.id;
  v_cur := rt.turn_order_refs[rt.turn_index];
  v_is_host := me.id = g.host_player_id;

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

  if v_is_host then
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', lr.public_ref, 'name', lr.desired_name, 'token', lr.desired_token,
             'device_label', lr.device_label) order by lr.created_at), '[]'::jsonb)
      into v_late from public.late_join_requests lr where lr.game_id=g.id and lr.status='pending';
  else
    v_late := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'game', jsonb_build_object('code', g.code, 'status', g.status,
      'config', jsonb_build_object(
        'initial_money', coalesce((g.config->>'initial_money')::int, 3000),
        'min_players',   coalesce((g.config->>'min_players')::int, 6),
        'max_players',   coalesce((g.config->>'max_players')::int, 16),
        'allow_late_join', coalesce((g.config->>'allow_late_join')::boolean, false))),
    'me', jsonb_build_object('public_ref', me.public_ref, 'is_host', v_is_host,
      'balance', (select balance from public.player_balances where game_id = g.id and player_ref = me.public_ref),
      'is_current', me.public_ref = v_cur),
    'turn', jsonb_build_object('turn_number', rt.turn_number, 'current_player_ref', v_cur,
      'order', to_jsonb(rt.turn_order_refs)),
    'players', coalesce(v_players, '[]'::jsonb),
    'ledger_recent', coalesce(v_ledger, '[]'::jsonb),
    'late_join_requests', v_late,
    'runtime_status', rt.runtime_status,
    'control', jsonb_build_object(
      'paused_by_ref', rt.paused_by_ref, 'finished_by_ref', rt.finished_by_ref, 'reason', rt.status_reason),
    'runtime_version', rt.runtime_version);
end $$;

-- ── 7) Consistencia de lobby: allow_late_join va en el helper compartido (no inyectado solo en by_code) ──
-- Antes, get_lobby_snapshot_by_code añadía allow_late_join con jsonb_set mientras get_lobby_snapshot(id) no,
-- divergiendo. Lo movemos al helper para que AMBAS entradas expongan el mismo contrato.
create or replace function public._lobby_snapshot(p_game uuid, p_caller uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  g public.games;
  me public.players;
  v_is_host boolean;
  v_players jsonb;
  v_requests jsonb := '[]'::jsonb;
  v_pc int; v_rc int;
begin
  if p_caller is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where id = p_game;
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  -- Miembro activo: ni expulsado ni fuera de partida (un saliente deja de ser miembro).
  select * into me from public.players where game_id = p_game and auth_uid = p_caller and kicked_at is null and left_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  v_is_host := (me.id = g.host_player_id);

  select coalesce(jsonb_agg(jsonb_build_object(
            'public_ref', p.public_ref, 'name', p.display_name, 'token_id', p.token_id,
            'status', p.join_status, 'last_seen_at', p.last_seen_at) order by p.created_at), '[]')
    into v_players
  from public.players p where p.game_id = p_game and p.kicked_at is null and p.left_at is null;

  select count(*), count(*) filter (where join_status = 'ready')
    into v_pc, v_rc from public.players where game_id = p_game and kicked_at is null and left_at is null;

  if v_is_host then
    select coalesce(jsonb_agg(req order by ord), '[]') into v_requests from (
      select jsonb_build_object('request_ref', r.public_ref, 'kind', 'recovery', 'status', r.status,
               'target_public_ref', tp.public_ref, 'device_label', r.device_label) as req, r.created_at as ord
      from public.player_recovery_requests r
      join public.players tp on tp.id = r.player_id
      where r.game_id = p_game and r.status = 'pending'
      union all
      select jsonb_build_object('request_ref', rr.public_ref, 'kind', 'reentry', 'status', rr.status,
               'target_public_ref', pp.public_ref, 'device_label', rr.device_label), rr.created_at
      from public.player_reentry_requests rr
      join public.players pp on pp.id = rr.prior_player_id
      where rr.game_id = p_game and rr.status = 'pending'
    ) s;
  end if;

  return jsonb_build_object(
    'game', jsonb_build_object(
      'id', g.id, 'code', g.code, 'name', g.name, 'status', g.status,
      'version', g.version, 'started_at', g.started_at, 'cancelled_at', g.cancelled_at,
      'host_public_ref', (select public_ref from public.players where id = g.host_player_id),
      'config', jsonb_build_object(
        'min_players',   coalesce((g.config->>'min_players')::int, 6),
        'max_players',   coalesce((g.config->>'max_players')::int, 16),
        'initial_money', coalesce((g.config->>'initial_money')::int, 3000),
        'allow_late_join', coalesce((g.config->>'allow_late_join')::boolean, false),
        'token_catalog_version', coalesce((g.config->>'token_catalog_version')::int, 0))),
    'players', v_players,
    'me', jsonb_build_object(
      'public_ref', me.public_ref, 'is_host', v_is_host,
      'join_status', me.join_status, 'token_id', me.token_id, 'membership', 'active'),
    'requests', v_requests,
    'counts', jsonb_build_object(
      'player_count', v_pc, 'ready_count', v_rc,
      'min_players', coalesce((g.config->>'min_players')::int, 6),
      'max_players', coalesce((g.config->>'max_players')::int, 16))
  );
end $$;

-- by_code ya no necesita inyectar allow_late_join: el helper lo incluye. Ambas entradas coinciden.
create or replace function public.get_lobby_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select id into v_id from public.games where code = upper(btrim(p_code));
  if v_id is null then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  return public._lobby_snapshot(v_id, auth.uid());
end $$;
