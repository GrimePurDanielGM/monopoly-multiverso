-- ============================================================================
-- Fase 6 — Hoteles: requieren 4 casas en todo el grupo; consumen 1 hotel y devuelven 4 casas al stock;
-- vender hotel repone 4 casas (o bloquea si no hay stock). Stock de hoteles. Tras `db reset`.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
drop table if exists _ctx; create temp table _ctx(k text primary key, v text);
grant select, insert, update, delete on _t, _ctx to authenticated;
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $f$
begin perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true); if auth.uid()<>uid::uuid then raise exception 'bad'; end if; end $f$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $f$ begin perform set_config('role', session_user, true); end $f$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;
create or replace function pg_temp._ctx(k text) returns text language sql as $f$ select v from _ctx where k=$1 $f$;
create or replace function pg_temp._ver(gid uuid) returns bigint language sql security definer as $f$ select runtime_version from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._bld(gid uuid, owner_uid text, host_uid text, prop text, action text) returns jsonb language plpgsql as $f$
declare rref text; r jsonb; begin
  perform pg_temp._as_user(owner_uid);
  rref := (case action
    when 'build_house' then request_build_house(gid, prop, gen_random_uuid())
    when 'build_hotel' then request_build_hotel(gid, prop, gen_random_uuid())
    when 'sell_house'  then request_sell_house(gid, prop, gen_random_uuid())
    when 'sell_hotel'  then request_sell_hotel(gid, prop, gen_random_uuid()) end)->>'request_ref';
  perform pg_temp._as_user(host_uid); r := resolve_building_request(rref, true, pg_temp._ver(gid));
  perform pg_temp._as_admin(); return r;
end $f$;
create or replace function pg_temp._own(gid uuid, prop text, owner_ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,owner_ref) on conflict do nothing $f$;
create or replace function pg_temp._hstock(gid uuid) returns int language sql security definer as $f$ select houses_available from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._tstock(gid uuid) returns int language sql security definer as $f$ select hotels_available from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._hh(gid uuid, prop text) returns boolean language sql security definer as $f$ select coalesce((select has_hotel from public.game_property_state where game_id=gid and property_ref=prop),false) $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='f2000000-0000-0000-0000-0000000000a1'; j1 text:='f2000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; i int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Hotel IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code'; href:=r->>'host_public_ref';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',href),('host_uid',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v);
  -- host posee marron y le damos saldo holgado; construye 4-4 (uniforme)
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-ronda-valencia',href); perform pg_temp._own(gid,'cl-plaza-lavapies',href);
  update public.player_balances set balance=100000 where game_id=gid and player_ref=href;
  perform pg_temp._as_user(host);
  for i in 1..4 loop
    perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_house');
    perform pg_temp._bld(gid, host, host, 'cl-plaza-lavapies', 'build_house');
  end loop;
  perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- H1) hotel requiere que TODO el grupo esté a 4: bajar lavapiés a 3 → build_hotel en ronda falla (UNEVEN_BUILDING).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host); perform pg_temp._bld(gid, host, host, 'cl-plaza-lavapies', 'sell_house'); -- 4-3
  begin perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_hotel'); exception when others then ok:=(sqlerrm='UNEVEN_BUILDING'); end;
  perform pg_temp._as_user(host); perform pg_temp._bld(gid, host, host, 'cl-plaza-lavapies', 'build_house'); -- vuelve a 4-4
  perform pg_temp._as_admin();
  perform pg_temp._rec('H1) hotel exige todo el grupo a 4 (UNEVEN_BUILDING si no)', ok);
end $$;

-- H2) construir hotel: cobra hotel_cost (50), consume 1 hotel y DEVUELVE 4 casas al stock.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref');
            hs0 int; ts0 int; b0 bigint; b1 bigint; res jsonb; begin
  perform pg_temp._as_admin(); hs0:=pg_temp._hstock(gid); ts0:=pg_temp._tstock(gid);
  select balance into b0 from public.player_balances where game_id=gid and player_ref=href;
  perform pg_temp._as_user(host); res := pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_hotel');
  perform pg_temp._as_admin(); select balance into b1 from public.player_balances where game_id=gid and player_ref=href;
  perform pg_temp._rec('H2) hotel: cobra 50, hotel=true, hoteles-1, casas+4',
    (res->>'has_hotel')='true' and b0-b1=50 and pg_temp._hh(gid,'cl-ronda-valencia')
    and pg_temp._tstock(gid)=ts0-1 and pg_temp._hstock(gid)=hs0+4);
end $$;

-- H3) vender hotel: reembolso 25, devuelve hotel y repone 4 casas (vuelve a 4 casas).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref');
            hs0 int; ts0 int; b0 bigint; b1 bigint; res jsonb; begin
  perform pg_temp._as_admin(); hs0:=pg_temp._hstock(gid); ts0:=pg_temp._tstock(gid);
  select balance into b0 from public.player_balances where game_id=gid and player_ref=href;
  perform pg_temp._as_user(host); res := pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'sell_hotel');
  perform pg_temp._as_admin(); select balance into b1 from public.player_balances where game_id=gid and player_ref=href;
  perform pg_temp._rec('H3) vender hotel: reembolso 25, hoteles+1, casas-4, vuelve a 4 casas',
    (res->>'houses')='4' and b1-b0=25 and not pg_temp._hh(gid,'cl-ronda-valencia')
    and pg_temp._tstock(gid)=ts0+1 and pg_temp._hstock(gid)=hs0-4);
end $$;

-- H4) vender hotel bloqueado si no hay 4 casas en el stock (INSUFFICIENT_HOUSES_AVAILABLE).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host); perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_hotel'); -- hotel de nuevo
  perform pg_temp._as_admin(); update public.game_runtime set houses_available=2 where game_id=gid; -- sin stock para reponer 4
  perform pg_temp._as_user(host);
  begin perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'sell_hotel'); exception when others then ok:=(sqlerrm='INSUFFICIENT_HOUSES_AVAILABLE'); end;
  perform pg_temp._as_admin(); update public.game_runtime set houses_available=20 where game_id=gid;
  perform pg_temp._rec('H4) vender hotel sin stock de casas → INSUFFICIENT_HOUSES_AVAILABLE', ok);
end $$;

-- H5) construir hotel sin hoteles en el banco → INSUFFICIENT_HOTELS_AVAILABLE.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host); perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'sell_hotel'); -- vuelve a 4 casas
  perform pg_temp._as_admin(); update public.game_runtime set hotels_available=0 where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_hotel'); exception when others then ok:=(sqlerrm='INSUFFICIENT_HOTELS_AVAILABLE'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('H5) construir hotel sin stock de hoteles → INSUFFICIENT_HOTELS_AVAILABLE', ok);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
