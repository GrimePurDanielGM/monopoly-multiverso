-- Fase 5 (corrección) — Una sola acción de cárcel por turno. Estando preso, el jugador puede elegir UNA
-- acción por turno (intentar dobles / pagar 50 / usar carta). Si tras ella sigue preso (intento fallido o
-- salida forzada sin saldo), no puede hacer otra acción de cárcel hasta su siguiente turno: debe finalizar.
-- Se modela con game_jail.action_turn = turn_number en que actuó. El backend lo bloquea (no solo la UI).

alter table public.game_jail add column if not exists action_turn int not null default 0;

-- ── roll_and_move: el intento de dobles cuenta como la acción de cárcel del turno ──
create or replace function public.roll_and_move(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; v_cur text; d1 int; d2 int; v_move jsonb; v_res jsonb;
        v_jail_board text; v_turns int; v_action_turn int; v_bal bigint; v_ver bigint; v_jailed boolean;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.pending_junction is not null then raise exception 'JUNCTION_PENDING'; end if;
  if rt.pending_card is not null then raise exception 'CARD_PENDING'; end if;
  if rt.pending_payment is not null then raise exception 'PAYMENT_PENDING'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  perform public._p4_ensure_guardians(p_game);
  perform public._p5_ensure_decks(p_game);

  select board_key, jail_turns, action_turn into v_jail_board, v_turns, v_action_turn
    from public.game_jail where game_id=p_game and player_ref=me.public_ref;
  v_jailed := found;
  -- Una sola acción de cárcel por turno: si ya actuó este turno y sigue preso, debe finalizar el turno.
  if v_jailed and v_action_turn = rt.turn_number then raise exception 'JAIL_ACTION_ALREADY_TAKEN'; end if;

  d1 := floor(random() * 6)::int + 1;
  d2 := floor(random() * 6)::int + 1;

  if v_jailed then
    if d1 = d2 then
      update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', me.public_ref, 'jail', 'doubles') where game_id = p_game;
      delete from public.game_jail where game_id=p_game and player_ref=me.public_ref;
      perform public._audit(p_game, 'jail_released_by_doubles', auth.uid(), me.id, array[me.id], null, jsonb_build_object('d1', d1, 'd2', d2), null, false);
      v_move := public._p4_apply_move(p_game, me, d1 + d2, p_request_id, 'roll');
      perform public._emit_active_signal(p_game);
      v_res := v_move || jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'jail_result', 'doubles');
    else
      v_turns := v_turns + 1;
      if v_turns >= 3 then
        select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
        if v_bal >= 50 then
          update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', me.public_ref, 'jail', 'forced_paid') where game_id = p_game;
          perform public._p2_move(p_game, me.public_ref, null, 50);
          perform public._p2_post(p_game, 'jail_release_payment', me.public_ref, null, 50, null, null, null, me.public_ref, null, gen_random_uuid());
          perform public._p5_pot_add(p_game, 50);
          delete from public.game_jail where game_id=p_game and player_ref=me.public_ref;
          perform public._audit(p_game, 'jail_forced_release_after_3_turns', auth.uid(), me.id, array[me.id], null, jsonb_build_object('amount', 50, 'd1', d1, 'd2', d2), null, false);
          v_move := public._p4_apply_move(p_game, me, d1 + d2, p_request_id, 'roll');
          perform public._emit_active_signal(p_game);
          v_res := v_move || jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'jail_result', 'forced_paid');
        else
          -- Sigue preso con pago pendiente: marca la acción del turno (no podrá intentar/pagar/usar carta otra vez).
          update public.game_jail set jail_turns = v_turns, action_turn = rt.turn_number where game_id=p_game and player_ref=me.public_ref;
          update public.game_runtime set
            last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', me.public_ref, 'jail', 'forced_pending'),
            pending_payment = jsonb_build_object('kind', 'jail_forced', 'player_ref', me.public_ref, 'amount', 50,
              'board', v_jail_board, 'space_index', 10, 'space_name', 'Cárcel') where game_id = p_game;
          v_ver := public._p2_bump(p_game);
          perform public._audit(p_game, 'jail_forced_payment_pending', auth.uid(), me.id, array[me.id], null, jsonb_build_object('amount', 50), null, false);
          perform public._emit_active_signal(p_game);
          v_res := jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'jail_result', 'forced_pending', 'runtime_version', v_ver);
        end if;
      else
        -- Intento fallido (1 o 2): no se mueve, suma el intento y marca la acción del turno.
        update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', me.public_ref, 'jail', 'failed') where game_id = p_game;
        update public.game_jail set jail_turns = v_turns, action_turn = rt.turn_number where game_id=p_game and player_ref=me.public_ref;
        v_ver := public._p2_bump(p_game);
        perform public._audit(p_game, 'jail_attempt_failed', auth.uid(), me.id, array[me.id], null, jsonb_build_object('jail_turns', v_turns, 'd1', d1, 'd2', d2), null, false);
        perform public._emit_active_signal(p_game);
        v_res := jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'jail_result', 'failed', 'jail_turns', v_turns, 'runtime_version', v_ver);
      end if;
    end if;
    perform public._p2_save(p_game, p_request_id, 'roll_and_move', v_res);
    return v_res;
  end if;

  -- Tirada normal (no estoy en la cárcel).
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

-- ── pay_jail_release: bloquea si ya se ejecutó una acción de cárcel este turno ──
create or replace function public.pay_jail_release(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; v_cur text; v_board text; v_action_turn int; v_bal bigint; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select board_key, action_turn into v_board, v_action_turn from public.game_jail where game_id=p_game and player_ref=me.public_ref;
  if not found then raise exception 'NOT_IN_JAIL'; end if;
  if v_action_turn = rt.turn_number then raise exception 'JAIL_ACTION_ALREADY_TAKEN'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < 50 then raise exception 'INSUFFICIENT_FUNDS'; end if;
  perform public._p2_move(p_game, me.public_ref, null, 50);
  perform public._p2_post(p_game, 'jail_release_payment', me.public_ref, null, 50, null, null, null, me.public_ref, null, p_request_id);
  perform public._p5_pot_add(p_game, 50);
  delete from public.game_jail where game_id=p_game and player_ref=me.public_ref;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'jail_released', auth.uid(), me.id, array[me.id], null, jsonb_build_object('via','pay','amount',50), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('released', true, 'via', 'pay', 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'pay_jail_release', v_res);
  return v_res;
end $$;
grant execute on function public.pay_jail_release(uuid, uuid, bigint) to authenticated;

-- ── use_jail_card: bloquea si ya se ejecutó una acción de cárcel este turno ──
create or replace function public.use_jail_card(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; v_cur text; v_id uuid; v_ref text; v_deck text; v_action_turn int; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select action_turn into v_action_turn from public.game_jail where game_id=p_game and player_ref=me.public_ref;
  if not found then raise exception 'NOT_IN_JAIL'; end if;
  if v_action_turn = rt.turn_number then raise exception 'JAIL_ACTION_ALREADY_TAKEN'; end if;
  select gh.id, gh.card_ref, c.deck_key into v_id, v_ref, v_deck
    from public.game_held_cards gh join public.card_catalog c on c.card_ref = gh.card_ref
    where gh.game_id=p_game and gh.player_ref=me.public_ref and c.effect_type='jail_free'
    order by gh.acquired_at limit 1;
  if v_id is null then raise exception 'NO_JAIL_CARD'; end if;
  delete from public.game_held_cards where id = v_id;
  update public.game_card_decks set discard_pile = discard_pile || v_ref, updated_at = now()
    where game_id=p_game and deck_key=v_deck;
  delete from public.game_jail where game_id=p_game and player_ref=me.public_ref;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'jail_card_used', auth.uid(), me.id, array[me.id], null, jsonb_build_object('card', v_ref), null, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('released', true, 'via', 'card', 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'use_jail_card', v_res);
  return v_res;
end $$;
grant execute on function public.use_jail_card(uuid, uuid, bigint) to authenticated;
