-- ============================================================================
-- Fase 8 — Cartas REALES (transcritas de las fotos del usuario) + efectos enriquecidos.
-- 64 cartas (16/mazo). Moneda unificada a € en los textos. Nuevos efectos:
--   to_space   : mueve el peón a una casilla concreta del mismo tablero; cobra el sueldo si pasa por Salida
--                (move_forward=false ⇒ retroceso, sin sueldo, p. ej. «retrocede a Ronda de Valencia»).
--   to_nearest : mueve al transporte / Mr.Fusión-Condensador más cercano; el pago especial (doble / 10× dado)
--                lo resuelve el anfitrión (pending_card con instrucción).
--   repairs    : cuenta casas/hoteles del jugador y cobra amount/casa + amount2/hotel AL BOTE del Parking.
--   choice     : el jugador elige (pagar al bote / robar una carta de Suerte) — resolve_card(p_choice).
-- Regla de pagos: todo «paga» de carta va al BOTE del Parking (no a la banca), salvo entre jugadores.
-- ============================================================================

-- ── Esquema: columnas del modelo enriquecido + nuevos effect_type ──
alter table public.card_catalog add column if not exists amount2 int;        -- 2º importe (p. ej. reparación por hotel)
alter table public.card_catalog add column if not exists target_index int;   -- índice de casilla destino (to_space)
alter table public.card_catalog add column if not exists target_kind text;   -- 'transport' | 'utility' (to_nearest)
alter table public.card_catalog add column if not exists move_forward boolean not null default true; -- to_space: avanzar (true) o retroceder (false)
alter table public.card_catalog drop constraint if exists card_catalog_effect_type_check;
alter table public.card_catalog add constraint card_catalog_effect_type_check check (effect_type in
  ('bank_credit','bank_debit','each_player_credit','each_player_debit','to_start','to_jail','back_steps',
   'jail_free','manual','to_space','to_nearest','repairs','choice'));

-- ── _p8_load_deck: acepta los nuevos campos (amount2, target_index, target_kind, move_forward) ──
create or replace function public._p8_load_deck(p_deck text, p_cards jsonb)
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if p_deck not in ('chance','community_chest','past','future') then raise exception 'INVALID_DECK'; end if;
  update public.card_catalog set active = false where deck_key = p_deck and active;
  insert into public.card_catalog(
    card_ref, deck_key, title, description, effect_type, amount, amount2, keepable, temporary,
    target_space, target_board, target_index, target_kind, move_forward, manual_instruction, sort_order, active)
  select x.card_ref, p_deck, x.title, x.description, x.effect_type, x.amount, x.amount2,
         coalesce(x.keepable,false), coalesce(x.temporary,false),
         x.target_space, x.target_board, x.target_index, x.target_kind, coalesce(x.move_forward,true),
         x.manual_instruction, coalesce(x.sort_order,0), true
  from jsonb_to_recordset(p_cards) as x(
    card_ref text, title text, description text, effect_type text, amount int, amount2 int,
    keepable boolean, temporary boolean, target_space text, target_board text, target_index int,
    target_kind text, move_forward boolean, manual_instruction text, sort_order int)
  on conflict (card_ref) do update set
    deck_key = excluded.deck_key, title = excluded.title, description = excluded.description,
    effect_type = excluded.effect_type, amount = excluded.amount, amount2 = excluded.amount2,
    keepable = excluded.keepable, temporary = excluded.temporary, target_space = excluded.target_space,
    target_board = excluded.target_board, target_index = excluded.target_index, target_kind = excluded.target_kind,
    move_forward = excluded.move_forward, manual_instruction = excluded.manual_instruction,
    sort_order = excluded.sort_order, active = true;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public._p8_load_deck(text, jsonb) from public, anon, authenticated;

-- ── _p5_draw_card: reproduce 0040 + nuevos efectos + pagos de carta al bote ──
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
  elsif c.effect_type = 'to_space' then               -- mueve a casilla concreta (sueldo si avanza y pasa Salida)
    select space_index into v_idx from public.player_positions where game_id=p_game and player_ref=p_me.public_ref;
    update public.player_positions set board_key=p_board, space_index=c.target_index, updated_at=now()
      where game_id=p_game and player_ref=p_me.public_ref;
    if coalesce(c.move_forward,true) and c.target_index <= v_idx then
      v_bonus := coalesce((g.config->>'start_bonus')::int, 200);
      if v_bonus > 0 then
        perform public._p2_move(p_game, null, p_me.public_ref, v_bonus);
        perform public._p2_post(p_game, 'pass_start_bonus', null, p_me.public_ref, v_bonus, null, null, null, p_me.public_ref, null, gen_random_uuid());
      end if;
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
        v_bonus := coalesce((g.config->>'start_bonus')::int, 200);
        if v_bonus > 0 then
          perform public._p2_move(p_game, null, p_me.public_ref, v_bonus);
          perform public._p2_post(p_game, 'pass_start_bonus', null, p_me.public_ref, v_bonus, null, null, null, p_me.public_ref, null, gen_random_uuid());
        end if;
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

-- ── resolve_card: añade p_choice para la carta de elección (pagar al bote / robar Suerte) ──
drop function if exists public.resolve_card(uuid, uuid, bigint);   -- sustituida por la versión con p_choice
create or replace function public.resolve_card(p_game uuid, p_request_id uuid, p_expected_version bigint, p_choice text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; pc jsonb; v_ver bigint; v_res jsonb;
        v_bal bigint; v_pay bigint; v_board text; v_amt bigint;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  pc := rt.pending_card;
  if pc is null or pc->>'player_ref' <> me.public_ref then raise exception 'NO_PENDING_CARD'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;

  if coalesce(pc->>'kind','manual') = 'choice' then
    if p_choice not in ('pay','draw') then raise exception 'INVALID_CHOICE'; end if;
    update public.game_card_decks set discard_pile = discard_pile || (pc->>'card_ref'), updated_at = now()
      where game_id=p_game and deck_key = pc->>'deck_key';
    update public.game_runtime set pending_card = null where game_id = p_game;
    if p_choice = 'pay' then
      v_amt := coalesce((pc->>'amount')::bigint, 0);
      select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
      v_pay := least(v_amt, v_bal);
      if v_pay > 0 then
        perform public._p2_move(p_game, me.public_ref, null, v_pay);
        perform public._p2_post(p_game, 'card_bank_charge', me.public_ref, null, v_pay, null, null, null, me.public_ref, null, gen_random_uuid());
        perform public._p5_pot_add(p_game, v_pay);
      end if;
    else  -- draw: roba una carta de Suerte en el tablero del jugador (aplica su propio efecto)
      select board_key into v_board from public.player_positions where game_id=p_game and player_ref=me.public_ref;
      perform public._p5_draw_card(p_game, me, 'chance', coalesce(v_board,'classic'), gen_random_uuid());
    end if;
  else
    -- resolución manual estándar: descarta y limpia
    update public.game_card_decks set discard_pile = discard_pile || (pc->>'card_ref'), updated_at = now()
      where game_id=p_game and deck_key = pc->>'deck_key';
    update public.game_runtime set pending_card = null where game_id = p_game;
  end if;

  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'card_resolved', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('card', pc->>'card_ref', 'choice', p_choice), null, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('resolved', true, 'choice', p_choice, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'resolve_card', v_res);
  return v_res;
end $$;
revoke all on function public.resolve_card(uuid, uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.resolve_card(uuid, uuid, bigint, text) to authenticated;

-- ── Carga de las 64 cartas reales (texto en €) ──
select public._p8_load_deck('past', $cards$[
  {
    "card_ref": "past-autocine",
    "title": "Avanza al Autocine Pohatchee (1955)",
    "description": "Reparas el microchip del circuito temporal del DeLorean. Avanza hasta el Autocine Pohatchee - 1955. Si pasas por la casilla de Salida, cobra 200 €.",
    "effect_type": "to_space",
    "sort_order": 1,
    "target_index": 11
  },
  {
    "card_ref": "past-reparaciones",
    "title": "Reparaciones de plutonio",
    "description": "Construyes una bomba con piezas de una máquina de pinball. Paga 25 € por cada barra de plutonio (casa) y 100 € por cada maletín de plutonio (hotel). Va al bote del Parking.",
    "effect_type": "repairs",
    "sort_order": 2,
    "amount": 25,
    "amount2": 100
  },
  {
    "card_ref": "past-carcel",
    "title": "Ve a la cárcel",
    "description": "Te pillan destrozando un maletín de plutonio. Ve directamente a la cárcel. No pases por la casilla de Salida. No cobres 200 €.",
    "effect_type": "to_jail",
    "sort_order": 3
  },
  {
    "card_ref": "past-jail-free",
    "title": "Sal de la cárcel",
    "description": "Dejas a Biff inconsciente. Quedas libre de la cárcel. Puedes vender esta carta o conservarla hasta que la necesites.",
    "effect_type": "jail_free",
    "sort_order": 4,
    "keepable": true
  },
  {
    "card_ref": "past-torre-reloj",
    "title": "Avanza a la Torre del Reloj (1955)",
    "description": "Reúnes 1,21 gigavatios de potencia. Avanza hasta la Torre del Reloj - 1955.",
    "effect_type": "to_space",
    "sort_order": 5,
    "target_index": 39
  },
  {
    "card_ref": "past-retrocede-3",
    "title": "Retrocede tres casillas",
    "description": "¡Te persiguen Biff y su pandilla! Retrocede tres casillas.",
    "effect_type": "back_steps",
    "sort_order": 6,
    "amount": 3
  },
  {
    "card_ref": "past-transporte",
    "title": "Avanza al transporte más cercano",
    "description": "«¿Carreteras? A donde vamos no necesitamos carreteras.» Avanza hasta la casilla de transporte más cercana. Si no tiene dueño, puedes comprársela a la banca. Si tiene dueño, paga a su dueño el doble del alquiler debido.",
    "effect_type": "to_nearest",
    "sort_order": 7,
    "target_kind": "transport",
    "manual_instruction": "Si la casilla de transporte no tiene dueño, puedes comprarla a la banca. Si tiene dueño, paga el DOBLE del alquiler que le corresponda."
  },
  {
    "card_ref": "past-salida",
    "title": "Avanza a la Salida",
    "description": "«Cuando esa belleza llegue a 140 kilómetros por hora, vas a ver algo acojonante.» Avanza hasta la casilla de Salida. (Cobra 200 €.)",
    "effect_type": "to_start",
    "sort_order": 8
  },
  {
    "card_ref": "past-cobra-150",
    "title": "Cobra 150 €",
    "description": "Sustituyes al cantante de la banda de Marvin Berry. Cobra 150 €.",
    "effect_type": "bank_credit",
    "sort_order": 9,
    "amount": 150
  },
  {
    "card_ref": "past-tren-tiempo",
    "title": "Avanza al Tren del Tiempo (1885)",
    "description": "Encuentras la manera de hacer llegar al DeLorean a los 140 km/h. Avanza hasta el Tren del Tiempo - 1885. Si pasas por la casilla de Salida, cobra 200 €.",
    "effect_type": "to_space",
    "sort_order": 10,
    "target_index": 5
  },
  {
    "card_ref": "past-cobra-50",
    "title": "Cobra 50 €",
    "description": "¡Gran puntuación! Ganas en el puesto de tiro al blanco. Cobra 50 €.",
    "effect_type": "bank_credit",
    "sort_order": 11,
    "amount": 50
  },
  {
    "card_ref": "past-paga-15",
    "title": "Paga 15 €",
    "description": "Construyes un refrigerador a vapor. Paga 15 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 12,
    "amount": 15
  },
  {
    "card_ref": "past-paga-cada-50",
    "title": "Paga 50 € a cada jugador",
    "description": "Borras todo rastro de la existencia de tu familia. Paga 50 € a cada jugador.",
    "effect_type": "each_player_debit",
    "sort_order": 13,
    "amount": 50
  },
  {
    "card_ref": "past-transporte-2",
    "title": "Avanza al transporte más cercano",
    "description": "«¿Carreteras? A donde vamos no necesitamos carreteras.» Avanza hasta la casilla de transporte más cercana. Si no tiene dueño, puedes comprársela a la banca. Si tiene dueño, paga a su dueño el doble del alquiler debido.",
    "effect_type": "to_nearest",
    "sort_order": 14,
    "target_kind": "transport",
    "manual_instruction": "Si la casilla de transporte no tiene dueño, puedes comprarla a la banca. Si tiene dueño, paga el DOBLE del alquiler que le corresponda."
  },
  {
    "card_ref": "past-mr-fusion",
    "title": "Avanza a Mr. Fusión / Condensador más cercano",
    "description": "Descubres un combustible alternativo para el DeLorean. Avanza hasta la casilla de Mr. Fusión o Condensador de Fluzo más cercana. Si no tiene dueño, puedes comprársela a la banca. Si tiene dueño, lanza el dado y paga a su dueño diez veces la cifra obtenida.",
    "effect_type": "to_nearest",
    "sort_order": 15,
    "target_kind": "utility",
    "manual_instruction": "Si la casilla no tiene dueño, puedes comprarla a la banca. Si tiene dueño, lanza el dado y paga a su dueño 10× la cifra obtenida."
  },
  {
    "card_ref": "past-residencia-mcfly",
    "title": "Avanza a la Residencia McFly (2015)",
    "description": "«¡Vuestros hijos, Marty! ¡Algo hay que hacer con vuestros hijos!» Avanza hasta la Residencia McFly - 2015. Si pasas por la casilla de Salida, cobra 200 €.",
    "effect_type": "to_space",
    "sort_order": 16,
    "target_index": 24
  }
]$cards$::jsonb);

select public._p8_load_deck('chance', $cards$[
  {
    "card_ref": "chance-gastos-escolares",
    "title": "Gastos escolares",
    "description": "Paga por gastos escolares 150 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 1,
    "amount": 150
  },
  {
    "card_ref": "chance-cea-bermudez",
    "title": "Adelanta a Cea Bermúdez",
    "description": "Adelanta hasta la calle Cea Bermúdez. Si pasas por la casilla de Salida, cobra 200 €.",
    "effect_type": "to_space",
    "sort_order": 2,
    "target_index": 24
  },
  {
    "card_ref": "chance-seguro-edificios",
    "title": "Cobra 150 €",
    "description": "Recibes el rescate por el seguro de tus edificios. Cobra 150 €.",
    "effect_type": "bank_credit",
    "sort_order": 3,
    "amount": 150
  },
  {
    "card_ref": "chance-embriaguez",
    "title": "Multa por embriaguez",
    "description": "Multa por embriaguez 20 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 4,
    "amount": 20
  },
  {
    "card_ref": "chance-crucigramas",
    "title": "Cobra 100 €",
    "description": "Has ganado el concurso de crucigramas. Cobra 100 €.",
    "effect_type": "bank_credit",
    "sort_order": 5,
    "amount": 100
  },
  {
    "card_ref": "chance-intereses",
    "title": "La banca te paga intereses",
    "description": "La banca te paga 50 € de intereses.",
    "effect_type": "bank_credit",
    "sort_order": 6,
    "amount": 50
  },
  {
    "card_ref": "chance-paseo-prado",
    "title": "Ve al Paseo del Prado",
    "description": "Ve al Paseo del Prado. Si pasas por la casilla de Salida, cobra 200 €.",
    "effect_type": "to_space",
    "sort_order": 7,
    "target_index": 39
  },
  {
    "card_ref": "chance-jail-free",
    "title": "Sal de la cárcel",
    "description": "Quedas libre de la cárcel. Esta carta puede venderse o conservarse hasta que sea utilizada.",
    "effect_type": "jail_free",
    "sort_order": 8,
    "keepable": true
  },
  {
    "card_ref": "chance-salida",
    "title": "Ve a la Salida",
    "description": "Colócate en la casilla de Salida. Cobra 200 €.",
    "effect_type": "to_start",
    "sort_order": 9
  },
  {
    "card_ref": "chance-retrocede-3",
    "title": "Retrocede tres casillas",
    "description": "Retrocede tres casillas.",
    "effect_type": "back_steps",
    "sort_order": 10,
    "amount": 3
  },
  {
    "card_ref": "chance-inspeccion",
    "title": "Reparaciones (inspección)",
    "description": "La inspección de la calle te obliga a reparaciones. Paga 40 € por cada casa y 115 € por cada hotel. Va al bote del Parking.",
    "effect_type": "repairs",
    "sort_order": 11,
    "amount": 40,
    "amount2": 115
  },
  {
    "card_ref": "chance-reparaciones",
    "title": "Reparaciones en tus edificios",
    "description": "Haz reparaciones en todos tus edificios. Paga 25 € por cada casa y 100 € por cada hotel. Va al bote del Parking.",
    "effect_type": "repairs",
    "sort_order": 12,
    "amount": 25,
    "amount2": 100
  },
  {
    "card_ref": "chance-carcel",
    "title": "Ve a la cárcel",
    "description": "Ve a la cárcel. Ve directamente sin pasar por la casilla de Salida y sin cobrar los 200 €.",
    "effect_type": "to_jail",
    "sort_order": 13
  },
  {
    "card_ref": "chance-delicias",
    "title": "Ve a la Estación de las Delicias",
    "description": "Ve a la Estación de las Delicias. Si pasas por la casilla de Salida, cobra 200 €.",
    "effect_type": "to_space",
    "sort_order": 14,
    "target_index": 15
  },
  {
    "card_ref": "chance-bilbao",
    "title": "Ve a la Glorieta de Bilbao",
    "description": "Ve a la Glorieta de Bilbao. Si pasas por la casilla de Salida, cobra 200 €.",
    "effect_type": "to_space",
    "sort_order": 15,
    "target_index": 11
  },
  {
    "card_ref": "chance-velocidad",
    "title": "Multa por velocidad",
    "description": "Multa por exceso de velocidad 15 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 16,
    "amount": 15
  }
]$cards$::jsonb);

select public._p8_load_deck('future', $cards$[
  {
    "card_ref": "future-cobra-200",
    "title": "Cobra 200 €",
    "description": "Te preparas para cualquier eventualidad monetaria. Cobra 200 €.",
    "effect_type": "bank_credit",
    "sort_order": 1,
    "amount": 200
  },
  {
    "card_ref": "future-jail-free",
    "title": "Sal de la cárcel",
    "description": "Impides que arresten a tu futuro hijo. Quedas libre de la cárcel. Puedes vender esta carta o conservarla hasta que la necesites.",
    "effect_type": "jail_free",
    "sort_order": 2,
    "keepable": true
  },
  {
    "card_ref": "future-cobra-10",
    "title": "Cobra 10 €",
    "description": "Biff le ha puesto una segunda capa de cera a tu camioneta. Cobra 10 €.",
    "effect_type": "bank_credit",
    "sort_order": 3,
    "amount": 10
  },
  {
    "card_ref": "future-aeroconversion",
    "title": "Cobra 100 €",
    "description": "Obtén una aeroconversión en Sistemas de Conversión Wilson. Cobra 100 €.",
    "effect_type": "bank_credit",
    "sort_order": 4,
    "amount": 100
  },
  {
    "card_ref": "future-novela",
    "title": "Cobra 50 €",
    "description": "Ha llegado tu primera novela. Cobra 50 €.",
    "effect_type": "bank_credit",
    "sort_order": 5,
    "amount": 50
  },
  {
    "card_ref": "future-salida",
    "title": "Avanza a la Salida",
    "description": "«¡Cuando esa belleza llegue a 140 kilómetros por hora, vas a ver algo acojonante!» Avanza hasta la casilla de Salida. (Cobra 200 €.)",
    "effect_type": "to_start",
    "sort_order": 6
  },
  {
    "card_ref": "future-carcel",
    "title": "Ve a la cárcel",
    "description": "Despedido por el Sr. Fujitsu por una transacción ilegal a Needles. Ve directamente a la cárcel. No pases por la casilla de Salida. No cobres 200 €.",
    "effect_type": "to_jail",
    "sort_order": 7
  },
  {
    "card_ref": "future-reparaciones",
    "title": "¡Hora de las reparaciones!",
    "description": "¡Hora de las reparaciones! Una sobrecarga de gigavatios ha cortocircuitado los circuitos temporales. Paga 40 € por cada casa y 115 € por cada hotel. Va al bote del Parking.",
    "effect_type": "repairs",
    "sort_order": 8,
    "amount": 40,
    "amount2": 115
  },
  {
    "card_ref": "future-einstein",
    "title": "Recibe 100 €",
    "description": "Haces viajar a Einstein en el tiempo. Recibe 100 €.",
    "effect_type": "bank_credit",
    "sort_order": 9,
    "amount": 100
  },
  {
    "card_ref": "future-sin-vigilancia",
    "title": "Paga 50 €",
    "description": "Has dejado el DeLorean sin vigilancia en 2015 y la máquina del tiempo ha caído en manos de Biff. Paga 50 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 10,
    "amount": 50
  },
  {
    "card_ref": "future-precauciones",
    "title": "Cobra 100 €",
    "description": "Tomas todas las precauciones necesarias para impedir que unos terroristas atenten contra tu vida. Cobra 100 €.",
    "effect_type": "bank_credit",
    "sort_order": 11,
    "amount": 100
  },
  {
    "card_ref": "future-refresco",
    "title": "Paga 50 €",
    "description": "Compras un refresco. Paga 50 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 12,
    "amount": 50
  },
  {
    "card_ref": "future-afortunado",
    "title": "Cobra 10 € de cada jugador",
    "description": "¡Eres el hombre más afortunado de la Tierra! Cobra 10 € de cada jugador.",
    "effect_type": "each_player_credit",
    "sort_order": 13,
    "amount": 10
  },
  {
    "card_ref": "future-plutonio",
    "title": "Cobra 25 €",
    "description": "Te has acordado de traer plutonio de sobra. Cobra 25 €.",
    "effect_type": "bank_credit",
    "sort_order": 14,
    "amount": 25
  },
  {
    "card_ref": "future-cuatro-dimensiones",
    "title": "Cobra 20 €",
    "description": "Empiezas a pensar en cuatro dimensiones. Cobra 20 €.",
    "effect_type": "bank_credit",
    "sort_order": 15,
    "amount": 20
  },
  {
    "card_ref": "future-almanaque",
    "title": "Paga 100 €",
    "description": "Compras una copia del Almanaque Deportivo Grays. Paga 100 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 16,
    "amount": 100
  }
]$cards$::jsonb);

select public._p8_load_deck('community_chest', $cards$[
  {
    "card_ref": "cc-cumpleanos",
    "title": "Cumpleaños",
    "description": "En tu cumpleaños recibes de cada jugador 10 €.",
    "effect_type": "each_player_credit",
    "sort_order": 1,
    "amount": 10
  },
  {
    "card_ref": "cc-herencia",
    "title": "Cobras una herencia",
    "description": "Cobras una herencia 100 €.",
    "effect_type": "bank_credit",
    "sort_order": 2,
    "amount": 100
  },
  {
    "card_ref": "cc-ronda-valencia",
    "title": "Retrocede a Ronda de Valencia",
    "description": "Retrocede hasta Ronda de Valencia. Como retrocedes, no cobras los 200 € de la Salida.",
    "effect_type": "to_space",
    "sort_order": 3,
    "target_index": 1,
    "move_forward": false
  },
  {
    "card_ref": "cc-medico",
    "title": "Factura del médico",
    "description": "Paga la factura del médico 50 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 4,
    "amount": 50
  },
  {
    "card_ref": "community_chest-jail-free",
    "title": "Sal de la cárcel",
    "description": "Quedas libre de la cárcel. Esta carta puede venderse o conservarse hasta que sea utilizada.",
    "effect_type": "jail_free",
    "sort_order": 5,
    "keepable": true
  },
  {
    "card_ref": "cc-acciones",
    "title": "Venta de acciones",
    "description": "La venta de tus acciones te produce 50 €.",
    "effect_type": "bank_credit",
    "sort_order": 6,
    "amount": 50
  },
  {
    "card_ref": "cc-plazo-fijo",
    "title": "Intereses de plazo fijo",
    "description": "Recibe 100 € por los intereses de tu plazo fijo.",
    "effect_type": "bank_credit",
    "sort_order": 7,
    "amount": 100
  },
  {
    "card_ref": "cc-acciones-pref",
    "title": "Acciones preferenciales",
    "description": "Recibe 25 € como intereses de tus acciones preferenciales.",
    "effect_type": "bank_credit",
    "sort_order": 8,
    "amount": 25
  },
  {
    "card_ref": "cc-multa-o-suerte",
    "title": "Multa o carta de Suerte",
    "description": "Paga una multa de 10 € (al bote del Parking) o bien saca una carta de Suerte.",
    "effect_type": "choice",
    "sort_order": 9,
    "amount": 10,
    "manual_instruction": "Elige: pagar 10 € al bote del Parking, o robar una carta de Suerte y aplicarla."
  },
  {
    "card_ref": "cc-hospital",
    "title": "Paga al hospital",
    "description": "Paga al hospital 100 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 10,
    "amount": 100
  },
  {
    "card_ref": "cc-error-banca",
    "title": "Error de la banca a tu favor",
    "description": "Error de la banca a tu favor. Recibe 200 €.",
    "effect_type": "bank_credit",
    "sort_order": 11,
    "amount": 200
  },
  {
    "card_ref": "cc-carcel",
    "title": "Ve a la cárcel",
    "description": "Ve a la cárcel. Ve directamente sin pasar por la casilla de Salida y sin cobrar los 200 €.",
    "effect_type": "to_jail",
    "sort_order": 12
  },
  {
    "card_ref": "cc-belleza",
    "title": "Segundo premio de belleza",
    "description": "Has ganado el segundo premio de belleza. Recibe 10 €.",
    "effect_type": "bank_credit",
    "sort_order": 13,
    "amount": 10
  },
  {
    "card_ref": "cc-seguro",
    "title": "Póliza de seguro",
    "description": "Paga tu póliza de seguro 50 € al bote del Parking.",
    "effect_type": "bank_debit",
    "sort_order": 14,
    "amount": 50
  },
  {
    "card_ref": "cc-salida",
    "title": "Ve a la Salida",
    "description": "Colócate en la casilla de Salida. Cobra 200 €.",
    "effect_type": "to_start",
    "sort_order": 15
  },
  {
    "card_ref": "cc-hacienda",
    "title": "Hacienda te devuelve",
    "description": "Hacienda te devuelve 20 €.",
    "effect_type": "bank_credit",
    "sort_order": 16,
    "amount": 20
  }
]$cards$::jsonb);
