-- ============================================================================
-- Fase 6 — Alquiler avanzado de calles: sin monopolio=base; monopolio sin casas=base×2; 1–4 casas=rent_N;
-- hotel=rent_hotel. Mantiene escala de estaciones y el bloqueo de doble pago (rent-once). Tras `db reset`.
-- Grupo celeste (cl-cuatro-caminos): base 6, rent 30/90/270/400, hotel 550.
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
create or replace function pg_temp._land(gid uuid) returns void language sql security definer as $f$ update public.game_runtime set landing_seq=landing_seq+1 where game_id=gid $f$;
-- p1 paga el alquiler de prop (con caída nueva) y devuelve el importe cobrado.
create or replace function pg_temp._pay(gid uuid, p1u text, prop text) returns int language plpgsql as $f$
declare res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  perform pg_temp._as_user(p1u); res := pay_rent(gid, prop, gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin(); return (res->>'amount')::int;
end $f$;
-- el dueño (host) construye una casa en cada calle del grupo celeste (sube el nivel uniformemente).
create or replace function pg_temp._round(gid uuid, host text) returns void language plpgsql as $f$
begin
  perform pg_temp._as_user(host);
  perform pg_temp._bld(gid, host, host, 'cl-cuatro-caminos', 'build_house');
  perform pg_temp._bld(gid, host, host, 'cl-reina-victoria', 'build_house');
  perform pg_temp._bld(gid, host, host, 'cl-bravo-murillo', 'build_house');
  perform pg_temp._as_admin();
end $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='f4000000-0000-0000-0000-0000000000a1'; j1 text:='f4000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('AdvRent IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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
  perform pg_temp._as_user(host); perform start_game(gid,v);
  -- host posee solo cuatro-caminos al principio; saldos holgados para construir/pagar.
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-cuatro-caminos',href);
  update public.player_balances set balance=100000 where game_id=gid;
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- A1) sin monopolio cobra base (6).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); begin
  perform pg_temp._rec('A1) sin monopolio cobra base (6)', pg_temp._pay(gid,p1u,'cl-cuatro-caminos')=6);
end $$;

-- A2) monopolio sin casas cobra base×2 (12).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); href text:=pg_temp._ctx('host_ref'); begin
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-reina-victoria',href); perform pg_temp._own(gid,'cl-bravo-murillo',href);
  perform pg_temp._rec('A2) monopolio sin casas cobra base×2 (12)', pg_temp._pay(gid,p1u,'cl-cuatro-caminos')=12);
end $$;

-- A3..A6) 1–4 casas cobran rent_1..rent_4 (30/90/270/400).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); host text:=pg_temp._ctx('host'); begin
  perform pg_temp._round(gid,host); perform pg_temp._rec('A3) 1 casa cobra rent_1 (30)', pg_temp._pay(gid,p1u,'cl-cuatro-caminos')=30);
  perform pg_temp._round(gid,host); perform pg_temp._rec('A4) 2 casas cobra rent_2 (90)', pg_temp._pay(gid,p1u,'cl-cuatro-caminos')=90);
  perform pg_temp._round(gid,host); perform pg_temp._rec('A5) 3 casas cobra rent_3 (270)', pg_temp._pay(gid,p1u,'cl-cuatro-caminos')=270);
  perform pg_temp._round(gid,host); perform pg_temp._rec('A6) 4 casas cobra rent_4 (400)', pg_temp._pay(gid,p1u,'cl-cuatro-caminos')=400);
end $$;

-- A7) hotel cobra rent_hotel (550).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); host text:=pg_temp._ctx('host'); begin
  perform pg_temp._as_user(host); perform pg_temp._bld(gid, host, host, 'cl-cuatro-caminos', 'build_hotel'); perform pg_temp._as_admin();
  perform pg_temp._rec('A7) hotel cobra rent_hotel (550)', pg_temp._pay(gid,p1u,'cl-cuatro-caminos')=550);
end $$;

-- A10) rent-once: pagar dos veces la misma caída → RENT_ALREADY_PAID.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); ok boolean:=false; begin
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  perform pg_temp._as_user(p1u); perform pay_rent(gid,'cl-cuatro-caminos',gen_random_uuid(),pg_temp._ver(gid));
  begin perform pay_rent(gid,'cl-cuatro-caminos',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='RENT_ALREADY_PAID'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('A10) rent-once sigue activo (RENT_ALREADY_PAID)', ok);
end $$;

-- A8) estaciones siguen su escala (1 estación → 25) tras Fase 6.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); href text:=pg_temp._ctx('host_ref'); begin
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-estacion-goya',href);
  perform pg_temp._rec('A8) estación sigue escala (1 → 25)', pg_temp._pay(gid,p1u,'cl-estacion-goya')=25);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
