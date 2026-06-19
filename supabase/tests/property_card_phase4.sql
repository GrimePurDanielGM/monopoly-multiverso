-- ============================================================================
-- Ficha de propiedad (Fase 4 pulido): el snapshot expone los campos de la TARJETA por propiedad
-- (alquileres con casas/hotel, coste de casa/hotel, hipoteca y deshipoteca). Calles con todos;
-- estaciones/transportes solo rent_1..rent_3; utilities sin alquiler de mejoras. Tras `db reset`.
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

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='dc000000-0000-0000-0000-0000000000d1'; j1 text:='dc000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Card IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- helper: extrae la propiedad p del array properties del snapshot.
create or replace function pg_temp._prop(p_code text, p_host text, p_ref text) returns jsonb language plpgsql as $f$
declare snap jsonb; el jsonb; begin
  perform pg_temp._as_user(p_host); snap := get_active_snapshot_by_code(p_code); perform pg_temp._as_admin();
  for el in select * from jsonb_array_elements(snap->'properties') loop
    if el->>'property_ref' = p_ref then return el; end if;
  end loop; return null;
end $f$;

-- C1) Calle (Ronda de Valencia): rent_1..rent_4, rent_hotel, house/hotel cost, hipoteca y deshipoteca.
do $$ declare code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host'); p jsonb; begin
  p := pg_temp._prop(code, host, 'cl-ronda-valencia');
  perform pg_temp._rec('C1) calle expone alquileres con casas/hotel y costes',
    (p->>'rent_1')='10' and (p->>'rent_2')='30' and (p->>'rent_3')='90' and (p->>'rent_4')='160'
    and (p->>'rent_hotel')='250' and (p->>'house_cost')='50' and (p->>'hotel_cost')='50'
    and (p->>'mortgage_value')='30' and (p->>'unmortgage_cost')='33');
end $$;

-- C2) Estación: solo rent_1..rent_3 (50/100/200); sin rent_4/rent_hotel/house/hotel; hipoteca 100.
do $$ declare code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host'); p jsonb; begin
  p := pg_temp._prop(code, host, 'cl-estacion-norte');
  perform pg_temp._rec('C2) estación: rent_1..3 y sin mejoras',
    (p->>'rent_1')='50' and (p->>'rent_2')='100' and (p->>'rent_3')='200'
    and p->>'rent_4' is null and p->>'rent_hotel' is null and p->>'house_cost' is null
    and (p->>'mortgage_value')='100');
end $$;

-- C3) Servicio (utility): sin alquileres de mejoras; hipoteca 75; deshipoteca = ceil(75*1.1)=83.
do $$ declare code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host'); p jsonb; begin
  p := pg_temp._prop(code, host, 'cl-cia-aguas');
  perform pg_temp._rec('C3) utility: sin mejoras; hipoteca 75; deshipoteca 83',
    p->>'rent_1' is null and p->>'rent_hotel' is null and (p->>'mortgage_value')='75' and (p->>'unmortgage_cost')='83');
end $$;

-- C4) invariante: precio = 2 × hipoteca para toda propiedad comprable.
do $$ declare n int; begin
  perform pg_temp._as_admin();
  select count(*) into n from public.property_catalog where active and mortgage_value <> price/2;
  perform pg_temp._rec('C4) precio = 2 × hipoteca en las 56', n = 0);
end $$;

-- Gate final.
do $$ declare n int; begin select count(*) into n from _t where not ok;
  if n>0 then raise exception '% test(s) FAIL', n; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
