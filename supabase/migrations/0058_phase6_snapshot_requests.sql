-- Fase 6 (pulido) — Snapshot: config de stock/construir-sin-monopolio, bandeja de solicitudes de
-- construcción (host) y mis solicitudes pendientes. Reproduce 0055. Saneado (sin ids internos), saldos privados.

-- Alquiler ACTUAL que adeudaría quien cae en la propiedad (calle/estación); null para utilities/no aplicable.
create or replace function public._p6_rent_due(p_game uuid, p_prop text) returns int
  language plpgsql stable security definer set search_path = public, pg_temp as $$
declare c public.property_catalog; v_owner text; v_h int; v_hotel boolean; v_mort boolean; v_n int; begin
  select * into c from public.property_catalog where property_ref = p_prop and active;
  if not found then return null; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_prop and released_at is null;
  if v_owner is null then return null; end if;  -- sin dueño no hay alquiler que mostrar
  if c.kind = 'street' then
    select houses, has_hotel, mortgaged into v_h, v_hotel, v_mort from public._p6_state(p_game, p_prop);
    if v_mort then return 0; end if;
    if v_hotel then return coalesce(c.rent_hotel, c.base_rent); end if;
    if v_h >= 1 then return coalesce(case v_h when 1 then c.rent_1 when 2 then c.rent_2 when 3 then c.rent_3 else c.rent_4 end, c.base_rent); end if;
    if public._p6_is_monopoly(p_game, p_prop) then return c.base_rent * 2; end if;
    return c.base_rent;
  elsif c.kind in ('station','transport') then
    select count(*) into v_n from public.property_ownership o join public.property_catalog cc on cc.property_ref=o.property_ref
      where o.game_id=p_game and o.owner_ref=v_owner and o.released_at is null and cc.kind in ('station','transport') and cc.active;
    return public._p3_station_rent(v_n);
  else
    return null;  -- utilities dependen de los dados
  end if;
end $$;
revoke all on function public._p6_rent_due(uuid, text) from public, anon, authenticated;

create or replace function public.get_active_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; rt public.game_runtime; me public.players; v_cur text; v_players jsonb; v_ledger jsonb;
        v_is_host boolean; v_late jsonb; v_props jsonb; v_purchase jsonb; v_auctions jsonb; v_leave jsonb; v_bankrupt jsonb;
        v_building jsonb := '[]'::jsonb; v_my_building jsonb;
        v_start_bonus int; v_boards jsonb; v_spaces jsonb; v_positions jsonb; v_my_pos jsonb; v_current jsonb; v_links jsonb;
        v_my_board text; v_my_index int; v_guards jsonb;
        v_jail jsonb; v_my_jail jsonb; v_decks jsonb; v_held jsonb; v_my_held jsonb; v_pending_card jsonb; v_pending_pay jsonb;
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

  -- Privacidad: cada jugador solo ve su propio saldo.
  select jsonb_agg(jsonb_build_object(
           'public_ref', p.public_ref, 'display_name', p.display_name, 'token_id', p.token_id,
           'balance', case when p.public_ref = me.public_ref then b.balance else null end,
           'is_current', p.public_ref = v_cur,
           'status', case when p.bankrupt_at is not null then 'bankrupt' else 'active' end)
           order by case when p.bankrupt_at is not null then 1 else 0 end, array_position(rt.turn_order_refs, p.public_ref))
    into v_players
    from public.players p
    join public.player_balances b on b.game_id = p.game_id and b.player_ref = p.public_ref
    where p.game_id = g.id and p.kicked_at is null and p.left_at is null
      and (p.public_ref = any(rt.turn_order_refs) or p.bankrupt_at is not null);

  select jsonb_agg(jsonb_build_object(
           'ledger_ref', l.ledger_ref, 'seq', l.seq, 'kind', l.kind, 'from_ref', l.from_ref, 'to_ref', l.to_ref,
           'amount', l.amount, 'before_balance', l.before_balance, 'after_balance', l.after_balance,
           'reason', l.reason, 'actor_ref', l.actor_ref,
           'reverts_ref', (select r.ledger_ref from public.ledger r where r.id = l.reverts_ledger_id),
           'created_at', l.created_at) order by l.seq desc)
    into v_ledger
    from (select * from public.ledger where game_id = g.id order by seq desc limit 25) l;

  select coalesce(jsonb_agg(jsonb_build_object(
           'property_ref', c.property_ref, 'board_key', c.board_key, 'group_key', c.group_key,
           'name', c.name, 'kind', c.kind, 'price', c.price, 'base_rent', c.base_rent,
           'is_buyable', c.is_buyable, 'sort_order', c.sort_order,
           -- Campos de la tarjeta (consulta): null donde no aplica (estaciones/transportes sin casas, utilities).
           'rent_1', c.rent_1, 'rent_2', c.rent_2, 'rent_3', c.rent_3, 'rent_4', c.rent_4, 'rent_hotel', c.rent_hotel,
           'house_cost', c.house_cost, 'hotel_cost', c.hotel_cost, 'mortgage_value', c.mortgage_value,
           -- Deshipoteca = hipoteca + 10% (regla estándar), redondeo al alza; null si no hay hipoteca.
           'unmortgage_cost', case when c.mortgage_value is null then null else ceil(c.mortgage_value * 1.1)::int end,
           'owner_ref', (select o.owner_ref from public.property_ownership o
                          where o.game_id = g.id and o.property_ref = c.property_ref and o.released_at is null),
           'in_auction', exists(select 1 from public.property_auctions a where a.game_id=g.id and a.property_ref=c.property_ref and a.status='active'),
           -- Fase 6 — construcción/hipoteca/monopolio y alquiler actual adeudado (saneado)
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
    -- Fase 6: bandeja de solicitudes de construcción (host)
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', gbr.public_ref, 'property_ref', gbr.property_ref,
             'property_name', (select name from public.property_catalog where property_ref=gbr.property_ref),
             'action', gbr.action, 'requester_ref', gbr.requester_ref,
             'requester_name', (select display_name from public.players where game_id=g.id and public_ref=gbr.requester_ref)) order by gbr.created_at), '[]'::jsonb)
      into v_building from public.game_building_requests gbr where gbr.game_id=g.id and gbr.status='pending';
  else
    v_purchase := '[]'::jsonb; v_leave := '[]'::jsonb; v_bankrupt := '[]'::jsonb; v_late := '[]'::jsonb;
  end if;
  -- Mis solicitudes de construcción pendientes (cualquier jugador, para mostrar "pendiente" en la ficha).
  select coalesce(jsonb_agg(jsonb_build_object('property_ref', gbr.property_ref, 'action', gbr.action)), '[]'::jsonb)
    into v_my_building from public.game_building_requests gbr where gbr.game_id=g.id and gbr.requester_ref=me.public_ref and gbr.status='pending';

  select coalesce(jsonb_agg(jsonb_build_object(
           'board_key', t.board_key, 'ring_size', t.n, 'start_bonus', v_start_bonus, 'provisional', t.prov) order by t.board_key), '[]'::jsonb)
    into v_boards
    from (select board_key, count(*)::int as n, bool_or(provisional) as prov from public.board_spaces where active group by board_key) t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'space_ref', s.space_ref, 'board_key', s.board_key, 'space_index', s.space_index,
           'name', s.name, 'space_type', s.space_type, 'property_ref', s.property_ref, 'is_start', s.is_start,
           'provisional', s.provisional, 'guardian', s.guardian, 'links_to_board', s.links_to_board, 'links_to_index', s.links_to_index, 'guardian_toll', s.guardian_toll)
           order by s.board_key, s.space_index), '[]'::jsonb)
    into v_spaces from public.board_spaces s where s.active;

  -- Enlaces de montaje entre tableros (esquinas con guardián).
  select coalesce(jsonb_agg(jsonb_build_object(
           'board_key', s.board_key, 'space_index', s.space_index, 'space_type', s.space_type,
           'links_to_board', s.links_to_board, 'links_to_index', s.links_to_index, 'guardian', s.guardian) order by s.board_key, s.space_index), '[]'::jsonb)
    into v_links from public.board_spaces s where s.active and s.links_to_board is not null;
  select coalesce(jsonb_agg(jsonb_build_object('board_key', gg.board_key, 'guards', gg.guards) order by gg.board_key), '[]'::jsonb)
    into v_guards from public.game_guardians gg where gg.game_id = g.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'player_ref', pp.player_ref, 'board_key', pp.board_key, 'space_index', pp.space_index)
           order by pp.player_ref), '[]'::jsonb)
    into v_positions
    from public.player_positions pp
    join public.players p on p.game_id = pp.game_id and p.public_ref = pp.player_ref
    where pp.game_id = g.id and p.kicked_at is null and p.left_at is null;

  select pp.board_key, pp.space_index into v_my_board, v_my_index
    from public.player_positions pp where pp.game_id = g.id and pp.player_ref = me.public_ref;
  if v_my_board is not null then
    v_my_pos := jsonb_build_object('board_key', v_my_board, 'space_index', v_my_index);
    select jsonb_build_object('space_ref', s.space_ref, 'board_key', s.board_key, 'space_index', s.space_index,
             'name', s.name, 'space_type', s.space_type, 'property_ref', s.property_ref, 'is_start', s.is_start)
      into v_current from public.board_spaces s
      where s.board_key = v_my_board and s.space_index = v_my_index and s.active;
  else
    v_my_pos := null; v_current := null;
  end if;

  -- ── Fase 5: cárcel, bote de Parking, cartas ──
  -- Estado de cárcel (público: quién está y en qué tablero). Mi estado incluye la multa de salida.
  select coalesce(jsonb_agg(jsonb_build_object('player_ref', j.player_ref, 'board_key', j.board_key, 'jail_turns', j.jail_turns)
           order by j.player_ref), '[]'::jsonb)
    into v_jail from public.game_jail j where j.game_id = g.id;
  select jsonb_build_object('board_key', j.board_key, 'jail_turns', j.jail_turns, 'fine', 50,
           'action_taken_this_turn', (j.action_turn = rt.turn_number))
    into v_my_jail from public.game_jail j where j.game_id = g.id and j.player_ref = me.public_ref;

  -- Mazos: solo recuentos (no el orden de las cartas, que se mantiene oculto). board_key derivado del mazo.
  select coalesce(jsonb_agg(jsonb_build_object(
           'deck_key', d.deck_key,
           'board_key', case when d.deck_key in ('chance','community_chest') then 'classic' else 'back_to_the_future' end,
           'draw_count', coalesce(array_length(d.draw_pile, 1), 0),
           'discard_count', coalesce(array_length(d.discard_pile, 1), 0)) order by d.deck_key), '[]'::jsonb)
    into v_decks from public.game_card_decks d where d.game_id = g.id;

  -- Cartas conservables: recuento por jugador (público) + mi inventario completo (privado).
  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_held
    from (select jsonb_build_object('player_ref', h.player_ref, 'count', count(*)) as t
          from public.game_held_cards h where h.game_id = g.id group by h.player_ref) s;
  select coalesce(jsonb_agg(jsonb_build_object(
           'card_ref', h.card_ref, 'title', c.title, 'description', c.description, 'deck_key', c.deck_key,
           'effect_type', c.effect_type) order by h.acquired_at), '[]'::jsonb)
    into v_my_held from public.game_held_cards h join public.card_catalog c on c.card_ref = h.card_ref
    where h.game_id = g.id and h.player_ref = me.public_ref;

  -- Carta/pago pendientes: solo se exponen al jugador a quien pertenecen.
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
        'allow_build_without_monopoly', coalesce((g.config->>'allow_build_without_monopoly')::boolean, false))),
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
    -- Fase 5: casillas especiales
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
    -- ¿la caída actual ya tiene su alquiler resuelto? (bloqueo de doble pago por caída)
    'current_landing_rent_resolved', (rt.rent_resolved_seq >= rt.landing_seq),
    'building_stock', jsonb_build_object('houses_available', rt.houses_available, 'hotels_available', rt.hotels_available),
    'control', jsonb_build_object('paused_by_ref', rt.paused_by_ref, 'finished_by_ref', rt.finished_by_ref, 'reason', rt.status_reason),
    'runtime_version', rt.runtime_version);
end $$;

-- Lobby snapshot: expone también config.dice_mode (el anfitrión lo configura antes de empezar).
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
        'allow_build_without_monopoly', coalesce((g.config->>'allow_build_without_monopoly')::boolean, false))),
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
