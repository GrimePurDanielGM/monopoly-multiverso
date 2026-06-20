-- Fase 6 (pulido final) — Con `allow_build_without_monopoly = true` NO se aplica construcción uniforme,
-- ni siquiera al completar el grupo de color. Se recrean los tres helpers _p6_do_* que comprobaban
-- uniformidad (build_house, build_hotel, sell_house) para SALTARSE esa comprobación cuando la regla está
-- activada. Se mantienen TODAS las demás validaciones por propiedad (≤4 casas, hotel tras 4 casas, stock,
-- saldo, no hipotecada, solo calles, propietario activo, grupo sin hipoteca, elegibilidad/aprobación).
-- _p6_do_sell_hotel no usaba uniformidad: no se toca.

create or replace function public._p6_do_build_house(p_game uuid, p_owner text, p_prop text, p_request_id uuid, p_dry boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; c public.property_catalog; v_owner text; v_h int; v_hotel boolean; v_mort boolean; v_min int; v_bal bigint;
begin
  select * into rt from public.game_runtime where game_id=p_game;
  select * into c from public.property_catalog where property_ref=p_prop and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  if not exists(select 1 from public.players where game_id=p_game and public_ref=p_owner and kicked_at is null and left_at is null and bankrupt_at is null) then raise exception 'PLAYER_NOT_ACTIVE'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_prop and released_at is null;
  if v_owner is null or v_owner <> p_owner then raise exception 'NOT_OWNER'; end if;
  select houses, has_hotel, mortgaged into v_h, v_hotel, v_mort from public._p6_state(p_game, p_prop);
  if v_mort then raise exception 'PROPERTY_MORTGAGED'; end if;
  if not public._p6_build_eligible(p_game, p_prop) then raise exception 'GROUP_NOT_COMPLETE'; end if;
  if public._p6_owner_group_mortgage(p_game, p_owner, c.board_key, c.group_key) then raise exception 'GROUP_HAS_MORTGAGE'; end if;
  if v_hotel or v_h >= 4 then raise exception 'UNEVEN_BUILDING'; end if;  -- por propiedad: máx. 4 casas antes de hotel
  if not public._p6_allow_no_monopoly(p_game) then                        -- uniformidad SOLO si la regla está desactivada
    v_min := public._p6_owned_group_min(p_game, p_owner, c.board_key, c.group_key);
    if v_h > v_min then raise exception 'UNEVEN_BUILDING'; end if;
  end if;
  if rt.houses_available < 1 then raise exception 'INSUFFICIENT_HOUSES_AVAILABLE'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_owner;
  if v_bal < c.house_cost then raise exception 'INSUFFICIENT_FUNDS'; end if;
  if p_dry then return jsonb_build_object('action','build_house','amount',c.house_cost); end if;
  perform public._p2_move(p_game, p_owner, null, c.house_cost);
  perform public._p2_post(p_game, 'building_purchase', p_owner, null, c.house_cost, null, null, null, p_owner, null, p_request_id);
  insert into public.game_property_state(game_id, property_ref, houses) values (p_game, p_prop, v_h + 1)
    on conflict (game_id, property_ref) do update set houses = v_h + 1, updated_at = now();
  update public.game_runtime set houses_available = houses_available - 1 where game_id = p_game;
  perform public._audit(p_game, 'house_built', auth.uid(), null, null, null,
            jsonb_build_object('property', p_prop, 'owner', p_owner, 'houses', v_h + 1, 'cost', c.house_cost), null, false);
  return jsonb_build_object('action','build_house','amount',c.house_cost,'houses',v_h+1);
end $$;

create or replace function public._p6_do_build_hotel(p_game uuid, p_owner text, p_prop text, p_request_id uuid, p_dry boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; c public.property_catalog; v_owner text; v_h int; v_hotel boolean; v_mort boolean; v_bal bigint;
begin
  select * into rt from public.game_runtime where game_id=p_game;
  select * into c from public.property_catalog where property_ref=p_prop and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  if not exists(select 1 from public.players where game_id=p_game and public_ref=p_owner and kicked_at is null and left_at is null and bankrupt_at is null) then raise exception 'PLAYER_NOT_ACTIVE'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_prop and released_at is null;
  if v_owner is null or v_owner <> p_owner then raise exception 'NOT_OWNER'; end if;
  select houses, has_hotel, mortgaged into v_h, v_hotel, v_mort from public._p6_state(p_game, p_prop);
  if v_mort then raise exception 'PROPERTY_MORTGAGED'; end if;
  if not public._p6_build_eligible(p_game, p_prop) then raise exception 'GROUP_NOT_COMPLETE'; end if;
  if public._p6_owner_group_mortgage(p_game, p_owner, c.board_key, c.group_key) then raise exception 'GROUP_HAS_MORTGAGE'; end if;
  if v_hotel or v_h <> 4 then raise exception 'UNEVEN_BUILDING'; end if;  -- por propiedad: hotel solo con 4 casas
  if not public._p6_allow_no_monopoly(p_game) then                        -- uniformidad del resto SOLO si la regla está desactivada
    if not public._p6_owned_rest_max(p_game, p_owner, c.board_key, c.group_key, p_prop) then raise exception 'UNEVEN_BUILDING'; end if;
  end if;
  if rt.hotels_available < 1 then raise exception 'INSUFFICIENT_HOTELS_AVAILABLE'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_owner;
  if v_bal < c.hotel_cost then raise exception 'INSUFFICIENT_FUNDS'; end if;
  if p_dry then return jsonb_build_object('action','build_hotel','amount',c.hotel_cost); end if;
  perform public._p2_move(p_game, p_owner, null, c.hotel_cost);
  perform public._p2_post(p_game, 'hotel_purchase', p_owner, null, c.hotel_cost, null, null, null, p_owner, null, p_request_id);
  update public.game_property_state set houses = 0, has_hotel = true, updated_at = now() where game_id=p_game and property_ref=p_prop;
  update public.game_runtime set hotels_available = hotels_available - 1, houses_available = houses_available + 4 where game_id = p_game;
  perform public._audit(p_game, 'hotel_built', auth.uid(), null, null, null,
            jsonb_build_object('property', p_prop, 'owner', p_owner, 'cost', c.hotel_cost), null, false);
  return jsonb_build_object('action','build_hotel','amount',c.hotel_cost,'has_hotel',true);
end $$;

create or replace function public._p6_do_sell_house(p_game uuid, p_owner text, p_prop text, p_request_id uuid, p_dry boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.property_catalog; v_owner text; v_h int; v_hotel boolean; v_max int; v_refund bigint;
begin
  select * into c from public.property_catalog where property_ref=p_prop and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  if not exists(select 1 from public.players where game_id=p_game and public_ref=p_owner and kicked_at is null and left_at is null and bankrupt_at is null) then raise exception 'PLAYER_NOT_ACTIVE'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_prop and released_at is null;
  if v_owner is null or v_owner <> p_owner then raise exception 'NOT_OWNER'; end if;
  select houses, has_hotel into v_h, v_hotel from public._p6_state(p_game, p_prop);
  if v_hotel or v_h <= 0 then raise exception 'NO_BUILDING_TO_SELL'; end if;
  if not public._p6_allow_no_monopoly(p_game) then                        -- uniformidad inversa SOLO si la regla está desactivada
    v_max := public._p6_owned_group_max(p_game, p_owner, c.board_key, c.group_key);
    if v_h < v_max then raise exception 'UNEVEN_BUILDING'; end if;
  end if;
  v_refund := (c.house_cost / 2)::bigint;
  if p_dry then return jsonb_build_object('action','sell_house','amount',v_refund); end if;
  perform public._p2_move(p_game, null, p_owner, v_refund);
  perform public._p2_post(p_game, 'building_sale', null, p_owner, v_refund, null, null, null, p_owner, null, p_request_id);
  update public.game_property_state set houses = v_h - 1, updated_at = now() where game_id=p_game and property_ref=p_prop;
  update public.game_runtime set houses_available = houses_available + 1 where game_id = p_game;
  perform public._audit(p_game, 'house_sold', auth.uid(), null, null, null,
            jsonb_build_object('property', p_prop, 'owner', p_owner, 'houses', v_h - 1, 'refund', v_refund), null, false);
  return jsonb_build_object('action','sell_house','amount',v_refund,'houses',v_h-1);
end $$;

revoke all on function public._p6_do_build_house(uuid,text,text,uuid,boolean) from public, anon, authenticated;
revoke all on function public._p6_do_build_hotel(uuid,text,text,uuid,boolean) from public, anon, authenticated;
revoke all on function public._p6_do_sell_house(uuid,text,text,uuid,boolean) from public, anon, authenticated;
