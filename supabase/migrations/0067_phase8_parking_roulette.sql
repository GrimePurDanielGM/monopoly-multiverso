-- ============================================================================
-- Fase 8 (C4) — Ruleta de Parking (configurable) + arreglo de exposición de config en el lobby.
-- Opción de partida parking_mode ('pot' = cobrar el bote como hasta ahora | 'roulette' = girar la ruleta).
-- La ruleta tiene 7 resultados (el "cobrar bote" sale dos veces para darle más probabilidad):
--   1 robar carta (de un mazo al azar)  ·  2 y 7 cobrar el bote (y queda a 0)  ·  3 ir a la cárcel
--   4 pierdes tu propiedad MÁS valiosa (a la banca)  ·  5 pierdes la MENOS valiosa  ·  6 pagas 500 € al bote.
-- El bote tiene tope 2.500 € (ya garantizado por _p5_pot_add). Resultado en last_global_event.
-- También expone allow_trade_built_properties y parking_mode en el snapshot del lobby (faltaban).
-- ============================================================================

-- ── Ruleta: aplica un resultado (p_force fija el resultado para los tests; si es null, aleatorio 1..7) ──
create or replace function public._p5_parking_roulette(p_game uuid, p_me public.players, p_board text, p_force int default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_out int; v_pot bigint; v_prop text; v_amt bigint; v_bal bigint; v_deck text; v_eid text; v_ev jsonb;
begin
  v_out := coalesce(p_force, 1 + floor(random()*7)::int);   -- 1..7
  if v_out < 1 or v_out > 7 then v_out := 1; end if;
  v_eid := gen_random_uuid()::text;

  if v_out in (2,7) then                                     -- cobrar el bote (doble probabilidad)
    select parking_pot into v_pot from public.game_runtime where game_id=p_game for update;
    if v_pot > 0 then
      perform public._p2_move(p_game, null, p_me.public_ref, v_pot);
      perform public._p2_post(p_game, 'parking_pot_payout', null, p_me.public_ref, v_pot, null, null, null, p_me.public_ref, null, gen_random_uuid());
      update public.game_runtime set parking_pot = 0 where game_id=p_game;
    end if;
    v_ev := jsonb_build_object('outcome','collect_pot','amount',coalesce(v_pot,0));
  elsif v_out = 1 then                                       -- robar carta de un mazo al azar
    v_deck := (array['chance','community_chest','past','future'])[1 + floor(random()*4)::int];
    perform public._p5_draw_card(p_game, p_me, v_deck, p_board, gen_random_uuid());
    v_ev := jsonb_build_object('outcome','draw_card','deck',v_deck);
  elsif v_out = 3 then                                       -- ir a la cárcel
    perform public._p5_send_to_jail(p_game, p_me, p_board, 'roulette');
    v_ev := jsonb_build_object('outcome','go_to_jail');
  elsif v_out in (4,5) then                                  -- pierde la propiedad más / menos valiosa (a la banca)
    select c.property_ref into v_prop
      from public.property_catalog c
      join public.property_ownership o on o.property_ref=c.property_ref and o.game_id=p_game and o.owner_ref=p_me.public_ref and o.released_at is null
      where c.active
      order by case when v_out=4 then c.price end desc nulls last, case when v_out=5 then c.price end asc nulls last
      limit 1;
    if v_prop is not null then
      update public.property_ownership set released_at=now(), released_reason='parking_roulette'
        where game_id=p_game and property_ref=v_prop and released_at is null;
      perform public._audit(p_game, 'parking_roulette_expropriate', auth.uid(), p_me.id, array[p_me.id], null,
                jsonb_build_object('property', v_prop, 'which', case when v_out=4 then 'most' else 'least' end), null, true);
    end if;
    v_ev := jsonb_build_object('outcome', case when v_out=4 then 'lose_most_valuable' else 'lose_least_valuable' end, 'property_ref', v_prop);
  else                                                       -- 6: paga 500 € al bote (mejor esfuerzo)
    select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_me.public_ref for update;
    v_amt := least(500, v_bal);
    if v_amt > 0 then
      perform public._p2_move(p_game, p_me.public_ref, null, v_amt);
      perform public._p2_post(p_game, 'card_bank_charge', p_me.public_ref, null, v_amt, null, null, null, p_me.public_ref, null, gen_random_uuid());
      perform public._p5_pot_add(p_game, v_amt);
    end if;
    v_ev := jsonb_build_object('outcome','pay_500','amount',coalesce(v_amt,0));
  end if;

  update public.game_runtime set last_global_event =
    v_ev || jsonb_build_object('kind','parking_roulette','player_ref',p_me.public_ref,'slot',v_out,'event_id',v_eid)
    where game_id=p_game;
  return jsonb_build_object('type','parking_roulette') || v_ev;
end $$;
revoke all on function public._p5_parking_roulette(uuid, public.players, text, int) from public, anon, authenticated;

-- ── _p5_resolve_landing: reproduce 0042 + rama de Parking que respeta parking_mode (pot | roulette) ──
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
    if coalesce((select config->>'parking_mode' from public.games where id=p_game), 'pot') = 'roulette' then
      return public._p5_parking_roulette(p_game, p_me, p_board, null);
    end if;
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

-- update_config: + parking_mode (resto idéntico a 0064)
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
    || (case when p_patch ? 'parking_mode' then jsonb_build_object('parking_mode',(p_patch->>'parking_mode')) else '{}'::jsonb end);
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

-- _lobby_snapshot: + allow_trade_built_properties + parking_mode en config (resto idéntico a 0058)
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
        'parking_mode', coalesce(g.config->>'parking_mode', 'pot'))),
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

-- get_active_snapshot_by_code: + parking_mode en config (resto idéntico a 0064)
create or replace function public.get_active_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; rt public.game_runtime; me public.players; v_cur text; v_players jsonb; v_ledger jsonb;
        v_is_host boolean; v_late jsonb; v_props jsonb; v_purchase jsonb; v_auctions jsonb; v_leave jsonb; v_bankrupt jsonb;
        v_building jsonb := '[]'::jsonb; v_my_building jsonb;
        v_start_bonus int; v_boards jsonb; v_spaces jsonb; v_positions jsonb; v_my_pos jsonb; v_current jsonb; v_links jsonb;
        v_my_board text; v_my_index int; v_guards jsonb;
        v_jail jsonb; v_my_jail jsonb; v_decks jsonb; v_held jsonb; v_my_held jsonb; v_pending_card jsonb; v_pending_pay jsonb;
        v_trades_in jsonb; v_trades_out jsonb; v_trade_reviews jsonb := '[]'::jsonb; v_recent_trades jsonb;
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
        'parking_mode', coalesce(g.config->>'parking_mode', 'pot'))),
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
