-- Fase 5 — Casillas especiales: RPC. Resolución del efecto al CAER en una casilla (impuesto, carta,
-- ve-a-la-cárcel, parking) integrada en el movimiento; cárcel (bloqueo + salida) y cartas (robo + efectos).
-- Reproduce _p4_apply_move / move_player / roll_and_move / resolve_junction / end_turn (Fase 4) añadiendo
-- el enganche de efectos y los bloqueos de cárcel/carta/pago. Patrones intactos (idem/lock/version/audit/
-- broadcast). Sin casas/hoteles/hipotecas. Las cartas no soportadas quedan en resolución manual.

-- ── Bote de Parking: acumula con tope 2.500 (el excedente se queda en banca) ──
create or replace function public._p5_pot_add(p_game uuid, p_amount bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.game_runtime set parking_pot = least(2500, parking_pot + greatest(p_amount, 0)) where game_id = p_game;
end $$;
revoke all on function public._p5_pot_add(uuid, bigint) from public, anon, authenticated;

-- ── Enviar a la cárcel: mueve a la casilla 10 del tablero (sin cobrar salida) y marca in_jail ──
create or replace function public._p5_send_to_jail(p_game uuid, p_me public.players, p_board text, p_source text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.player_positions set board_key = p_board, space_index = 10, updated_at = now()
    where game_id = p_game and player_ref = p_me.public_ref;
  insert into public.game_jail(game_id, player_ref, board_key, jail_turns)
    values (p_game, p_me.public_ref, p_board, 0)
    on conflict (game_id, player_ref) do update set board_key = excluded.board_key, jail_turns = 0;
  perform public._audit(p_game, 'sent_to_jail', auth.uid(), p_me.id, array[p_me.id], null,
            jsonb_build_object('board', p_board, 'source', p_source), null, true);
  return jsonb_build_object('type', 'go_to_jail', 'jailed', true, 'board', p_board);
end $$;
revoke all on function public._p5_send_to_jail(uuid, public.players, text, text) from public, anon, authenticated;

-- ── Robar una carta del mazo y aplicar su efecto (o dejarla pendiente si es de resolución manual) ──
create or replace function public._p5_draw_card(p_game uuid, p_me public.players, p_deck text, p_board text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_draw text[]; v_discard text[]; v_ref text; c public.card_catalog; v_ring int; v_idx int;
        v_bal bigint; v_pay bigint; v_bonus int; g public.games; v_manual boolean := false; v_did text; r record; v_order text[];
begin
  perform public._p5_ensure_decks(p_game);
  select turn_order_refs into v_order from public.game_runtime where game_id = p_game;
  select draw_pile, discard_pile into v_draw, v_discard
    from public.game_card_decks where game_id = p_game and deck_key = p_deck for update;
  if array_length(v_draw, 1) is null then v_draw := v_discard; v_discard := '{}'; end if;   -- rebaraja en orden
  if array_length(v_draw, 1) is null then
    return jsonb_build_object('type', 'card', 'deck', p_deck, 'empty', true);
  end if;
  v_ref := v_draw[1];
  v_draw := v_draw[2:];
  select * into c from public.card_catalog where card_ref = v_ref;
  select * into g from public.games where id = p_game;

  if c.effect_type = 'bank_credit' then
    perform public._p2_move(p_game, null, p_me.public_ref, c.amount);
    perform public._p2_post(p_game, 'card_bank_payment', null, p_me.public_ref, c.amount, null, null, null, p_me.public_ref, null, gen_random_uuid());
  elsif c.effect_type = 'bank_debit' then
    select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_me.public_ref for update;
    v_pay := least(c.amount, v_bal);                 -- mejor esfuerzo (Fase 5): paga lo que tenga
    if v_pay > 0 then
      perform public._p2_move(p_game, p_me.public_ref, null, v_pay);
      perform public._p2_post(p_game, 'card_bank_charge', p_me.public_ref, null, v_pay, null, null, null, p_me.public_ref, null, gen_random_uuid());
    end if;
  elsif c.effect_type = 'each_player_credit' then    -- cada otro jugador me paga (lo que pueda)
    for r in select p.public_ref from public.players p
             where p.game_id=p_game and p.public_ref = any(v_order)
               and p.public_ref <> p_me.public_ref and p.bankrupt_at is null loop
      select balance into v_bal from public.player_balances where game_id=p_game and player_ref=r.public_ref for update;
      v_pay := least(c.amount, v_bal);
      if v_pay > 0 then
        perform public._p2_move(p_game, r.public_ref, p_me.public_ref, v_pay);
        perform public._p2_post(p_game, 'card_player_charge', r.public_ref, p_me.public_ref, v_pay, null, null, null, p_me.public_ref, null, gen_random_uuid());
      end if;
    end loop;
  elsif c.effect_type = 'each_player_debit' then     -- pago a cada otro jugador (lo que pueda)
    for r in select p.public_ref from public.players p
             where p.game_id=p_game and p.public_ref = any(v_order)
               and p.public_ref <> p_me.public_ref and p.bankrupt_at is null loop
      select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_me.public_ref for update;
      v_pay := least(c.amount, v_bal);
      if v_pay > 0 then
        perform public._p2_move(p_game, p_me.public_ref, r.public_ref, v_pay);
        perform public._p2_post(p_game, 'card_player_payment', p_me.public_ref, r.public_ref, v_pay, null, null, null, p_me.public_ref, null, gen_random_uuid());
      end if;
    end loop;
  elsif c.effect_type = 'to_start' then
    update public.player_positions set board_key = p_board, space_index = 0, updated_at = now()
      where game_id=p_game and player_ref=p_me.public_ref;
    v_bonus := coalesce((g.config->>'start_bonus')::int, 200);
    if v_bonus > 0 then
      perform public._p2_move(p_game, null, p_me.public_ref, v_bonus);
      perform public._p2_post(p_game, 'pass_start_bonus', null, p_me.public_ref, v_bonus, null, null, null, p_me.public_ref, null, gen_random_uuid());
    end if;
  elsif c.effect_type = 'to_jail' then
    perform public._p5_send_to_jail(p_game, p_me, p_board, 'card');
  elsif c.effect_type = 'back_steps' then
    v_ring := public._p4_ring_size(p_board);
    select space_index into v_idx from public.player_positions where game_id=p_game and player_ref=p_me.public_ref;
    update public.player_positions set space_index = ((v_idx - c.amount) % v_ring + v_ring) % v_ring, updated_at = now()
      where game_id=p_game and player_ref=p_me.public_ref;
  elsif c.effect_type = 'jail_free' then
    insert into public.game_held_cards(game_id, player_ref, card_ref) values (p_game, p_me.public_ref, v_ref);
  elsif c.effect_type = 'manual' then
    v_manual := true;
  end if;

  -- Persistencia del mazo: conservable -> a la mano; manual -> al descarte al resolver; resto -> al descarte.
  if c.effect_type not in ('jail_free', 'manual') then v_discard := v_discard || v_ref; end if;
  update public.game_card_decks set draw_pile = v_draw, discard_pile = v_discard, updated_at = now()
    where game_id = p_game and deck_key = p_deck;

  v_did := gen_random_uuid()::text;
  update public.game_runtime set last_card_draw = jsonb_build_object(
      'draw_id', v_did, 'player_ref', p_me.public_ref, 'deck_key', p_deck, 'board_key', p_board,
      'card_ref', c.card_ref, 'title', c.title, 'description', c.description, 'effect_type', c.effect_type,
      'amount', c.amount, 'keepable', c.keepable, 'temporary', c.temporary, 'manual', v_manual)
    where game_id = p_game;
  if v_manual then
    update public.game_runtime set pending_card = jsonb_build_object(
        'player_ref', p_me.public_ref, 'card_ref', c.card_ref, 'deck_key', p_deck,
        'title', c.title, 'description', c.description) where game_id = p_game;
  end if;
  perform public._audit(p_game, 'card_drawn', auth.uid(), p_me.id, array[p_me.id], null,
            jsonb_build_object('deck', p_deck, 'card', c.card_ref, 'effect', c.effect_type, 'manual', v_manual), null, true);
  return jsonb_build_object('type', 'card', 'deck', p_deck, 'card_ref', c.card_ref, 'title', c.title,
           'effect_type', c.effect_type, 'manual', v_manual, 'keepable', c.keepable);
end $$;
revoke all on function public._p5_draw_card(uuid, public.players, text, text, uuid) from public, anon, authenticated;

-- ── Resolver el efecto de la casilla en la que se cae. Devuelve el efecto (no bumpea ni emite). ──
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
      update public.game_runtime set parking_pot = 0 where game_id = p_game;
      return jsonb_build_object('type', 'parking', 'payout', v_pot);
    end if;
    return jsonb_build_object('type', 'parking', 'payout', 0);
  elsif sp.space_type = 'card' and not p_from_card and sp.card_deck is not null then
    return public._p5_draw_card(p_game, p_me, sp.card_deck, p_board, p_request_id);
  end if;
  return jsonb_build_object('type', 'none');
end $$;
revoke all on function public._p5_resolve_landing(uuid, public.players, text, int, uuid, boolean) from public, anon, authenticated;

-- ── Núcleo del movimiento (Fase 4 + efecto de casilla al caer) ──
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
        'space_ref', v_jref, 'space_name', v_jname, 'space_type', 'jail', 'property_ref', null, 'pending_junction', true, 'effect', null)
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
  update public.game_runtime set last_move = v_last where game_id = p_game;
  select balance into v_bal from public.player_balances where game_id = p_game and player_ref = p_me.public_ref;
  return jsonb_build_object('from', v_old, 'to', v_new, 'steps', p_steps, 'passed_start', v_passed, 'bonus', v_bonus,
           'board', pos.board_key, 'space_ref', sp.space_ref, 'space_name', sp.name,
           'space_type', sp.space_type, 'property_ref', sp.property_ref, 'effect', v_eff, 'balance', v_bal, 'runtime_version', v_ver);
end $$;
revoke all on function public._p4_apply_move(uuid, public.players, int, uuid, text) from public, anon, authenticated;

-- ── move_player / roll_and_move: además bloquean si estás en la cárcel o con carta/pago pendiente ──
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
  if rt.pending_card is not null then raise exception 'CARD_PENDING'; end if;
  if rt.pending_payment is not null then raise exception 'PAYMENT_PENDING'; end if;
  if exists (select 1 from public.game_jail where game_id=p_game and player_ref=me.public_ref) then raise exception 'IN_JAIL'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  perform public._p4_ensure_guardians(p_game);
  perform public._p5_ensure_decks(p_game);
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
  if rt.pending_card is not null then raise exception 'CARD_PENDING'; end if;
  if rt.pending_payment is not null then raise exception 'PAYMENT_PENDING'; end if;
  if exists (select 1 from public.game_jail where game_id=p_game and player_ref=me.public_ref) then raise exception 'IN_JAIL'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  perform public._p4_ensure_guardians(p_game);
  perform public._p5_ensure_decks(p_game);
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

-- ── resolve_junction: tras colocar al jugador, resuelve el efecto de su casilla destino (p. ej. Parking) ──
create or replace function public.resolve_junction(p_game uuid, p_direction text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; g public.games; v_idem jsonb; v_ver bigint; pj jsonb;
        v_board text; v_j int; v_remaining int; v_link_board text; v_link_index int; v_toll int; v_guards text;
        v_paid boolean := false; v_nb text; v_ringn int; v_ni int; v_passed boolean := false; v_bonus int := 0;
        sp public.board_spaces; v_bal bigint; v_eff jsonb; v_res jsonb;
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
  perform public._p5_ensure_decks(p_game);
  select links_to_board, links_to_index, coalesce(guardian_toll,0) into v_link_board, v_link_index, v_toll
    from public.board_spaces where board_key = v_board and guardian and active limit 1;
  select guards into v_guards from public.game_guardians where game_id = p_game and board_key = v_board;

  if p_direction = v_guards then
    select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
    if v_bal < v_toll then raise exception 'INSUFFICIENT_FUNDS'; end if;
    if v_toll > 0 then
      perform public._p2_move(p_game, me.public_ref, null, v_toll);
      perform public._p2_post(p_game, 'guardian_toll', me.public_ref, null, v_toll, null, null, null, me.public_ref, null, p_request_id);
      v_paid := true;
    end if;
  else
    update public.game_guardians set guards = p_direction, updated_at = now() where game_id = p_game and board_key = v_board;
  end if;

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
      perform public._p2_post(p_game, 'pass_start_bonus', null, me.public_ref, v_bonus, null, null, null, me.public_ref, null, gen_random_uuid());
    end if;
  end if;
  update public.player_positions set board_key = v_nb, space_index = v_ni, updated_at = now()
    where game_id = p_game and player_ref = me.public_ref;
  update public.game_runtime set pending_junction = null where game_id = p_game;
  select * into sp from public.board_spaces where board_key = v_nb and space_index = v_ni and active;
  v_eff := public._p5_resolve_landing(p_game, me, v_nb, v_ni, p_request_id, false);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'junction_resolved', auth.uid(), me.id, array[me.id],
            jsonb_build_object('board', v_board, 'junction', v_j),
            jsonb_build_object('direction', p_direction, 'paid_toll', v_paid, 'toll', case when v_paid then v_toll else 0 end,
                               'board', v_nb, 'to', v_ni, 'bonus', v_bonus, 'effect', v_eff), null, false);
  update public.game_runtime set last_move = jsonb_build_object('player_ref', me.public_ref, 'board', v_nb,
      'from', v_j, 'to', v_ni, 'steps', v_remaining, 'method', case when p_direction='cross' then 'cross' else 'continue' end,
      'passed_start', v_passed, 'bonus', v_bonus, 'space_ref', sp.space_ref, 'space_name', sp.name,
      'space_type', sp.space_type, 'property_ref', sp.property_ref, 'pending_junction', false, 'effect', v_eff) where game_id = p_game;
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('direction', p_direction, 'paid_toll', v_paid, 'board', v_nb, 'space_index', v_ni,
             'space_ref', sp.space_ref, 'space_name', sp.name, 'property_ref', sp.property_ref, 'effect', v_eff, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'resolve_junction', v_res);
  return v_res;
end $$;

-- ── end_turn: bloquea también si tienes carta o pago pendiente de resolver ──
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
  -- Si el jugador en turno está en la cárcel, su turno cuenta (jail_turns++) pero no resuelve la salida.
  update public.game_jail set jail_turns = jail_turns + 1 where game_id = p_game and player_ref = me.public_ref;
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

-- ── Salir de la cárcel pagando 50 (la multa alimenta el bote del Parking) ──
create or replace function public.pay_jail_release(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; v_cur text; v_board text; v_bal bigint; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select board_key into v_board from public.game_jail where game_id=p_game and player_ref=me.public_ref;
  if not found then raise exception 'NOT_IN_JAIL'; end if;
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

-- ── Salir de la cárcel usando una carta "Sal de la cárcel gratis" (se descarta) ──
create or replace function public.use_jail_card(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; v_cur text; v_id uuid; v_ref text; v_deck text; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if not exists (select 1 from public.game_jail where game_id=p_game and player_ref=me.public_ref) then raise exception 'NOT_IN_JAIL'; end if;
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

-- ── Marcar como resuelta una carta de resolución manual ──
create or replace function public.resolve_card(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; pc jsonb; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  pc := rt.pending_card;
  if pc is null or pc->>'player_ref' <> me.public_ref then raise exception 'NO_PENDING_CARD'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  update public.game_card_decks set discard_pile = discard_pile || (pc->>'card_ref'), updated_at = now()
    where game_id=p_game and deck_key = pc->>'deck_key';
  update public.game_runtime set pending_card = null where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'card_resolved', auth.uid(), me.id, array[me.id], null, jsonb_build_object('card', pc->>'card_ref'), null, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('resolved', true, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'resolve_card', v_res);
  return v_res;
end $$;
grant execute on function public.resolve_card(uuid, uuid, bigint) to authenticated;

-- ── Pagar un impuesto que quedó pendiente por falta de saldo (cuando ya se puede) ──
create or replace function public.pay_pending(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; pp jsonb; v_amt bigint; v_bal bigint; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  pp := rt.pending_payment;
  if pp is null or pp->>'player_ref' <> me.public_ref then raise exception 'NO_PENDING_PAYMENT'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  v_amt := (pp->>'amount')::bigint;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < v_amt then raise exception 'INSUFFICIENT_FUNDS'; end if;
  perform public._p2_move(p_game, me.public_ref, null, v_amt);
  perform public._p2_post(p_game, 'tax_payment', me.public_ref, null, v_amt, null, null, null, me.public_ref, null, p_request_id);
  perform public._p5_pot_add(p_game, v_amt);
  update public.game_runtime set pending_payment = null where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'pending_paid', auth.uid(), me.id, array[me.id], null, jsonb_build_object('kind', pp->>'kind', 'amount', v_amt), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('paid', true, 'amount', v_amt, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'pay_pending', v_res);
  return v_res;
end $$;
grant execute on function public.pay_pending(uuid, uuid, bigint) to authenticated;

-- ── host_set_player_position: además limpia cárcel y pendientes del jugador recolocado ──
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
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'host_set_position', auth.uid(), g.host_player_id, array[me_p.id],
            jsonb_build_object('board', old_pos.board_key, 'space', old_pos.space_index),
            jsonb_build_object('board', p_board_key, 'space', p_space_index), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('player_ref', p_player_ref, 'board', p_board_key, 'space_index', p_space_index, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'host_set_player_position', v_res);
  return v_res;
end $$;
