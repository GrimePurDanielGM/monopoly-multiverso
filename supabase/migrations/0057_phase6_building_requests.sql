-- Fase 6 (pulido) — Construir/vender casas y hoteles pasa por SOLICITUD + APROBACIÓN del anfitrión.
-- · _p6_do_*(game, owner, prop, req, dry): valida (y si !dry ejecuta) la acción para `owner` (no el llamador).
--   Soporta construir sin grupo completo (uniformidad sobre las calles del grupo que el owner posee).
-- · request_build_house/hotel/sell_house/sell_hotel: el propietario crea solicitud (pre-validada).
-- · resolve_building_request: el anfitrión aprueba (revalida + ejecuta) o rechaza.
-- · Las RPC directas de 0053 (build/sell) dejan de ser invocables por jugadores (revocadas).

create table if not exists public.game_building_requests (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null default public.gen_public_ref(),
  game_id uuid not null references public.games(id) on delete cascade,
  property_ref text not null references public.property_catalog(property_ref),
  requester_ref text not null,
  action text not null check (action in ('build_house','build_hotel','sell_house','sell_hotel')),
  status public.request_status not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  resolved_by_ref text null,
  result_ledger_ref text null
);
create unique index if not exists gbr_pubref_key on public.game_building_requests (public_ref);
create unique index if not exists gbr_one_pending on public.game_building_requests (game_id, property_ref, requester_ref, action) where status='pending';
create index if not exists gbr_game_pending_idx on public.game_building_requests (game_id) where status='pending';
alter table public.game_building_requests enable row level security;  -- deny-all: solo vía RPC

-- ¿el owner tiene alguna calle hipotecada en el grupo de p_prop? (bloquea construir; respeta posesión parcial)
create or replace function public._p6_owner_group_mortgage(p_game uuid, p_owner text, p_board text, p_group text) returns boolean
  language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.property_catalog c
    join public.property_ownership o on o.property_ref=c.property_ref and o.game_id=p_game and o.owner_ref=p_owner and o.released_at is null
    join public.game_property_state s on s.game_id=p_game and s.property_ref=c.property_ref
    where c.board_key=p_board and c.group_key=p_group and c.kind='street' and c.active and s.mortgaged);
$$;
revoke all on function public._p6_owner_group_mortgage(uuid,text,text,text) from public, anon, authenticated;

-- ── Núcleo: valida (y opcionalmente ejecuta) cada acción para `p_owner`. dry=true solo valida. ──
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
  if v_hotel or v_h >= 4 then raise exception 'UNEVEN_BUILDING'; end if;
  v_min := public._p6_owned_group_min(p_game, p_owner, c.board_key, c.group_key);
  if v_h > v_min then raise exception 'UNEVEN_BUILDING'; end if;
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
  if v_hotel or v_h <> 4 then raise exception 'UNEVEN_BUILDING'; end if;
  if not public._p6_owned_rest_max(p_game, p_owner, c.board_key, c.group_key, p_prop) then raise exception 'UNEVEN_BUILDING'; end if;
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
  v_max := public._p6_owned_group_max(p_game, p_owner, c.board_key, c.group_key);
  if v_h < v_max then raise exception 'UNEVEN_BUILDING'; end if;
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

create or replace function public._p6_do_sell_hotel(p_game uuid, p_owner text, p_prop text, p_request_id uuid, p_dry boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; c public.property_catalog; v_owner text; v_hotel boolean; v_refund bigint;
begin
  select * into rt from public.game_runtime where game_id=p_game;
  select * into c from public.property_catalog where property_ref=p_prop and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'street' then raise exception 'PROPERTY_NOT_STREET'; end if;
  if not exists(select 1 from public.players where game_id=p_game and public_ref=p_owner and kicked_at is null and left_at is null and bankrupt_at is null) then raise exception 'PLAYER_NOT_ACTIVE'; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_prop and released_at is null;
  if v_owner is null or v_owner <> p_owner then raise exception 'NOT_OWNER'; end if;
  select has_hotel into v_hotel from public._p6_state(p_game, p_prop);
  if not v_hotel then raise exception 'NO_BUILDING_TO_SELL'; end if;
  if rt.houses_available < 4 then raise exception 'INSUFFICIENT_HOUSES_AVAILABLE'; end if;
  v_refund := (c.hotel_cost / 2)::bigint;
  if p_dry then return jsonb_build_object('action','sell_hotel','amount',v_refund); end if;
  perform public._p2_move(p_game, null, p_owner, v_refund);
  perform public._p2_post(p_game, 'hotel_sale', null, p_owner, v_refund, null, null, null, p_owner, null, p_request_id);
  update public.game_property_state set has_hotel = false, houses = 4, updated_at = now() where game_id=p_game and property_ref=p_prop;
  update public.game_runtime set hotels_available = hotels_available + 1, houses_available = houses_available - 4 where game_id = p_game;
  perform public._audit(p_game, 'hotel_sold', auth.uid(), null, null, null,
            jsonb_build_object('property', p_prop, 'owner', p_owner, 'refund', v_refund), null, false);
  return jsonb_build_object('action','sell_hotel','amount',v_refund,'houses',4);
end $$;
revoke all on function public._p6_do_build_house(uuid,text,text,uuid,boolean) from public, anon, authenticated;
revoke all on function public._p6_do_build_hotel(uuid,text,text,uuid,boolean) from public, anon, authenticated;
revoke all on function public._p6_do_sell_house(uuid,text,text,uuid,boolean) from public, anon, authenticated;
revoke all on function public._p6_do_sell_hotel(uuid,text,text,uuid,boolean) from public, anon, authenticated;

-- ── Solicitud genérica del propietario (pre-valida con dry-run). ──
create or replace function public._p6_request(p_game uuid, p_prop text, p_action text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; v_idem jsonb; r public.game_building_requests; v_existing public.game_building_requests;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  if rt.runtime_status='paused' then raise exception 'GAME_PAUSED'; end if;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  -- pre-validación (dry-run) según la acción; lanza el error saneado si no procede
  case p_action
    when 'build_house' then perform public._p6_do_build_house(p_game, me.public_ref, p_prop, gen_random_uuid(), true);
    when 'build_hotel' then perform public._p6_do_build_hotel(p_game, me.public_ref, p_prop, gen_random_uuid(), true);
    when 'sell_house'  then perform public._p6_do_sell_house(p_game, me.public_ref, p_prop, gen_random_uuid(), true);
    when 'sell_hotel'  then perform public._p6_do_sell_hotel(p_game, me.public_ref, p_prop, gen_random_uuid(), true);
    else raise exception 'BAD_REQUEST';
  end case;
  select * into v_existing from public.game_building_requests where game_id=p_game and property_ref=p_prop and requester_ref=me.public_ref and action=p_action and status='pending';
  if found then
    perform public._p2_save(p_game, p_request_id, 'building_request', jsonb_build_object('request_ref', v_existing.public_ref, 'status','pending'));
    return jsonb_build_object('request_ref', v_existing.public_ref, 'status', 'pending');
  end if;
  insert into public.game_building_requests(game_id, property_ref, requester_ref, action) values (p_game, p_prop, me.public_ref, p_action) returning * into r;
  perform public._audit(p_game,'building_requested',auth.uid(),me.id,array[me.id],null,jsonb_build_object('property',p_prop,'action',p_action,'request',r.public_ref),null,false);
  perform public._emit_active_signal(p_game);
  perform public._p2_save(p_game, p_request_id, 'building_request', jsonb_build_object('request_ref', r.public_ref, 'status','pending'));
  return jsonb_build_object('request_ref', r.public_ref, 'status', 'pending');
end $$;

create or replace function public.request_build_house(p_game uuid, p_property_ref text, p_request_id uuid) returns jsonb language sql security definer set search_path=public,pg_temp as $$ select public._p6_request(p_game, p_property_ref, 'build_house', p_request_id) $$;
create or replace function public.request_build_hotel(p_game uuid, p_property_ref text, p_request_id uuid) returns jsonb language sql security definer set search_path=public,pg_temp as $$ select public._p6_request(p_game, p_property_ref, 'build_hotel', p_request_id) $$;
create or replace function public.request_sell_house(p_game uuid, p_property_ref text, p_request_id uuid) returns jsonb language sql security definer set search_path=public,pg_temp as $$ select public._p6_request(p_game, p_property_ref, 'sell_house', p_request_id) $$;
create or replace function public.request_sell_hotel(p_game uuid, p_property_ref text, p_request_id uuid) returns jsonb language sql security definer set search_path=public,pg_temp as $$ select public._p6_request(p_game, p_property_ref, 'sell_hotel', p_request_id) $$;
grant execute on function public.request_build_house(uuid,text,uuid) to authenticated;
grant execute on function public.request_build_hotel(uuid,text,uuid) to authenticated;
grant execute on function public.request_sell_house(uuid,text,uuid) to authenticated;
grant execute on function public.request_sell_hotel(uuid,text,uuid) to authenticated;

-- ── El anfitrión aprueba (revalida + ejecuta) o rechaza una solicitud de construcción. ──
create or replace function public.resolve_building_request(p_request_ref text, p_accept boolean, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.game_building_requests; g public.games; rt public.game_runtime; v_host_ref text; v_ver bigint; v_res jsonb;
begin
  select * into r from public.game_building_requests where public_ref=p_request_ref for update;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(r.game_id);
  select * into rt from public.game_runtime where game_id=g.id for update;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  if rt.runtime_status='paused' then raise exception 'GAME_PAUSED'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'idempotent', true); end if;
  select public_ref into v_host_ref from public.players where id=g.host_player_id;
  if not p_accept then
    update public.game_building_requests set status='rejected', resolved_at=now(), resolved_by_ref=v_host_ref where id=r.id;
    perform public._audit(g.id,'building_rejected',auth.uid(),null,null,null,jsonb_build_object('request',r.public_ref,'property',r.property_ref,'action',r.action),null,false);
    perform public._emit_active_signal(g.id);
    return jsonb_build_object('status','rejected');
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  -- Revalidar + ejecutar (el estado puede haber cambiado desde la solicitud).
  case r.action
    when 'build_house' then v_res := public._p6_do_build_house(g.id, r.requester_ref, r.property_ref, gen_random_uuid(), false);
    when 'build_hotel' then v_res := public._p6_do_build_hotel(g.id, r.requester_ref, r.property_ref, gen_random_uuid(), false);
    when 'sell_house'  then v_res := public._p6_do_sell_house(g.id, r.requester_ref, r.property_ref, gen_random_uuid(), false);
    when 'sell_hotel'  then v_res := public._p6_do_sell_hotel(g.id, r.requester_ref, r.property_ref, gen_random_uuid(), false);
  end case;
  update public.game_building_requests set status='approved', resolved_at=now(), resolved_by_ref=v_host_ref where id=r.id;
  v_ver := public._p2_bump(g.id);
  perform public._audit(g.id,'building_approved',auth.uid(),null,null,null,jsonb_build_object('request',r.public_ref,'property',r.property_ref,'action',r.action),null,false);
  perform public._emit_active_signal(g.id);
  return v_res || jsonb_build_object('status','approved','runtime_version',v_ver);
end $$;
grant execute on function public.resolve_building_request(text, boolean, bigint) to authenticated;

-- ── Las RPC directas de construcción/venta de 0053 dejan de ser invocables por jugadores. ──
revoke execute on function public.build_house(uuid, text, uuid, bigint) from authenticated;
revoke execute on function public.build_hotel(uuid, text, uuid, bigint) from authenticated;
revoke execute on function public.sell_house(uuid, text, uuid, bigint) from authenticated;
revoke execute on function public.sell_hotel(uuid, text, uuid, bigint) from authenticated;
