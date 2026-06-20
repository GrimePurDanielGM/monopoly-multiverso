-- ============================================================================
-- Fase 6 — Monopolios y construcción de casas: monopolio requerido, construcción uniforme, stock,
-- grupos no combinables entre tableros, venta de casas (uniformidad inversa). Tras `db reset`.
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
create or replace function pg_temp._houses(gid uuid, prop text) returns int language sql security definer as $f$
  select coalesce((select houses from public.game_property_state where game_id=gid and property_ref=prop),0) $f$;
create or replace function pg_temp._stock(gid uuid) returns int language sql security definer as $f$
  select houses_available from public.game_runtime where game_id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='f1000000-0000-0000-0000-0000000000a1'; j1 text:='f1000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Build IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code'; href:=r->>'host_public_ref';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',href),('host_uid',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- B1) sin grupo completo no se puede construir (GROUP_NOT_COMPLETE).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); ok boolean:=false; begin
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-ronda-valencia',href);  -- solo 1 de 2 del grupo marron
  perform pg_temp._as_user(host);
  begin perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_house'); exception when others then ok:=(sqlerrm='GROUP_NOT_COMPLETE'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('B1) sin grupo completo no construye (GROUP_NOT_COMPLETE)', ok);
end $$;

-- B2) con grupo completo construye casa: cobra house_cost (50) y baja el stock de casas.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); bal0 bigint; bal1 bigint; st0 int; res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-plaza-lavapies',href);  -- ahora monopolio marron (2/2)
  select balance into bal0 from public.player_balances where game_id=gid and player_ref=href; st0:=pg_temp._stock(gid);
  perform pg_temp._as_user(host); res := pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_house');
  perform pg_temp._as_admin(); select balance into bal1 from public.player_balances where game_id=gid and player_ref=href;
  perform pg_temp._rec('B2) construye casa: cobra 50, casas=1, stock-1',
    (res->>'houses')='1' and bal0-bal1=50 and pg_temp._houses(gid,'cl-ronda-valencia')=1 and pg_temp._stock(gid)=st0-1);
end $$;

-- B3) construcción uniforme: con 1-0 no se puede subir la misma a 2 (UNEVEN_BUILDING).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host);  -- ronda tiene 1 casa, lavapiés 0 → no se puede 2-0
  begin perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_house'); exception when others then ok:=(sqlerrm='UNEVEN_BUILDING'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('B3) construcción uniforme: no 2-0 (UNEVEN_BUILDING)', ok);
end $$;

-- B4) la otra del grupo sí puede subir a 1 (1-1 es uniforme); luego ya se puede 2-1.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok1 boolean; ok2 boolean; begin
  perform pg_temp._as_user(host);
  perform pg_temp._bld(gid, host, host, 'cl-plaza-lavapies', 'build_house');  -- 1-1
  perform pg_temp._as_admin(); ok1 := pg_temp._houses(gid,'cl-plaza-lavapies')=1;
  perform pg_temp._as_user(host);
  perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_house');  -- 2-1 (uniforme)
  perform pg_temp._as_admin(); ok2 := pg_temp._houses(gid,'cl-ronda-valencia')=2;
  perform pg_temp._rec('B4) 1-1 permitido y luego 2-1 (uniforme)', ok1 and ok2);
end $$;

-- B5) vender casa respeta uniformidad inversa: con 2-1, vender la de 1 falla (UNEVEN_BUILDING); vender la de 2 sube stock.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); st0 int; bad boolean:=false; res jsonb; begin
  perform pg_temp._as_user(host);
  begin perform pg_temp._bld(gid, host, host, 'cl-plaza-lavapies', 'sell_house'); exception when others then bad:=(sqlerrm='UNEVEN_BUILDING'); end; -- vender la baja deja 2-0
  perform pg_temp._as_admin(); st0:=pg_temp._stock(gid);
  perform pg_temp._as_user(host); res := pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'sell_house'); -- vender la alta (2→1)
  perform pg_temp._as_admin();
  perform pg_temp._rec('B5) venta uniforme inversa: no vender la baja; vender la alta repone stock',
    bad and (res->>'houses')='1' and pg_temp._stock(gid)=st0+1);
end $$;

-- B6) los grupos NO se combinan entre tableros: poseer marron en Classic no cuenta el marron de RdF.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; ntotal int; nclassic int; begin
  perform pg_temp._as_admin();
  ntotal := public._p6_group_total('classic','marron');  -- 2 (solo classic)
  -- monopolio marron classic ya confirmado arriba (host posee las 2 de classic); el de RdF es independiente
  perform pg_temp._rec('B6) grupos por tablero: marron Classic tiene 2 calles y no incluye RdF', ntotal=2 and public._p6_is_monopoly(gid,'cl-ronda-valencia'));
end $$;

-- B7) NOT_OWNER: un no-propietario no puede construir.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); ok boolean:=false; begin
  begin perform pg_temp._bld(gid, p1u, p1u, 'cl-ronda-valencia', 'build_house'); exception when others then ok:=(sqlerrm='NOT_OWNER'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('B7) no-propietario no construye (NOT_OWNER)', ok);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
