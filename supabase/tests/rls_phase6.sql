-- ============================================================================
-- Fase 6 — Seguridad/snapshot: game_property_state es deny-all (solo vía RPC); el snapshot no expone ids
-- internos ni saldos ajenos, y sí expone building_stock + estado de construcción por propiedad. Tras `db reset`.
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
create or replace function pg_temp._own(gid uuid, prop text, owner_ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,owner_ref) on conflict do nothing $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='f5000000-0000-0000-0000-0000000000a1'; j1 text:='f5000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('RLS6 IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code'; href:=r->>'host_public_ref';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',href);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v);
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-ronda-valencia',href); perform pg_temp._own(gid,'cl-plaza-lavapies',href);
  insert into public.game_property_state(game_id,property_ref,houses) values (gid,'cl-ronda-valencia',2) on conflict (game_id,property_ref) do update set houses=2;
  update public.game_runtime set houses_available=30 where game_id=gid;  -- coherente con las 2 casas colocadas
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- R1) game_property_state deny-all: authenticated no puede leer ni escribir directamente.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); rsel boolean:=false; rins boolean:=false; n int; begin
  perform pg_temp._as_user(p1u);
  begin select count(*) into n from public.game_property_state; rsel:=(n=0); exception when insufficient_privilege then rsel:=true; end;  -- RLS oculta filas (0) o deniega
  begin insert into public.game_property_state(game_id,property_ref,houses) values (gid,'cl-bravo-murillo',1); exception when insufficient_privilege then rins:=true; when others then rins:=true; end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('R1) game_property_state deny-all (sin lectura/escritura directa)', rsel and rins);
end $$;

-- R2) el snapshot no expone ids internos (auth_uid, host_recovery, request_secrets).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); snap text; begin
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code)::text; perform pg_temp._as_admin();
  perform pg_temp._rec('R2) snapshot sin ids internos',
    snap not ilike '%auth_uid%' and snap not ilike '%host_recovery%' and snap not ilike '%request_secret%');
end $$;

-- R3) privacidad de saldos: el saldo de p1 es null en el snapshot del host.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); p1 text:=pg_temp._ctx('p1'); snap jsonb; p1bal jsonb; begin
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  select (e->'balance') into p1bal from jsonb_array_elements(snap->'players') e where e->>'public_ref'=p1;
  perform pg_temp._rec('R3) privacidad de saldos (saldo ajeno null)', p1bal = 'null'::jsonb);
end $$;

-- R4) el snapshot expone building_stock (32/12) y estado de construcción por propiedad.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); snap jsonb; prop jsonb; begin
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  select e into prop from jsonb_array_elements(snap->'properties') e where e->>'property_ref'='cl-ronda-valencia';
  perform pg_temp._rec('R4) snapshot expone building_stock + estado por propiedad',
    (snap#>>'{building_stock,houses_available}')='30' and (snap#>>'{building_stock,hotels_available}')='12'
    and (prop->>'houses')='2' and (prop->>'monopoly')='true' and (prop->>'mortgaged')='false' and (prop->>'rent_due') is not null);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
