-- Fase 4 — RPC de movimiento: mover manual, tirar dados y corrección de posición por anfitrión.
-- Patrón Fase 2: idempotencia (con guard pausa/finished) -> lock game_runtime FOR UPDATE ->
-- permisos -> versión -> efecto -> ledger/posición -> auditoría -> 1 Broadcast.
-- El paso por salida cobra el bonus (banca -> jugador), reconciliable y con sonido de "dinero recibido".

-- ── Núcleo del movimiento (avanza en el mismo tablero; al superar el final, vuelve al inicio
--    y cuenta como pasar por salida -> cobra el bonus). Compartido por move_player y roll_and_move. ──
create or replace function public._p4_apply_move(
  p_game uuid, p_me public.players, p_steps int, p_request_id uuid, p_method text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; pos public.player_positions; v_ring int; v_old int; v_new int; v_passed boolean;
        v_bonus int := 0; sp public.board_spaces; v_ver bigint; v_bal bigint; v_last jsonb;
begin
  select * into g from public.games where id = p_game;
  select * into pos from public.player_positions where game_id = p_game and player_ref = p_me.public_ref for update;
  if not found then raise exception 'NO_POSITION'; end if;
  v_ring := public._p4_ring_size(pos.board_key);
  if v_ring < 1 then raise exception 'BOARD_NOT_FOUND'; end if;

  v_old := pos.space_index;
  v_new := (v_old + p_steps) % v_ring;
  v_passed := (v_old + p_steps) >= v_ring;     -- cruzó (o cayó en) la salida; p_steps<=12 < ring => a lo sumo una vuelta
  update public.player_positions set space_index = v_new, updated_at = now()
    where game_id = p_game and player_ref = p_me.public_ref;

  if v_passed then
    v_bonus := coalesce((g.config->>'start_bonus')::int, 200);
    if v_bonus > 0 then
      perform public._p2_move(p_game, null, p_me.public_ref, v_bonus);
      perform public._p2_post(p_game, 'pass_start_bonus', null, p_me.public_ref, v_bonus,
                              null, null, null, p_me.public_ref, null, p_request_id);
    end if;
  end if;

  select * into sp from public.board_spaces where board_key = pos.board_key and space_index = v_new and active;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'player_moved', auth.uid(), p_me.id, array[p_me.id],
            jsonb_build_object('board', pos.board_key, 'from', v_old),
            jsonb_build_object('board', pos.board_key, 'to', v_new, 'steps', p_steps, 'method', p_method,
                               'passed_start', v_passed, 'bonus', v_bonus,
                               'space', sp.space_ref, 'space_type', sp.space_type, 'property', sp.property_ref), null, false);
  if v_passed then
    perform public._audit(p_game, 'passed_start', auth.uid(), p_me.id, array[p_me.id], null,
              jsonb_build_object('bonus', v_bonus), null, true);
  end if;

  v_last := jsonb_build_object('player_ref', p_me.public_ref, 'board', pos.board_key, 'from', v_old, 'to', v_new,
              'steps', p_steps, 'method', p_method, 'passed_start', v_passed, 'bonus', v_bonus,
              'space_ref', sp.space_ref, 'space_name', sp.name, 'space_type', sp.space_type, 'property_ref', sp.property_ref);
  update public.game_runtime set last_move = v_last where game_id = p_game;

  select balance into v_bal from public.player_balances where game_id = p_game and player_ref = p_me.public_ref;
  return jsonb_build_object('from', v_old, 'to', v_new, 'steps', p_steps, 'passed_start', v_passed, 'bonus', v_bonus,
           'board', pos.board_key, 'space_ref', sp.space_ref, 'space_name', sp.name,
           'space_type', sp.space_type, 'property_ref', sp.property_ref, 'balance', v_bal, 'runtime_version', v_ver);
end $$;
revoke all on function public._p4_apply_move(uuid, public.players, int, uuid, text) from public, anon, authenticated;

-- ── move_player: SOLO el jugador actual y activo; 1..12; running; idempotente ──────
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
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  update public.game_runtime set last_roll = null where game_id = p_game;   -- movimiento manual: sin tirada
  v_res := public._p4_apply_move(p_game, me, p_steps, p_request_id, 'manual');
  perform public._emit_active_signal(p_game);
  perform public._p2_save(p_game, p_request_id, 'move_player', v_res);
  return v_res;
end $$;

-- ── roll_and_move: SOLO el jugador actual; dos dados 1-6; mueve la suma; idempotente ──
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
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  d1 := floor(random() * 6)::int + 1;
  d2 := floor(random() * 6)::int + 1;
  update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', me.public_ref)
    where game_id = p_game;
  v_move := public._p4_apply_move(p_game, me, d1 + d2, p_request_id, 'roll');
  perform public._audit(p_game, 'player_rolled', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2,
                               'from', (v_move->>'from')::int, 'to', (v_move->>'to')::int), null, false);
  perform public._emit_active_signal(p_game);
  v_res := v_move || jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2);
  perform public._p2_save(p_game, p_request_id, 'roll_and_move', v_res);
  return v_res;
end $$;

-- ── host_set_player_position: SOLO anfitrión; motivo obligatorio; corrige posición ──
-- No cobra salida ni dispara compra/alquiler: solo coloca la ficha. Permite jugador activo o
-- espectador (bancarrota) para corrección; bloqueado en pausa/finalización (como las correcciones).
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
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'host_set_position', auth.uid(), g.host_player_id, array[me_p.id],
            jsonb_build_object('board', old_pos.board_key, 'space', old_pos.space_index),
            jsonb_build_object('board', p_board_key, 'space', p_space_index), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('player_ref', p_player_ref, 'board', p_board_key, 'space_index', p_space_index, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'host_set_player_position', v_res);
  return v_res;
end $$;

grant execute on function public.move_player(uuid, int, uuid, bigint)                              to authenticated;
grant execute on function public.roll_and_move(uuid, uuid, bigint)                                 to authenticated;
grant execute on function public.host_set_player_position(uuid, text, text, int, text, uuid, bigint) to authenticated;
