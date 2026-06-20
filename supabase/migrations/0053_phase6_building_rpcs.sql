-- Fase 6 — RPCs de construcción/venta de casas y hoteles, e hipoteca/deshipoteca (solo CALLES).
-- Patrón estándar: req_id → _p2_lock → guard pausa/fin → _p2_idem → propietario activo → validaciones →
-- version check → efectos (dinero + estado + stock) → _p2_bump → _audit → _emit_active_signal → _p2_save.
-- El actor debe ser el PROPIETARIO activo (no hace falta que sea su turno; en Monopoly se construye entre turnos).

-- ── build_house ─────────────────────────────────────────────────────────────────────
create or replace function public.build_house(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_owner text; v_idem jsonb;
        v_ver bigint; v_bal bigint; v_h int; v_hotel boolean; v_mort boolean; v_min int; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  if rt.runtime_status = 'paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if v_owner is null or v_owner <> me.public_ref then raise exception 'NOT_OWNER'; end if;
  select houses, has_hotel, mortgaged into v_h, v_hotel, v_mort from public._p6_state(p_game, p_property_ref);
  if v_mort then raise exception 'PROPERTY_MORTGAGED'; end if;
  if not public._p6_is_monopoly(p_game, p_property_ref) then raise exception 'GROUP_NOT_COMPLETE'; end if;
  if public._p6_group_has_mortgage(p_game, c.board_key, c.group_key) then raise exception 'GROUP_HAS_MORTGAGE'; end if;
  if v_hotel or v_h >= 4 then raise exception 'UNEVEN_BUILDING'; end if;     -- con 4 casas se construye hotel
  v_min := public._p6_group_min_level(p_game, c.board_key, c.group_key);
  if v_h > v_min then raise exception 'UNEVEN_BUILDING'; end if;            -- construcción uniforme
  if rt.houses_available < 1 then raise exception 'INSUFFICIENT_HOUSES_AVAILABLE'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < c.house_cost then raise exception 'INSUFFICIENT_FUNDS'; end if;
  perform public._p2_move(p_game, me.public_ref, null, c.house_cost);
  perform public._p2_post(p_game, 'building_purchase', me.public_ref, null, c.house_cost, null, null, null, me.public_ref, null, p_request_id);
  insert into public.game_property_state(game_id, property_ref, houses) values (p_game, p_property_ref, v_h + 1)
    on conflict (game_id, property_ref) do update set houses = v_h + 1, updated_at = now();
  update public.game_runtime set houses_available = houses_available - 1 where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'house_built', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', p_property_ref, 'houses', v_h + 1, 'cost', c.house_cost), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', p_property_ref, 'houses', v_h + 1, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'build_house', v_res);
  return v_res;
end $$;
grant execute on function public.build_house(uuid, text, uuid, bigint) to authenticated;

-- ── build_hotel (4 casas en la propiedad + el resto del grupo en 4 casas/hotel) ──────
create or replace function public.build_hotel(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_owner text; v_idem jsonb;
        v_ver bigint; v_bal bigint; v_h int; v_hotel boolean; v_mort boolean; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  if rt.runtime_status = 'paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if v_owner is null or v_owner <> me.public_ref then raise exception 'NOT_OWNER'; end if;
  select houses, has_hotel, mortgaged into v_h, v_hotel, v_mort from public._p6_state(p_game, p_property_ref);
  if v_mort then raise exception 'PROPERTY_MORTGAGED'; end if;
  if not public._p6_is_monopoly(p_game, p_property_ref) then raise exception 'GROUP_NOT_COMPLETE'; end if;
  if public._p6_group_has_mortgage(p_game, c.board_key, c.group_key) then raise exception 'GROUP_HAS_MORTGAGE'; end if;
  if v_hotel then raise exception 'UNEVEN_BUILDING'; end if;
  if v_h <> 4 then raise exception 'UNEVEN_BUILDING'; end if;
  if not public._p6_group_rest_max(p_game, c.board_key, c.group_key, p_property_ref) then raise exception 'UNEVEN_BUILDING'; end if;
  if rt.hotels_available < 1 then raise exception 'INSUFFICIENT_HOTELS_AVAILABLE'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < c.hotel_cost then raise exception 'INSUFFICIENT_FUNDS'; end if;
  perform public._p2_move(p_game, me.public_ref, null, c.hotel_cost);
  perform public._p2_post(p_game, 'hotel_purchase', me.public_ref, null, c.hotel_cost, null, null, null, me.public_ref, null, p_request_id);
  update public.game_property_state set houses = 0, has_hotel = true, updated_at = now() where game_id=p_game and property_ref=p_property_ref;
  -- el hotel consume 1 hotel del stock y DEVUELVE 4 casas al banco.
  update public.game_runtime set hotels_available = hotels_available - 1, houses_available = houses_available + 4 where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'hotel_built', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', p_property_ref, 'cost', c.hotel_cost), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', p_property_ref, 'has_hotel', true, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'build_hotel', v_res);
  return v_res;
end $$;
grant execute on function public.build_hotel(uuid, text, uuid, bigint) to authenticated;

-- ── sell_house (50% del coste; uniformidad inversa: solo desde la propiedad con más nivel) ──
create or replace function public.sell_house(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_owner text; v_idem jsonb;
        v_ver bigint; v_bal bigint; v_h int; v_hotel boolean; v_mort boolean; v_max int; v_refund bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  if rt.runtime_status = 'paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if v_owner is null or v_owner <> me.public_ref then raise exception 'NOT_OWNER'; end if;
  select houses, has_hotel, mortgaged into v_h, v_hotel, v_mort from public._p6_state(p_game, p_property_ref);
  if v_hotel or v_h <= 0 then raise exception 'NO_BUILDING_TO_SELL'; end if;
  v_max := public._p6_group_max_level(p_game, c.board_key, c.group_key);
  if v_h < v_max then raise exception 'UNEVEN_BUILDING'; end if;             -- vende primero desde la(s) más altas
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  v_refund := (c.house_cost / 2)::bigint;
  perform public._p2_move(p_game, null, me.public_ref, v_refund);
  perform public._p2_post(p_game, 'building_sale', null, me.public_ref, v_refund, null, null, null, me.public_ref, null, p_request_id);
  update public.game_property_state set houses = v_h - 1, updated_at = now() where game_id=p_game and property_ref=p_property_ref;
  update public.game_runtime set houses_available = houses_available + 1 where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'house_sold', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', p_property_ref, 'houses', v_h - 1, 'refund', v_refund), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', p_property_ref, 'houses', v_h - 1, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'sell_house', v_res);
  return v_res;
end $$;
grant execute on function public.sell_house(uuid, text, uuid, bigint) to authenticated;

-- ── sell_hotel (50%; vuelve a 4 casas si hay stock, si no INSUFFICIENT_HOUSES_AVAILABLE) ──
create or replace function public.sell_hotel(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_owner text; v_idem jsonb;
        v_ver bigint; v_bal bigint; v_h int; v_hotel boolean; v_mort boolean; v_refund bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  if rt.runtime_status = 'paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if v_owner is null or v_owner <> me.public_ref then raise exception 'NOT_OWNER'; end if;
  select houses, has_hotel, mortgaged into v_h, v_hotel, v_mort from public._p6_state(p_game, p_property_ref);
  if not v_hotel then raise exception 'NO_BUILDING_TO_SELL'; end if;
  if rt.houses_available < 4 then raise exception 'INSUFFICIENT_HOUSES_AVAILABLE'; end if;  -- el hotel vuelve a 4 casas
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  v_refund := (c.hotel_cost / 2)::bigint;
  perform public._p2_move(p_game, null, me.public_ref, v_refund);
  perform public._p2_post(p_game, 'hotel_sale', null, me.public_ref, v_refund, null, null, null, me.public_ref, null, p_request_id);
  update public.game_property_state set has_hotel = false, houses = 4, updated_at = now() where game_id=p_game and property_ref=p_property_ref;
  -- devuelve el hotel al banco y retira 4 casas del stock (la propiedad vuelve a 4 casas).
  update public.game_runtime set hotels_available = hotels_available + 1, houses_available = houses_available - 4 where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'hotel_sold', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', p_property_ref, 'refund', v_refund), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', p_property_ref, 'has_hotel', false, 'houses', 4, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'sell_hotel', v_res);
  return v_res;
end $$;
grant execute on function public.sell_hotel(uuid, text, uuid, bigint) to authenticated;

-- ── mortgage_property (sin construcciones en TODO el grupo; recibe el valor de hipoteca) ──
create or replace function public.mortgage_property(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_owner text; v_idem jsonb;
        v_ver bigint; v_bal bigint; v_h int; v_hotel boolean; v_mort boolean; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  if rt.runtime_status = 'paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if v_owner is null or v_owner <> me.public_ref then raise exception 'NOT_OWNER'; end if;
  select houses, has_hotel, mortgaged into v_h, v_hotel, v_mort from public._p6_state(p_game, p_property_ref);
  if v_mort then raise exception 'ALREADY_MORTGAGED'; end if;
  -- no se puede hipotecar si HAY construcciones en cualquier propiedad del grupo
  if public._p6_group_max_level(p_game, c.board_key, c.group_key) > 0 then raise exception 'HAS_BUILDINGS'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p2_move(p_game, null, me.public_ref, c.mortgage_value);
  perform public._p2_post(p_game, 'mortgage_received', null, me.public_ref, c.mortgage_value, null, null, null, me.public_ref, null, p_request_id);
  insert into public.game_property_state(game_id, property_ref, mortgaged) values (p_game, p_property_ref, true)
    on conflict (game_id, property_ref) do update set mortgaged = true, updated_at = now();
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'property_mortgaged', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', p_property_ref, 'amount', c.mortgage_value), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', p_property_ref, 'mortgaged', true, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'mortgage_property', v_res);
  return v_res;
end $$;
grant execute on function public.mortgage_property(uuid, text, uuid, bigint) to authenticated;

-- ── unmortgage_property (paga hipoteca + 10%) ────────────────────────────────────────
create or replace function public.unmortgage_property(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_owner text; v_idem jsonb;
        v_ver bigint; v_bal bigint; v_mort boolean; v_cost int; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  if rt.runtime_status = 'paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if v_owner is null or v_owner <> me.public_ref then raise exception 'NOT_OWNER'; end if;
  select mortgaged into v_mort from public._p6_state(p_game, p_property_ref);
  if not v_mort then raise exception 'NOT_MORTGAGED'; end if;
  v_cost := public._p6_unmortgage_cost(c.mortgage_value);
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < v_cost then raise exception 'INSUFFICIENT_FUNDS'; end if;
  perform public._p2_move(p_game, me.public_ref, null, v_cost);
  perform public._p2_post(p_game, 'unmortgage_payment', me.public_ref, null, v_cost, null, null, null, me.public_ref, null, p_request_id);
  update public.game_property_state set mortgaged = false, updated_at = now() where game_id=p_game and property_ref=p_property_ref;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'property_unmortgaged', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', p_property_ref, 'cost', v_cost), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', p_property_ref, 'mortgaged', false, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'unmortgage_property', v_res);
  return v_res;
end $$;
grant execute on function public.unmortgage_property(uuid, text, uuid, bigint) to authenticated;
