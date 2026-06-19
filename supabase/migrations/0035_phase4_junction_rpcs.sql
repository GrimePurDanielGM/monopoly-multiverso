-- Fase 4 (corrección 4) — RPC del CRUCE entre tableros (intersección con guardián).
-- _p4_apply_move detecta la cárcel-guardián: si el movimiento la alcanza con pasos restantes, se DETIENE
-- ahí (pending_junction) y no avanza solo. resolve_junction elige destino (seguir o cruzar al Parking del
-- otro tablero), cobrando el peaje si la entrada elegida está custodiada (si es la libre, el guardián se
-- desplaza a custodiarla). La cárcel/solo-visitas no es destino final: es de paso.

-- ── Núcleo del movimiento: detecta la bifurcación; si no, mueve normal ────────────
create or replace function public._p4_apply_move(
  p_game uuid, p_me public.players, p_steps int, p_request_id uuid, p_method text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; pos public.player_positions; v_ring int; v_old int; v_new int; v_passed boolean;
        v_bonus int := 0; sp public.board_spaces; v_ver bigint; v_bal bigint; v_last jsonb;
        v_j int; v_d int; v_remaining int; v_jname text; v_jref text;
begin
  select * into g from public.games where id = p_game;
  select * into pos from public.player_positions where game_id = p_game and player_ref = p_me.public_ref for update;
  if not found then raise exception 'NO_POSITION'; end if;
  v_ring := public._p4_ring_size(pos.board_key);
  if v_ring < 1 then raise exception 'BOARD_NOT_FOUND'; end if;
  v_old := pos.space_index;

  -- Cárcel-guardián de este tablero (bifurcación).
  select s.space_index into v_j from public.board_spaces s
    where s.board_key = pos.board_key and s.guardian and s.active limit 1;
  if v_j is not null then
    v_d := (v_j - v_old + v_ring) % v_ring;            -- pasos para llegar a la cárcel
    if v_d = 0 then v_d := v_ring; end if;             -- ya estás sobre ella: la siguiente está a una vuelta
  end if;

  if v_j is not null and p_steps > v_d then
    -- Alcanza la bifurcación con pasos restantes: DETENER y pedir decisión.
    v_remaining := p_steps - v_d;
    v_passed := (v_old + v_d) >= v_ring;               -- ¿pasó por salida al llegar a la cárcel?
    update public.player_positions set space_index = v_j, updated_at = now()
      where game_id = p_game and player_ref = p_me.public_ref;
    if v_passed then
      v_bonus := coalesce((g.config->>'start_bonus')::int, 200);
      if v_bonus > 0 then
        perform public._p2_move(p_game, null, p_me.public_ref, v_bonus);
        perform public._p2_post(p_game, 'pass_start_bonus', null, p_me.public_ref, v_bonus, null, null, null, p_me.public_ref, null, p_request_id);
      end if;
    end if;
    select name, space_ref into v_jname, v_jref from public.board_spaces where board_key=pos.board_key and space_index=v_j and active;
    update public.game_runtime set pending_junction = jsonb_build_object(
        'player_ref', p_me.public_ref, 'board_key', pos.board_key, 'junction_index', v_j,
        'remaining', v_remaining, 'passed_start', v_passed) where game_id = p_game;
    v_ver := public._p2_bump(p_game);
    perform public._audit(p_game, 'reached_junction', auth.uid(), p_me.id, array[p_me.id],
              jsonb_build_object('board', pos.board_key, 'from', v_old),
              jsonb_build_object('junction', v_j, 'remaining', v_remaining, 'method', p_method, 'bonus', v_bonus), null, false);
    update public.game_runtime set last_move = jsonb_build_object('player_ref', p_me.public_ref, 'board', pos.board_key,
        'from', v_old, 'to', v_j, 'steps', p_steps, 'method', p_method, 'passed_start', v_passed, 'bonus', v_bonus,
        'space_ref', v_jref, 'space_name', v_jname, 'space_type', 'jail', 'property_ref', null, 'pending_junction', true)
      where game_id = p_game;
    select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_me.public_ref;
    return jsonb_build_object('pending_junction', true, 'junction_index', v_j, 'remaining', v_remaining,
             'board', pos.board_key, 'balance', v_bal, 'runtime_version', v_ver);
  end if;

  -- Movimiento normal (sin bifurcación).
  v_new := (v_old + p_steps) % v_ring;
  v_passed := (v_old + p_steps) >= v_ring;
  update public.player_positions set space_index = v_new, updated_at = now()
    where game_id = p_game and player_ref = p_me.public_ref;
  if v_passed then
    v_bonus := coalesce((g.config->>'start_bonus')::int, 200);
    if v_bonus > 0 then
      perform public._p2_move(p_game, null, p_me.public_ref, v_bonus);
      perform public._p2_post(p_game, 'pass_start_bonus', null, p_me.public_ref, v_bonus, null, null, null, p_me.public_ref, null, p_request_id);
    end if;
  end if;
  select * into sp from public.board_spaces where board_key = pos.board_key and space_index = v_new and active;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'player_moved', auth.uid(), p_me.id, array[p_me.id],
            jsonb_build_object('board', pos.board_key, 'from', v_old),
            jsonb_build_object('board', pos.board_key, 'to', v_new, 'steps', p_steps, 'method', p_method,
                               'passed_start', v_passed, 'bonus', v_bonus, 'space', sp.space_ref, 'space_type', sp.space_type, 'property', sp.property_ref), null, false);
  if v_passed then
    perform public._audit(p_game, 'passed_start', auth.uid(), p_me.id, array[p_me.id], null, jsonb_build_object('bonus', v_bonus), null, true);
  end if;
  v_last := jsonb_build_object('player_ref', p_me.public_ref, 'board', pos.board_key, 'from', v_old, 'to', v_new,
              'steps', p_steps, 'method', p_method, 'passed_start', v_passed, 'bonus', v_bonus,
              'space_ref', sp.space_ref, 'space_name', sp.name, 'space_type', sp.space_type, 'property_ref', sp.property_ref, 'pending_junction', false);
  update public.game_runtime set last_move = v_last where game_id = p_game;
  select balance into v_bal from public.player_balances where game_id = p_game and player_ref = p_me.public_ref;
  return jsonb_build_object('from', v_old, 'to', v_new, 'steps', p_steps, 'passed_start', v_passed, 'bonus', v_bonus,
           'board', pos.board_key, 'space_ref', sp.space_ref, 'space_name', sp.name,
           'space_type', sp.space_type, 'property_ref', sp.property_ref, 'balance', v_bal, 'runtime_version', v_ver);
end $$;
revoke all on function public._p4_apply_move(uuid, public.players, int, uuid, text) from public, anon, authenticated;

-- ── move_player / roll_and_move: bloquean si hay decisión de cruce pendiente ───────
create or replace function public.move_player(p_game uuid, p_steps int, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; v_cur text; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if p_steps is null or p_steps < 1 or p_steps > 12 then raise exception 'INVALID_STEPS'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.pending_junction is not null then raise exception 'JUNCTION_PENDING'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  perform public._p4_ensure_guardians(p_game);
  update public.game_runtime set last_roll = null where game_id = p_game;
  v_res := public._p4_apply_move(p_game, me, p_steps, p_request_id, 'manual');
  perform public._emit_active_signal(p_game);
  perform public._p2_save(p_game, p_request_id, 'move_player', v_res);
  return v_res;
end $$;

create or replace function public.roll_and_move(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; v_cur text; d1 int; d2 int; v_move jsonb; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.pending_junction is not null then raise exception 'JUNCTION_PENDING'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  perform public._p4_ensure_guardians(p_game);
  d1 := floor(random() * 6)::int + 1;
  d2 := floor(random() * 6)::int + 1;
  update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', me.public_ref)
    where game_id = p_game;
  v_move := public._p4_apply_move(p_game, me, d1 + d2, p_request_id, 'roll');
  perform public._audit(p_game, 'player_rolled', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2), null, false);
  perform public._emit_active_signal(p_game);
  v_res := v_move || jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2);
  perform public._p2_save(p_game, p_request_id, 'roll_and_move', v_res);
  return v_res;
end $$;

-- ── resolve_junction: el jugador en la bifurcación elige seguir o cruzar ──────────
create or replace function public.resolve_junction(p_game uuid, p_direction text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; g public.games; v_idem jsonb; v_ver bigint; pj jsonb;
        v_board text; v_j int; v_remaining int; v_link_board text; v_link_index int; v_toll int; v_guards text;
        v_paid boolean := false; v_nb text; v_ringn int; v_ni int; v_passed boolean := false; v_bonus int := 0;
        sp public.board_spaces; v_bal bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if p_direction not in ('own','cross') then raise exception 'INVALID_DIRECTION'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  pj := rt.pending_junction;
  if pj is null then raise exception 'NO_PENDING_JUNCTION'; end if;
  if pj->>'player_ref' <> me.public_ref then raise exception 'NOT_YOUR_JUNCTION'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select * into g from public.games where id = p_game;
  v_board := pj->>'board_key'; v_j := (pj->>'junction_index')::int; v_remaining := (pj->>'remaining')::int;
  perform public._p4_ensure_guardians(p_game);
  select links_to_board, links_to_index, coalesce(guardian_toll,0) into v_link_board, v_link_index, v_toll
    from public.board_spaces where board_key = v_board and guardian and active limit 1;
  select guards into v_guards from public.game_guardians where game_id = p_game and board_key = v_board;

  if p_direction = v_guards then
    -- entrada custodiada: paga el peaje; el guardián se queda
    select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
    if v_bal < v_toll then raise exception 'INSUFFICIENT_FUNDS'; end if;
    if v_toll > 0 then
      perform public._p2_move(p_game, me.public_ref, null, v_toll);
      perform public._p2_post(p_game, 'guardian_toll', me.public_ref, null, v_toll, null, null, null, me.public_ref, null, p_request_id);
      v_paid := true;
    end if;
  else
    -- entrada libre: el guardián se desplaza a custodiarla
    update public.game_guardians set guards = p_direction, updated_at = now() where game_id = p_game and board_key = v_board;
  end if;

  -- Continúa los pasos restantes en la dirección elegida.
  if p_direction = 'own' then
    v_nb := v_board; v_ringn := public._p4_ring_size(v_nb);
    v_ni := (v_j + v_remaining) % v_ringn; v_passed := (v_j + v_remaining) >= v_ringn;
  else
    v_nb := v_link_board; v_ringn := public._p4_ring_size(v_nb);
    v_ni := (v_link_index + v_remaining - 1) % v_ringn; v_passed := (v_link_index + v_remaining - 1) >= v_ringn;
  end if;
  if v_passed then
    v_bonus := coalesce((g.config->>'start_bonus')::int, 200);
    if v_bonus > 0 then
      perform public._p2_move(p_game, null, me.public_ref, v_bonus);
      perform public._p2_post(p_game, 'pass_start_bonus', null, me.public_ref, v_bonus, null, null, null, me.public_ref, null, p_request_id);
    end if;
  end if;
  update public.player_positions set board_key = v_nb, space_index = v_ni, updated_at = now()
    where game_id = p_game and player_ref = me.public_ref;
  update public.game_runtime set pending_junction = null where game_id = p_game;
  select * into sp from public.board_spaces where board_key = v_nb and space_index = v_ni and active;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'junction_resolved', auth.uid(), me.id, array[me.id],
            jsonb_build_object('board', v_board, 'junction', v_j),
            jsonb_build_object('direction', p_direction, 'paid_toll', v_paid, 'toll', case when v_paid then v_toll else 0 end,
                               'board', v_nb, 'to', v_ni, 'bonus', v_bonus), null, false);
  update public.game_runtime set last_move = jsonb_build_object('player_ref', me.public_ref, 'board', v_nb,
      'from', v_j, 'to', v_ni, 'steps', v_remaining, 'method', case when p_direction='cross' then 'cross' else 'continue' end,
      'passed_start', v_passed, 'bonus', v_bonus, 'space_ref', sp.space_ref, 'space_name', sp.name,
      'space_type', sp.space_type, 'property_ref', sp.property_ref, 'pending_junction', false) where game_id = p_game;
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('direction', p_direction, 'paid_toll', v_paid, 'board', v_nb, 'space_index', v_ni,
             'space_ref', sp.space_ref, 'space_name', sp.name, 'property_ref', sp.property_ref, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'resolve_junction', v_res);
  return v_res;
end $$;

-- ── end_turn: bloquea si el jugador tiene una decisión de cruce pendiente ─────────
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
  if rt.pending_junction is not null then raise exception 'JUNCTION_PENDING'; end if;
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

-- ── host_set_player_position: además, limpia la decisión pendiente de ese jugador ──
create or replace function public.host_set_player_position(
  p_game uuid, p_player_ref text, p_board_key text, p_space_index int, p_reason text,
  p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; me_p public.players; v_idem jsonb; v_ver bigint; v_ring int; old_pos public.player_positions; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'REASON_REQUIRED'; end if;
  if p_board_key not in ('classic','back_to_the_future') then raise exception 'INVALID_BOARD'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  select * into me_p from public.players where game_id = p_game and public_ref = p_player_ref
    and kicked_at is null and left_at is null;
  if not found then raise exception 'UNKNOWN_PLAYER'; end if;
  v_ring := public._p4_ring_size(p_board_key);
  if p_space_index is null or p_space_index < 0 or p_space_index >= v_ring then raise exception 'INVALID_SPACE'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  select * into old_pos from public.player_positions where game_id = p_game and player_ref = p_player_ref for update;
  insert into public.player_positions(game_id, player_ref, board_key, space_index)
    values (p_game, p_player_ref, p_board_key, p_space_index)
    on conflict (game_id, player_ref) do update set board_key = excluded.board_key,
      space_index = excluded.space_index, updated_at = now();
  -- si el jugador recolocado tenía una decisión de cruce pendiente, se anula.
  if rt.pending_junction is not null and rt.pending_junction->>'player_ref' = p_player_ref then
    update public.game_runtime set pending_junction = null where game_id = p_game;
  end if;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'host_set_position', auth.uid(), g.host_player_id, array[me_p.id],
            jsonb_build_object('board', old_pos.board_key, 'space', old_pos.space_index),
            jsonb_build_object('board', p_board_key, 'space', p_space_index), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('player_ref', p_player_ref, 'board', p_board_key, 'space_index', p_space_index, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'host_set_player_position', v_res);
  return v_res;
end $$;

grant execute on function public.resolve_junction(uuid, text, uuid, bigint) to authenticated;
