-- ============================================================================
-- Feature E — Retorno de inversión al pasar por Salida.
-- Opción de partida start_invest_pct (0..100, def. 0 = solo el sueldo normal). Al pasar por Salida, además de
-- los 200 € (start_bonus), el jugador cobra start_invest_pct % del valor de lo que posee (propiedades + casas +
-- hoteles). Centralizado en _p9_pay_start y aplicado en TODOS los sitios donde se cobra el sueldo de Salida.
-- ============================================================================

-- Helper centralizado del sueldo de Salida: base (start_bonus) + retorno de inversión (start_invest_pct %
-- sobre el valor de propiedades + casas + hoteles del jugador). Mueve el dinero, registra el asiento y devuelve
-- el total. Usado por _p4_apply_move, resolve_junction y _p5_draw_card (to_start/to_space/to_nearest).
create or replace function public._p9_pay_start(p_game uuid, p_ref text, p_req uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_base int; v_pct int; v_inv bigint; v_total int;
begin
  select coalesce((config->>'start_bonus')::int, 200), coalesce((config->>'start_invest_pct')::int, 0)
    into v_base, v_pct from public.games where id = p_game;
  v_total := v_base;
  if v_pct > 0 then
    select coalesce(sum(c.price + coalesce(s.houses,0)*coalesce(c.house_cost,0)
                        + (case when coalesce(s.has_hotel,false) then coalesce(c.hotel_cost,0) else 0 end)), 0)
      into v_inv
      from public.property_ownership o
      join public.property_catalog c on c.property_ref = o.property_ref
      left join public.game_property_state s on s.game_id = o.game_id and s.property_ref = o.property_ref
      where o.game_id = p_game and o.owner_ref = p_ref and o.released_at is null;
    v_total := v_base + floor(v_inv * v_pct / 100.0)::int;
  end if;
  if v_total > 0 then
    perform public._p2_move(p_game, null, p_ref, v_total);
    perform public._p2_post(p_game, 'pass_start_bonus', null, p_ref, v_total, null, null, null, p_ref, null, coalesce(p_req, gen_random_uuid()));
  end if;
  return v_total;
end $$;
revoke all on function public._p9_pay_start(uuid, text, uuid) from public, anon, authenticated;

-- _p4_apply_move (0049) con el sueldo centralizado.
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
      v_bonus := public._p9_pay_start(p_game, p_me.public_ref, p_request_id);  -- sueldo Salida + retorno de inversión
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
    v_bonus := public._p9_pay_start(p_game, p_me.public_ref, p_request_id);  -- sueldo Salida + retorno de inversión
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

-- resolve_junction (0040) con el sueldo centralizado.
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
    v_bonus := public._p9_pay_start(p_game, me.public_ref, gen_random_uuid());  -- sueldo Salida + retorno de inversión
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
grant execute on function public.resolve_junction(uuid, text, uuid, bigint) to authenticated;

-- _p5_draw_card (0068) con el sueldo centralizado.
create or replace function public._p5_draw_card(p_game uuid, p_me public.players, p_deck text, p_board text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_draw text[]; v_discard text[]; v_ref text; c public.card_catalog; v_ring int; v_idx int;
        v_bal bigint; v_pay bigint; v_bonus int; g public.games; v_manual boolean := false; v_did text; r record; v_order text[];
        v_target int; v_h int; v_hotels int; v_total bigint; v_pc jsonb;
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
    v_pay := least(c.amount, v_bal);                 -- mejor esfuerzo: paga lo que tenga
    if v_pay > 0 then
      perform public._p2_move(p_game, p_me.public_ref, null, v_pay);
      perform public._p2_post(p_game, 'card_bank_charge', p_me.public_ref, null, v_pay, null, null, null, p_me.public_ref, null, gen_random_uuid());
      perform public._p5_pot_add(p_game, v_pay);     -- los pagos de carta van al BOTE
    end if;
  elsif c.effect_type = 'each_player_credit' then    -- cada otro jugador AUTORIZA pagarme (banner por jugador)
    for r in select p.public_ref from public.players p
             where p.game_id=p_game and p.public_ref = any(v_order)
               and p.public_ref <> p_me.public_ref and p.bankrupt_at is null loop
      insert into public.game_card_transfers(game_id, card_ref, payer_ref, payee_ref, amount, authorizer_ref)
        values (p_game, c.card_ref, r.public_ref, p_me.public_ref, c.amount, r.public_ref);
    end loop;
  elsif c.effect_type = 'each_player_debit' then     -- YO autorizo pagar a cada jugador (un banner por pago)
    for r in select p.public_ref from public.players p
             where p.game_id=p_game and p.public_ref = any(v_order)
               and p.public_ref <> p_me.public_ref and p.bankrupt_at is null loop
      insert into public.game_card_transfers(game_id, card_ref, payer_ref, payee_ref, amount, authorizer_ref)
        values (p_game, c.card_ref, p_me.public_ref, r.public_ref, c.amount, p_me.public_ref);
    end loop;
  elsif c.effect_type = 'to_start' then
    update public.player_positions set board_key = p_board, space_index = 0, updated_at = now()
      where game_id=p_game and player_ref=p_me.public_ref;
    v_bonus := public._p9_pay_start(p_game, p_me.public_ref, gen_random_uuid());  -- sueldo Salida + retorno de inversión
  elsif c.effect_type = 'to_jail' then
    perform public._p5_send_to_jail(p_game, p_me, p_board, 'card');
  elsif c.effect_type = 'back_steps' then
    v_ring := public._p4_ring_size(p_board);
    select space_index into v_idx from public.player_positions where game_id=p_game and player_ref=p_me.public_ref;
    update public.player_positions set space_index = ((v_idx - c.amount) % v_ring + v_ring) % v_ring, updated_at = now()
      where game_id=p_game and player_ref=p_me.public_ref;
  elsif c.effect_type = 'to_space' then               -- mueve a casilla concreta (sueldo si avanza y pasa Salida)
    select space_index into v_idx from public.player_positions where game_id=p_game and player_ref=p_me.public_ref;
    update public.player_positions set board_key=p_board, space_index=c.target_index, updated_at=now()
      where game_id=p_game and player_ref=p_me.public_ref;
    if coalesce(c.move_forward,true) and c.target_index <= v_idx then
      v_bonus := public._p9_pay_start(p_game, p_me.public_ref, gen_random_uuid());  -- sueldo Salida + retorno de inversión
    end if;
  elsif c.effect_type = 'to_nearest' then              -- mueve al transporte/utility más cercano (pago especial manual)
    select space_index into v_idx from public.player_positions where game_id=p_game and player_ref=p_me.public_ref;
    v_ring := public._p4_ring_size(p_board);
    select s.space_index into v_target
      from public.board_spaces s join public.property_catalog cc on cc.property_ref=s.property_ref
      where s.board_key=p_board and s.active
        and ((c.target_kind='utility' and cc.kind='utility') or (c.target_kind='transport' and cc.kind in ('transport','station')))
      order by case when ((s.space_index - v_idx + v_ring) % v_ring)=0 then v_ring else ((s.space_index - v_idx + v_ring) % v_ring) end
      limit 1;
    if v_target is not null then
      update public.player_positions set board_key=p_board, space_index=v_target, updated_at=now()
        where game_id=p_game and player_ref=p_me.public_ref;
      if v_target <= v_idx then
        v_bonus := public._p9_pay_start(p_game, p_me.public_ref, gen_random_uuid());  -- sueldo Salida + retorno de inversión
      end if;
    end if;
    v_manual := true;
  elsif c.effect_type = 'repairs' then                 -- reparaciones: cuenta casas/hoteles → bote
    select coalesce(sum(s.houses),0), coalesce(sum(case when s.has_hotel then 1 else 0 end),0)
      into v_h, v_hotels
      from public.game_property_state s
      join public.property_ownership o on o.game_id=s.game_id and o.property_ref=s.property_ref and o.released_at is null and o.owner_ref=p_me.public_ref
      where s.game_id=p_game;
    v_total := coalesce(v_h,0)::bigint*coalesce(c.amount,0) + coalesce(v_hotels,0)::bigint*coalesce(c.amount2,0);
    if v_total > 0 then
      select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_me.public_ref for update;
      v_pay := least(v_total, v_bal);
      if v_pay > 0 then
        perform public._p2_move(p_game, p_me.public_ref, null, v_pay);
        perform public._p2_post(p_game, 'card_bank_charge', p_me.public_ref, null, v_pay, null, null, null, p_me.public_ref, null, gen_random_uuid());
        perform public._p5_pot_add(p_game, v_pay);
      end if;
    end if;
  elsif c.effect_type = 'jail_free' then
    insert into public.game_held_cards(game_id, player_ref, card_ref) values (p_game, p_me.public_ref, v_ref);
  elsif c.effect_type = 'choice' then
    v_manual := true;
  elsif c.effect_type = 'manual' then
    v_manual := true;
  end if;

  -- Persistencia del mazo: conservable -> mano; manual/choice/to_nearest -> descarte al resolver; resto -> descarte.
  if c.effect_type not in ('jail_free', 'manual', 'choice', 'to_nearest') then v_discard := v_discard || v_ref; end if;
  update public.game_card_decks set draw_pile = v_draw, discard_pile = v_discard, updated_at = now()
    where game_id = p_game and deck_key = p_deck;

  v_did := gen_random_uuid()::text;
  update public.game_runtime set last_card_draw = jsonb_build_object(
      'draw_id', v_did, 'player_ref', p_me.public_ref, 'deck_key', p_deck, 'board_key', p_board,
      'card_ref', c.card_ref, 'title', c.title, 'description', c.description, 'effect_type', c.effect_type,
      'amount', c.amount, 'keepable', c.keepable, 'temporary', c.temporary, 'manual', v_manual,
      'manual_instruction', c.manual_instruction)
    where game_id = p_game;
  if v_manual then
    v_pc := jsonb_build_object('player_ref', p_me.public_ref, 'card_ref', c.card_ref, 'deck_key', p_deck,
        'title', c.title, 'description', c.description, 'manual_instruction', c.manual_instruction,
        'kind', case when c.effect_type='choice' then 'choice' else 'manual' end, 'amount', c.amount);
    update public.game_runtime set pending_card = v_pc where game_id = p_game;
  end if;
  perform public._audit(p_game, 'card_drawn', auth.uid(), p_me.id, array[p_me.id], null,
            jsonb_build_object('deck', p_deck, 'card', c.card_ref, 'effect', c.effect_type, 'manual', v_manual), null, true);
  return jsonb_build_object('type', 'card', 'deck', p_deck, 'card_ref', c.card_ref, 'title', c.title,
           'effect_type', c.effect_type, 'manual', v_manual, 'keepable', c.keepable);
end $$;
revoke all on function public._p5_draw_card(uuid, public.players, text, text, uuid) from public, anon, authenticated;

-- update_config (0067) + start_invest_pct.
create or replace function public.update_config(p_game uuid, p_patch jsonb, p_expected_version int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; v_cfg jsonb; v_active_tokens int; v_max int; v_min int;
begin
  g := public._require_host(p_game);
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  if g.version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if p_patch ? 'dice_mode' and (p_patch->>'dice_mode') not in ('virtual_only','physical_allowed','physical_only') then raise exception 'INVALID_DICE_MODE'; end if;
  if p_patch ? 'initial_houses_available' and (p_patch->>'initial_houses_available')::int < 32 then raise exception 'INVALID_BUILDING_STOCK'; end if;
  if p_patch ? 'parking_mode' and (p_patch->>'parking_mode') not in ('pot','roulette') then raise exception 'INVALID_PARKING_MODE'; end if;
  if p_patch ? 'start_invest_pct' and ((p_patch->>'start_invest_pct')::int < 0 or (p_patch->>'start_invest_pct')::int > 100) then raise exception 'INVALID_INVEST_PCT'; end if;
  if p_patch ? 'initial_hotels_available' and (p_patch->>'initial_hotels_available')::int < 12 then raise exception 'INVALID_BUILDING_STOCK'; end if;
  v_cfg := g.config;
  if p_patch ? 'name' then
    if char_length(btrim(p_patch->>'name')) not between 3 and 40 then raise exception 'INVALID_GAME_NAME'; end if;
    update public.games set name=btrim(p_patch->>'name') where id=g.id;
  end if;
  v_cfg := v_cfg
    || (case when p_patch ? 'initial_money'   then jsonb_build_object('initial_money',(p_patch->>'initial_money')::int) else '{}'::jsonb end)
    || (case when p_patch ? 'min_players'     then jsonb_build_object('min_players',(p_patch->>'min_players')::int)   else '{}'::jsonb end)
    || (case when p_patch ? 'max_players'     then jsonb_build_object('max_players',(p_patch->>'max_players')::int)   else '{}'::jsonb end)
    || (case when p_patch ? 'allow_late_join' then jsonb_build_object('allow_late_join',(p_patch->>'allow_late_join')::boolean) else '{}'::jsonb end)
    || (case when p_patch ? 'dice_mode'       then jsonb_build_object('dice_mode',(p_patch->>'dice_mode')) else '{}'::jsonb end)
    || (case when p_patch ? 'initial_houses_available' then jsonb_build_object('initial_houses_available',greatest(32,(p_patch->>'initial_houses_available')::int)) else '{}'::jsonb end)
    || (case when p_patch ? 'initial_hotels_available' then jsonb_build_object('initial_hotels_available',greatest(12,(p_patch->>'initial_hotels_available')::int)) else '{}'::jsonb end)
    || (case when p_patch ? 'allow_build_without_monopoly' then jsonb_build_object('allow_build_without_monopoly',(p_patch->>'allow_build_without_monopoly')::boolean) else '{}'::jsonb end)
    || (case when p_patch ? 'allow_trade_built_properties' then jsonb_build_object('allow_trade_built_properties',(p_patch->>'allow_trade_built_properties')::boolean) else '{}'::jsonb end)
    || (case when p_patch ? 'parking_mode' then jsonb_build_object('parking_mode',(p_patch->>'parking_mode')) else '{}'::jsonb end)
    || (case when p_patch ? 'start_invest_pct' then jsonb_build_object('start_invest_pct',greatest(0,least(100,(p_patch->>'start_invest_pct')::int))) else '{}'::jsonb end);
  v_min := coalesce((v_cfg->>'min_players')::int,6);
  v_max := coalesce((v_cfg->>'max_players')::int,16);
  if v_min < 2 or v_min > v_max or v_max > 16 then raise exception 'INVALID_PLAYER_LIMITS'; end if;
  select count(*) into v_active_tokens from public.token_catalog
    where active and catalog_version=coalesce((v_cfg->>'token_catalog_version')::int,0);
  if v_max > v_active_tokens then raise exception 'MAX_EXCEEDS_TOKENS'; end if;
  update public.games set config=v_cfg, version=version+1 where id=g.id returning * into g;
  perform public._audit(g.id,'config_changed',auth.uid(),null,null,null,g.config,null,false);
  return jsonb_build_object('version',g.version,'config',g.config,'name',g.name);
end $$;

-- _lobby_snapshot (0067) + start_invest_pct.
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
        'token_catalog_version', coalesce((g.config->>'token_catalog_version')::int, 0),
        'dice_mode', coalesce(g.config->>'dice_mode', 'virtual_only'),
        'initial_houses_available', greatest(32, coalesce((g.config->>'initial_houses_available')::int, 32)),
        'initial_hotels_available', greatest(12, coalesce((g.config->>'initial_hotels_available')::int, 12)),
        'allow_build_without_monopoly', coalesce((g.config->>'allow_build_without_monopoly')::boolean, false),
        'allow_trade_built_properties', coalesce((g.config->>'allow_trade_built_properties')::boolean, false),
        'parking_mode', coalesce(g.config->>'parking_mode', 'pot'),
        'start_invest_pct', coalesce((g.config->>'start_invest_pct')::int, 0))),
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

-- get_active_snapshot_by_code (0067) + start_invest_pct.
create or replace function public.get_active_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; rt public.game_runtime; me public.players; v_cur text; v_players jsonb; v_ledger jsonb;
        v_is_host boolean; v_late jsonb; v_props jsonb; v_purchase jsonb; v_auctions jsonb; v_leave jsonb; v_bankrupt jsonb;
        v_building jsonb := '[]'::jsonb; v_my_building jsonb;
        v_start_bonus int; v_boards jsonb; v_spaces jsonb; v_positions jsonb; v_my_pos jsonb; v_current jsonb; v_links jsonb;
        v_my_board text; v_my_index int; v_guards jsonb;
        v_jail jsonb; v_my_jail jsonb; v_decks jsonb; v_held jsonb; v_my_held jsonb; v_pending_card jsonb; v_pending_pay jsonb;
        v_trades_in jsonb; v_trades_out jsonb; v_trade_reviews jsonb := '[]'::jsonb; v_recent_trades jsonb;
        v_card_transfers jsonb;
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
  v_start_bonus := coalesce((g.config->>'start_bonus')::int, 200);

  select jsonb_agg(jsonb_build_object(
           'public_ref', p.public_ref, 'display_name', p.display_name, 'token_id', p.token_id,
           'balance', case when p.public_ref = me.public_ref then b.balance else null end,
           'is_current', p.public_ref = v_cur,
           'status', case when p.bankrupt_at is not null then 'bankrupt' else 'active' end)
           order by case when p.bankrupt_at is not null then 1 else 0 end, array_position(rt.turn_order_refs, p.public_ref))
    into v_players from public.players p
    join public.player_balances b on b.game_id = p.game_id and b.player_ref = p.public_ref
    where p.game_id = g.id and p.kicked_at is null and p.left_at is null
      and (p.public_ref = any(rt.turn_order_refs) or p.bankrupt_at is not null);

  select jsonb_agg(jsonb_build_object(
           'ledger_ref', l.ledger_ref, 'seq', l.seq, 'kind', l.kind, 'from_ref', l.from_ref, 'to_ref', l.to_ref,
           'amount', l.amount, 'before_balance', l.before_balance, 'after_balance', l.after_balance,
           'reason', l.reason, 'actor_ref', l.actor_ref,
           'reverts_ref', (select r.ledger_ref from public.ledger r where r.id = l.reverts_ledger_id),
           'created_at', l.created_at) order by l.seq desc)
    into v_ledger from (select * from public.ledger where game_id = g.id order by seq desc limit 25) l;

  select coalesce(jsonb_agg(jsonb_build_object(
           'property_ref', c.property_ref, 'board_key', c.board_key, 'group_key', c.group_key,
           'name', c.name, 'kind', c.kind, 'price', c.price, 'base_rent', c.base_rent,
           'is_buyable', c.is_buyable, 'sort_order', c.sort_order,
           'rent_1', c.rent_1, 'rent_2', c.rent_2, 'rent_3', c.rent_3, 'rent_4', c.rent_4, 'rent_hotel', c.rent_hotel,
           'house_cost', c.house_cost, 'hotel_cost', c.hotel_cost, 'mortgage_value', c.mortgage_value,
           'unmortgage_cost', case when c.mortgage_value is null then null else ceil(c.mortgage_value * 1.1)::int end,
           'owner_ref', (select o.owner_ref from public.property_ownership o
                          where o.game_id = g.id and o.property_ref = c.property_ref and o.released_at is null),
           'in_auction', exists(select 1 from public.property_auctions a where a.game_id=g.id and a.property_ref=c.property_ref and a.status='active'),
           'houses', coalesce((select s.houses from public.game_property_state s where s.game_id=g.id and s.property_ref=c.property_ref), 0),
           'has_hotel', coalesce((select s.has_hotel from public.game_property_state s where s.game_id=g.id and s.property_ref=c.property_ref), false),
           'mortgaged', coalesce((select s.mortgaged from public.game_property_state s where s.game_id=g.id and s.property_ref=c.property_ref), false),
           'monopoly', (c.kind='street' and public._p6_is_monopoly(g.id, c.property_ref)),
           'rent_due', public._p6_rent_due(g.id, c.property_ref))
           order by c.board_key, c.sort_order), '[]'::jsonb)
    into v_props from public.property_catalog c where c.active;

  select coalesce(jsonb_agg(jsonb_build_object(
           'auction_ref', a.public_ref, 'property_ref', a.property_ref,
           'property_name', (select name from public.property_catalog where property_ref=a.property_ref),
           'high_bid', a.high_bid, 'high_bidder_ref', a.high_bidder_ref,
           'started_by_ref', a.started_by_ref) order by a.started_at), '[]'::jsonb)
    into v_auctions from public.property_auctions a where a.game_id=g.id and a.status='active';

  if v_is_host then
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', pr.public_ref, 'property_ref', pr.property_ref,
             'property_name', (select name from public.property_catalog where property_ref=pr.property_ref),
             'requester_ref', pr.requester_ref,
             'requester_name', (select display_name from public.players where game_id=g.id and public_ref=pr.requester_ref)) order by pr.created_at), '[]'::jsonb)
      into v_purchase from public.property_purchase_requests pr where pr.game_id=g.id and pr.status='pending';
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', lr.public_ref, 'requester_ref', lr.requester_ref,
             'requester_name', (select display_name from public.players where game_id=g.id and public_ref=lr.requester_ref)) order by lr.created_at), '[]'::jsonb)
      into v_leave from public.player_leave_requests lr where lr.game_id=g.id and lr.status='pending';
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', br.public_ref, 'requester_ref', br.requester_ref,
             'requester_name', (select display_name from public.players where game_id=g.id and public_ref=br.requester_ref),
             'kind', br.kind, 'creditor_ref', br.creditor_ref,
             'creditor_name', (select display_name from public.players where game_id=g.id and public_ref=br.creditor_ref),
             'reason', br.reason) order by br.created_at), '[]'::jsonb)
      into v_bankrupt from public.bankruptcy_requests br where br.game_id=g.id and br.status='pending';
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', lr.public_ref, 'name', lr.desired_name, 'token', lr.desired_token, 'device_label', lr.device_label) order by lr.created_at), '[]'::jsonb)
      into v_late from public.late_join_requests lr where lr.game_id=g.id and lr.status='pending';
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', gbr.public_ref, 'property_ref', gbr.property_ref,
             'property_name', (select name from public.property_catalog where property_ref=gbr.property_ref),
             'action', gbr.action, 'requester_ref', gbr.requester_ref,
             'requester_name', (select display_name from public.players where game_id=g.id and public_ref=gbr.requester_ref)) order by gbr.created_at), '[]'::jsonb)
      into v_building from public.game_building_requests gbr where gbr.game_id=g.id and gbr.status='pending';
    -- Fase 7: bandeja de tratos a revisar por el anfitrión.
    select coalesce(jsonb_agg(public._p7_trade_json(t.id) order by t.updated_at), '[]'::jsonb)
      into v_trade_reviews from public.game_trade_proposals t where t.game_id=g.id and t.status='host_review';
  else
    v_purchase := '[]'::jsonb; v_leave := '[]'::jsonb; v_bankrupt := '[]'::jsonb; v_late := '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('property_ref', gbr.property_ref, 'action', gbr.action)), '[]'::jsonb)
    into v_my_building from public.game_building_requests gbr where gbr.game_id=g.id and gbr.requester_ref=me.public_ref and gbr.status='pending';

  -- Fase 7: mis tratos (salientes = los creé; entrantes = dirigidos a mí) activos, e historial reciente.
  select coalesce(jsonb_agg(public._p7_trade_json(t.id) order by t.updated_at desc), '[]'::jsonb) into v_trades_out
    from public.game_trade_proposals t where t.game_id=g.id and t.from_ref=me.public_ref and t.status in ('pending','countered','host_review');
  select coalesce(jsonb_agg(public._p7_trade_json(t.id) order by t.updated_at desc), '[]'::jsonb) into v_trades_in
    from public.game_trade_proposals t where t.game_id=g.id and t.to_ref=me.public_ref and t.status in ('pending','countered','host_review');
  select coalesce(jsonb_agg(public._p7_trade_json(t.id) order by t.ord desc), '[]'::jsonb) into v_recent_trades
    from (select id, coalesce(resolved_at, updated_at) as ord from public.game_trade_proposals
          where game_id=g.id and status in ('executed','rejected','cancelled','invalidated')
            and (from_ref=me.public_ref or to_ref=me.public_ref or v_is_host)
          order by coalesce(resolved_at, updated_at) desc limit 12) t;

  -- C3: transferencias de carta que YO debo autorizar (cobros/pagos «a cada jugador»).
  select coalesce(jsonb_agg(jsonb_build_object(
           'transfer_ref', ct.public_ref, 'amount', ct.amount,
           'payer_ref', ct.payer_ref, 'payee_ref', ct.payee_ref,
           'payer_name', (select display_name from public.players where game_id=g.id and public_ref=ct.payer_ref),
           'payee_name', (select display_name from public.players where game_id=g.id and public_ref=ct.payee_ref)
         ) order by ct.created_at), '[]'::jsonb) into v_card_transfers
    from public.game_card_transfers ct where ct.game_id=g.id and ct.authorizer_ref=me.public_ref and ct.status='pending';

  select coalesce(jsonb_agg(jsonb_build_object(
           'board_key', t.board_key, 'ring_size', t.n, 'start_bonus', v_start_bonus, 'provisional', t.prov) order by t.board_key), '[]'::jsonb)
    into v_boards from (select board_key, count(*)::int as n, bool_or(provisional) as prov from public.board_spaces where active group by board_key) t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'space_ref', s.space_ref, 'board_key', s.board_key, 'space_index', s.space_index,
           'name', s.name, 'space_type', s.space_type, 'property_ref', s.property_ref, 'is_start', s.is_start,
           'provisional', s.provisional, 'guardian', s.guardian, 'links_to_board', s.links_to_board, 'links_to_index', s.links_to_index, 'guardian_toll', s.guardian_toll)
           order by s.board_key, s.space_index), '[]'::jsonb)
    into v_spaces from public.board_spaces s where s.active;

  select coalesce(jsonb_agg(jsonb_build_object(
           'board_key', s.board_key, 'space_index', s.space_index, 'space_type', s.space_type,
           'links_to_board', s.links_to_board, 'links_to_index', s.links_to_index, 'guardian', s.guardian) order by s.board_key, s.space_index), '[]'::jsonb)
    into v_links from public.board_spaces s where s.active and s.links_to_board is not null;
  select coalesce(jsonb_agg(jsonb_build_object('board_key', gg.board_key, 'guards', gg.guards) order by gg.board_key), '[]'::jsonb)
    into v_guards from public.game_guardians gg where gg.game_id = g.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'player_ref', pp.player_ref, 'board_key', pp.board_key, 'space_index', pp.space_index) order by pp.player_ref), '[]'::jsonb)
    into v_positions from public.player_positions pp
    join public.players p on p.game_id = pp.game_id and p.public_ref = pp.player_ref
    where pp.game_id = g.id and p.kicked_at is null and p.left_at is null;

  select pp.board_key, pp.space_index into v_my_board, v_my_index
    from public.player_positions pp where pp.game_id = g.id and pp.player_ref = me.public_ref;
  if v_my_board is not null then
    v_my_pos := jsonb_build_object('board_key', v_my_board, 'space_index', v_my_index);
    select jsonb_build_object('space_ref', s.space_ref, 'board_key', s.board_key, 'space_index', s.space_index,
             'name', s.name, 'space_type', s.space_type, 'property_ref', s.property_ref, 'is_start', s.is_start)
      into v_current from public.board_spaces s where s.board_key = v_my_board and s.space_index = v_my_index and s.active;
  else
    v_my_pos := null; v_current := null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('player_ref', j.player_ref, 'board_key', j.board_key, 'jail_turns', j.jail_turns)
           order by j.player_ref), '[]'::jsonb)
    into v_jail from public.game_jail j where j.game_id = g.id;
  select jsonb_build_object('board_key', j.board_key, 'jail_turns', j.jail_turns, 'fine', 50,
           'action_taken_this_turn', (j.action_turn = rt.turn_number))
    into v_my_jail from public.game_jail j where j.game_id = g.id and j.player_ref = me.public_ref;

  select coalesce(jsonb_agg(jsonb_build_object(
           'deck_key', d.deck_key,
           'board_key', case when d.deck_key in ('chance','community_chest') then 'classic' else 'back_to_the_future' end,
           'draw_count', coalesce(array_length(d.draw_pile, 1), 0),
           'discard_count', coalesce(array_length(d.discard_pile, 1), 0)) order by d.deck_key), '[]'::jsonb)
    into v_decks from public.game_card_decks d where d.game_id = g.id;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_held
    from (select jsonb_build_object('player_ref', h.player_ref, 'count', count(*)) as t
          from public.game_held_cards h where h.game_id = g.id group by h.player_ref) s;
  select coalesce(jsonb_agg(jsonb_build_object(
           'card_ref', h.card_ref, 'title', c.title, 'description', c.description, 'deck_key', c.deck_key,
           'effect_type', c.effect_type) order by h.acquired_at), '[]'::jsonb)
    into v_my_held from public.game_held_cards h join public.card_catalog c on c.card_ref = h.card_ref
    where h.game_id = g.id and h.player_ref = me.public_ref;

  v_pending_card := case when rt.pending_card is not null and rt.pending_card->>'player_ref' = me.public_ref then rt.pending_card else null end;
  v_pending_pay  := case when rt.pending_payment is not null and rt.pending_payment->>'player_ref' = me.public_ref then rt.pending_payment else null end;

  return jsonb_build_object(
    'game', jsonb_build_object('code', g.code, 'status', g.status,
      'config', jsonb_build_object(
        'initial_money', coalesce((g.config->>'initial_money')::int, 3000),
        'min_players',   coalesce((g.config->>'min_players')::int, 6),
        'max_players',   coalesce((g.config->>'max_players')::int, 16),
        'allow_late_join', coalesce((g.config->>'allow_late_join')::boolean, false),
        'start_bonus', v_start_bonus,
        'dice_mode', coalesce(g.config->>'dice_mode', 'virtual_only'),
        'initial_houses_available', greatest(32, coalesce((g.config->>'initial_houses_available')::int, 32)),
        'initial_hotels_available', greatest(12, coalesce((g.config->>'initial_hotels_available')::int, 12)),
        'allow_build_without_monopoly', coalesce((g.config->>'allow_build_without_monopoly')::boolean, false),
        'allow_trade_built_properties', coalesce((g.config->>'allow_trade_built_properties')::boolean, false),
        'parking_mode', coalesce(g.config->>'parking_mode', 'pot'),
        'start_invest_pct', coalesce((g.config->>'start_invest_pct')::int, 0))),
    'me', jsonb_build_object('public_ref', me.public_ref, 'is_host', v_is_host,
      'balance', (select balance from public.player_balances where game_id = g.id and player_ref = me.public_ref),
      'is_current', me.public_ref = v_cur,
      'is_spectator', me.bankrupt_at is not null),
    'turn', jsonb_build_object('turn_number', rt.turn_number, 'current_player_ref', v_cur, 'order', to_jsonb(rt.turn_order_refs)),
    'players', coalesce(v_players, '[]'::jsonb),
    'ledger_recent', coalesce(v_ledger, '[]'::jsonb),
    'properties', v_props,
    'auctions', v_auctions,
    'purchase_requests', v_purchase,
    'building_requests', v_building,
    'my_building_requests', v_my_building,
    'leave_requests', v_leave,
    'bankruptcy_requests', v_bankrupt,
    'late_join_requests', v_late,
    -- Fase 7: tratos
    'incoming_trades', v_trades_in,
    'outgoing_trades', v_trades_out,
    'trade_reviews', v_trade_reviews,
    'recent_trades', v_recent_trades,
    'my_card_transfers', v_card_transfers,
    'boards', v_boards,
    'spaces', v_spaces,
    'board_links', v_links,
    'pending_junction', rt.pending_junction,
    'guardians', v_guards,
    'positions', v_positions,
    'my_position', v_my_pos,
    'current_space', v_current,
    'last_roll', rt.last_roll,
    'last_move', rt.last_move,
    'parking_pot', rt.parking_pot,
    'jail', v_jail,
    'my_jail', v_my_jail,
    'card_decks', v_decks,
    'last_card_draw', rt.last_card_draw,
    'held_cards', v_held,
    'my_held_cards', v_my_held,
    'pending_card', v_pending_card,
    'pending_payment', v_pending_pay,
    'last_global_event', rt.last_global_event,
    'runtime_status', rt.runtime_status,
    'current_landing_rent_resolved', (rt.rent_resolved_seq >= rt.landing_seq),
    'building_stock', jsonb_build_object('houses_available', rt.houses_available, 'hotels_available', rt.hotels_available),
    'control', jsonb_build_object('paused_by_ref', rt.paused_by_ref, 'finished_by_ref', rt.finished_by_ref, 'reason', rt.status_reason),
    'runtime_version', rt.runtime_version);
end $$;
