-- Fase 5 (corrección) — Identificador de "caída" para bloquear el doble pago de alquiler.
-- game_runtime.landing_seq: contador monótono que avanza en CADA aterrizaje del jugador activo
--   (_p4_apply_move) y en CADA recolocación del anfitrión (host_set_player_position).
-- game_runtime.rent_resolved_seq: el landing_seq cuyo alquiler ya se pagó. Si landing_seq <= rent_resolved_seq,
--   la caída actual ya está resuelta (no se puede volver a pagar). Una nueva caída (++landing_seq) reabre el pago.

alter table public.game_runtime add column if not exists landing_seq bigint not null default 0;
alter table public.game_runtime add column if not exists rent_resolved_seq bigint not null default 0;

-- _p4_apply_move: reproduce 0040 (detección de cruce + _p5_resolve_landing) y SOLO añade ++landing_seq
-- en los dos puntos donde se actualiza last_move (parada en cruce y aterrizaje normal): cada uno es una caída.
create or replace function public._p4_apply_move(
  p_game uuid, p_me public.players, p_steps int, p_request_id uuid, p_method text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; pos public.player_positions; v_ring int; v_old int; v_new int; v_passed boolean;
        v_bonus int := 0; sp public.board_spaces; v_ver bigint; v_bal bigint; v_last jsonb;
        v_j int; v_d int; v_remaining int; v_jname text; v_jref text; v_eff jsonb;
begin
  select * into g from public.games where id = p_game;
  select * into pos from public.player_positions where game_id = p_game and player_ref = p_me.public_ref for update;
  if not found then raise exception 'NO_POSITION'; end if;
  v_ring := public._p4_ring_size(pos.board_key);
  if v_ring < 1 then raise exception 'BOARD_NOT_FOUND'; end if;
  v_old := pos.space_index;

  select s.space_index into v_j from public.board_spaces s
    where s.board_key = pos.board_key and s.guardian and s.active limit 1;
  if v_j is not null then
    v_d := (v_j - v_old + v_ring) % v_ring;
    if v_d = 0 then v_d := v_ring; end if;
  end if;

  if v_j is not null and p_steps > v_d then
    v_remaining := p_steps - v_d;
    v_passed := (v_old + v_d) >= v_ring;
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
        'space_ref', v_jref, 'space_name', v_jname, 'space_type', 'jail', 'property_ref', null, 'pending_junction', true, 'effect', null),
        landing_seq = landing_seq + 1
      where game_id = p_game;
    select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_me.public_ref;
    return jsonb_build_object('pending_junction', true, 'junction_index', v_j, 'remaining', v_remaining,
             'board', pos.board_key, 'balance', v_bal, 'runtime_version', v_ver);
  end if;

  -- Movimiento normal: avanza, cobra salida si procede, y resuelve el efecto de la casilla.
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
  v_eff := public._p5_resolve_landing(p_game, p_me, pos.board_key, v_new, p_request_id, false);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'player_moved', auth.uid(), p_me.id, array[p_me.id],
            jsonb_build_object('board', pos.board_key, 'from', v_old),
            jsonb_build_object('board', pos.board_key, 'to', v_new, 'steps', p_steps, 'method', p_method,
                               'passed_start', v_passed, 'bonus', v_bonus, 'space', sp.space_ref, 'space_type', sp.space_type, 'property', sp.property_ref, 'effect', v_eff), null, false);
  if v_passed then
    perform public._audit(p_game, 'passed_start', auth.uid(), p_me.id, array[p_me.id], null, jsonb_build_object('bonus', v_bonus), null, true);
  end if;
  v_last := jsonb_build_object('player_ref', p_me.public_ref, 'board', pos.board_key, 'from', v_old, 'to', v_new,
              'steps', p_steps, 'method', p_method, 'passed_start', v_passed, 'bonus', v_bonus,
              'space_ref', sp.space_ref, 'space_name', sp.name, 'space_type', sp.space_type, 'property_ref', sp.property_ref,
              'pending_junction', false, 'effect', v_eff);
  update public.game_runtime set last_move = v_last, landing_seq = landing_seq + 1 where game_id = p_game;
  select balance into v_bal from public.player_balances where game_id = p_game and player_ref = p_me.public_ref;
  return jsonb_build_object('from', v_old, 'to', v_new, 'steps', p_steps, 'passed_start', v_passed, 'bonus', v_bonus,
           'board', pos.board_key, 'space_ref', sp.space_ref, 'space_name', sp.name,
           'space_type', sp.space_type, 'property_ref', sp.property_ref, 'effect', v_eff, 'balance', v_bal, 'runtime_version', v_ver);
end $$;
revoke all on function public._p4_apply_move(uuid, public.players, int, uuid, text) from public, anon, authenticated;

-- host_set_player_position: la recolocación es una nueva caída (++landing_seq), pero NO marca alquiler resuelto.
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
  if rt.pending_junction is not null and rt.pending_junction->>'player_ref' = p_player_ref then
    update public.game_runtime set pending_junction = null where game_id = p_game;
  end if;
  if rt.pending_card is not null and rt.pending_card->>'player_ref' = p_player_ref then
    update public.game_runtime set pending_card = null where game_id = p_game;
  end if;
  if rt.pending_payment is not null and rt.pending_payment->>'player_ref' = p_player_ref then
    update public.game_runtime set pending_payment = null where game_id = p_game;
  end if;
  delete from public.game_jail where game_id = p_game and player_ref = p_player_ref;
  update public.game_runtime set landing_seq = landing_seq + 1 where game_id = p_game;  -- nueva caída (no resuelta)
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'host_set_position', auth.uid(), g.host_player_id, array[me_p.id],
            jsonb_build_object('board', old_pos.board_key, 'space', old_pos.space_index),
            jsonb_build_object('board', p_board_key, 'space', p_space_index), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('player_ref', p_player_ref, 'board', p_board_key, 'space_index', p_space_index, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'host_set_player_position', v_res);
  return v_res;
end $$;
