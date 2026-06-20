-- Fase 5 (corrección) — Cárcel completa (máx. 3 turnos con intento de dobles) + evento global del bote.
-- · roll_and_move estando en la cárcel = INTENTO de dobles: si saca dobles, sale gratis y se mueve; si no,
--   suma intento sin moverse; al 3er fallo paga 50 forzado (o queda pago pendiente) y se mueve.
-- · pay_pending libera de la cárcel si el pago pendiente es de salida forzada (kind 'jail_forced').
-- · _p5_resolve_landing publica last_global_event al cobrar el bote del Parking (banner para todos).
-- · end_turn ya no incrementa jail_turns (lo hace el intento de dobles). Patrones intactos.

alter table public.game_runtime add column if not exists last_global_event jsonb;

-- ── Resolución de casilla: igual que antes + evento global al cobrar el bote del Parking ──
create or replace function public._p5_resolve_landing(p_game uuid, p_me public.players, p_board text, p_index int, p_request_id uuid, p_from_card boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare sp public.board_spaces; v_amt int; v_bal bigint; v_pot bigint;
begin
  select * into sp from public.board_spaces where board_key = p_board and space_index = p_index and active;
  if not found then return jsonb_build_object('type', 'none'); end if;

  if sp.space_type = 'tax' then
    v_amt := coalesce(sp.tax_amount, 0);
    if v_amt <= 0 then return jsonb_build_object('type', 'none'); end if;
    select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_me.public_ref for update;
    if v_bal >= v_amt then
      perform public._p2_move(p_game, p_me.public_ref, null, v_amt);
      perform public._p2_post(p_game, 'tax_payment', p_me.public_ref, null, v_amt, null, null, null, p_me.public_ref, null, gen_random_uuid());
      perform public._p5_pot_add(p_game, v_amt);
      return jsonb_build_object('type', 'tax', 'name', sp.name, 'amount', v_amt, 'paid', true);
    else
      update public.game_runtime set pending_payment = jsonb_build_object(
          'kind', 'tax', 'player_ref', p_me.public_ref, 'amount', v_amt,
          'board', p_board, 'space_index', p_index, 'space_name', sp.name) where game_id = p_game;
      return jsonb_build_object('type', 'tax', 'name', sp.name, 'amount', v_amt, 'paid', false, 'pending', true);
    end if;
  elsif sp.space_type = 'go_to_jail' then
    return public._p5_send_to_jail(p_game, p_me, p_board, 'space');
  elsif sp.space_type = 'parking' then
    select parking_pot into v_pot from public.game_runtime where game_id = p_game for update;
    if v_pot > 0 then
      perform public._p2_move(p_game, null, p_me.public_ref, v_pot);
      perform public._p2_post(p_game, 'parking_pot_payout', null, p_me.public_ref, v_pot, null, null, null, p_me.public_ref, null, gen_random_uuid());
      update public.game_runtime set parking_pot = 0,
        last_global_event = jsonb_build_object('kind', 'parking_pot_payout', 'player_ref', p_me.public_ref,
          'amount', v_pot, 'event_id', gen_random_uuid()::text) where game_id = p_game;
      return jsonb_build_object('type', 'parking', 'payout', v_pot);
    end if;
    return jsonb_build_object('type', 'parking', 'payout', 0);
  elsif sp.space_type = 'card' and not p_from_card and sp.card_deck is not null then
    return public._p5_draw_card(p_game, p_me, sp.card_deck, p_board, p_request_id);
  end if;
  return jsonb_build_object('type', 'none');
end $$;
revoke all on function public._p5_resolve_landing(uuid, public.players, text, int, uuid, boolean) from public, anon, authenticated;

-- ── roll_and_move: tirar normal, o INTENTO de dobles si estoy en la cárcel ──
create or replace function public.roll_and_move(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; v_cur text; d1 int; d2 int; v_move jsonb; v_res jsonb;
        v_jail_board text; v_turns int; v_bal bigint; v_ver bigint; v_jailed boolean;
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

  d1 := floor(random() * 6)::int + 1;
  d2 := floor(random() * 6)::int + 1;
  select board_key, jail_turns into v_jail_board, v_turns from public.game_jail where game_id=p_game and player_ref=me.public_ref;
  v_jailed := found;

  if v_jailed then
    -- INTENTO de dobles dentro de la cárcel.
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
        -- Tercer intento fallido: salida forzada pagando 50 (al bote) y se mueve; si no puede, pago pendiente.
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
          -- No puede pagar la salida forzada: queda en la cárcel con pago pendiente (pagar/bancarrota).
          update public.game_jail set jail_turns = v_turns where game_id=p_game and player_ref=me.public_ref;
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
        -- Intento fallido (1 o 2): no se mueve, suma el intento.
        update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', me.public_ref, 'jail', 'failed') where game_id = p_game;
        update public.game_jail set jail_turns = v_turns where game_id=p_game and player_ref=me.public_ref;
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

-- ── pay_pending: paga impuesto (tax) o multa forzada de cárcel (jail_forced, que además libera) ──
create or replace function public.pay_pending(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; pp jsonb; v_kind text; v_amt bigint; v_bal bigint; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  pp := rt.pending_payment;
  if pp is null or pp->>'player_ref' <> me.public_ref then raise exception 'NO_PENDING_PAYMENT'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  v_kind := pp->>'kind'; v_amt := (pp->>'amount')::bigint;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < v_amt then raise exception 'INSUFFICIENT_FUNDS'; end if;
  if v_kind = 'jail_forced' then
    perform public._p2_move(p_game, me.public_ref, null, v_amt);
    perform public._p2_post(p_game, 'jail_release_payment', me.public_ref, null, v_amt, null, null, null, me.public_ref, null, p_request_id);
    perform public._p5_pot_add(p_game, v_amt);
    delete from public.game_jail where game_id=p_game and player_ref=me.public_ref;
  else
    perform public._p2_move(p_game, me.public_ref, null, v_amt);
    perform public._p2_post(p_game, 'tax_payment', me.public_ref, null, v_amt, null, null, null, me.public_ref, null, p_request_id);
    perform public._p5_pot_add(p_game, v_amt);
  end if;
  update public.game_runtime set pending_payment = null where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'pending_paid', auth.uid(), me.id, array[me.id], null, jsonb_build_object('kind', v_kind, 'amount', v_amt), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('paid', true, 'kind', v_kind, 'amount', v_amt, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'pay_pending', v_res);
  return v_res;
end $$;
grant execute on function public.pay_pending(uuid, uuid, bigint) to authenticated;

-- ── end_turn: ya NO incrementa jail_turns (lo hace el intento de dobles en roll_and_move) ──
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
  if rt.pending_card is not null and rt.pending_card->>'player_ref' = me.public_ref then raise exception 'CARD_PENDING'; end if;
  if rt.pending_payment is not null and rt.pending_payment->>'player_ref' = me.public_ref then raise exception 'PAYMENT_PENDING'; end if;
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
