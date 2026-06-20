-- ============================================================================
-- Bloqueo de doble pago de alquiler por la MISMA caída (Fase 5 corrección): calles, estaciones y servicios.
-- Tras pagar, un segundo pago de la misma caída → RENT_ALREADY_PAID; el snapshot marca la caída resuelta;
-- una nueva caída (movimiento o recolocación del anfitrión) reabre el pago. Privacidad de saldos. Tras `db reset`.
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
create or replace function pg_temp._own(gid uuid, prop text, owner_ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,owner_ref) on conflict do nothing $f$;
create or replace function pg_temp._land(gid uuid) returns void language sql security definer as $f$
  update public.game_runtime set landing_seq = landing_seq + 1 where game_id=gid $f$;
-- Estado de "caída resuelta" leído directamente del runtime (sin depender de auth; mismo valor que el snapshot).
create or replace function pg_temp._resolved(gid uuid, code text) returns boolean language sql security definer as $f$
  select (rent_resolved_seq >= landing_seq) from public.game_runtime where game_id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='e2000000-0000-0000-0000-0000000000a1'; j1 text:='e2000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Once IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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
  -- p1 posee una calle, una estación y un servicio.
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-bailen',pg_temp._ctx('p1'));
  perform pg_temp._own(gid,'cl-estacion-goya',pg_temp._ctx('p1')); perform pg_temp._own(gid,'cl-cia-electricidad',pg_temp._ctx('p1'));
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- R1/R2/R3) calle: pagar una vez; segundo pago bloqueado; snapshot marca resuelta.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); ok2 boolean:=false; res jsonb; snap_resolved boolean; begin
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  perform pg_temp._as_user(host); res := pay_rent(gid,'cl-bailen',gen_random_uuid(),pg_temp._ver(gid));
  begin perform pay_rent(gid,'cl-bailen',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok2:=(sqlerrm='RENT_ALREADY_PAID'); end;
  -- el snapshot (saneado, como host autenticado) expone la caída ya resuelta
  snap_resolved := (get_active_snapshot_by_code(code)->>'current_landing_rent_resolved')::boolean;
  perform pg_temp._as_admin();
  perform pg_temp._rec('R1) calle: primer pago OK', (res->>'amount')::int > 0);
  perform pg_temp._rec('R2) calle: segundo pago misma caída → RENT_ALREADY_PAID', ok2);
  perform pg_temp._rec('R3) snapshot expone current_landing_rent_resolved=true', snap_resolved and pg_temp._resolved(gid, code));
end $$;

-- R4) nueva caída (movimiento simulado) → puede pagar de nuevo la misma propiedad.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  perform pg_temp._rec('R4a) tras nueva caída el snapshot ya NO está resuelto', not pg_temp._resolved(gid, code));
  perform pg_temp._as_user(host); res := pay_rent(gid,'cl-bailen',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('R4b) puede volver a pagar en una nueva caída', (res->>'amount')::int > 0);
end $$;

-- R5) estación: pagar una vez; segundo pago bloqueado.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok2 boolean:=false; res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  perform pg_temp._as_user(host); res := pay_rent(gid,'cl-estacion-goya',gen_random_uuid(),pg_temp._ver(gid));
  begin perform pay_rent(gid,'cl-estacion-goya',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok2:=(sqlerrm='RENT_ALREADY_PAID'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('R5) estación: primer pago OK y segundo bloqueado', (res->>'amount')='25' and ok2);
end $$;

-- R6) servicio: pagar una vez (con la última tirada del pagador); segundo pago bloqueado.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); ok2 boolean:=false; res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  update public.game_runtime set last_roll = jsonb_build_object('total',7,'player_ref',href) where game_id=gid;
  perform pg_temp._as_user(host); res := pay_utility_rent(gid,'cl-cia-electricidad',null,null,gen_random_uuid(),pg_temp._ver(gid));
  begin perform pay_utility_rent(gid,'cl-cia-electricidad',null,null,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok2:=(sqlerrm='RENT_ALREADY_PAID'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('R6) servicio: primer pago OK y segundo bloqueado', (res->>'amount')='28' and ok2);
end $$;

-- R7) la recolocación del anfitrión crea una caída NUEVA (no auto-resuelta) → vuelve a ser pagable.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); code text:=pg_temp._ctx('code'); res jsonb; begin
  perform pg_temp._as_user(host); perform host_set_player_position(gid, href, 'classic', 27, 'recolocar (test)', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('R7a) tras recolocar, la caída no está resuelta', not pg_temp._resolved(gid, code));
  perform pg_temp._as_user(host); res := pay_rent(gid,'cl-bailen',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('R7b) tras recolocar se puede pagar de nuevo', (res->>'amount')::int > 0);
end $$;

-- R8) privacidad de saldos: en el snapshot del pagador, el saldo de p1 es null.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); p1 text:=pg_temp._ctx('p1'); snap jsonb; p1bal jsonb; begin
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  select (e->'balance') into p1bal from jsonb_array_elements(snap->'players') e where e->>'public_ref'=p1;
  perform pg_temp._rec('R8) privacidad de saldos: saldo de otro jugador oculto (null)', p1bal = 'null'::jsonb);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
