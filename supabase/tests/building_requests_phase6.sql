-- ============================================================================
-- Fase 6 (pulido) — Solicitudes de construcción con aprobación del anfitrión: solicitar → aprobar ejecuta;
-- rechazar no cambia nada; no-host no aprueba; revalidación al aprobar; venta también por solicitud. Tras `db reset`.
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
create or replace function pg_temp._houses(gid uuid, prop text) returns int language sql security definer as $f$
  select coalesce((select houses from public.game_property_state where game_id=gid and property_ref=prop),0) $f$;
create or replace function pg_temp._stock(gid uuid) returns int language sql security definer as $f$ select houses_available from public.game_runtime where game_id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='f6000000-0000-0000-0000-0000000000a1'; j1 text:='f6000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('BReq IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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
  -- p1 posee el grupo marron completo (monopolio) y saldo holgado.
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-ronda-valencia',pg_temp._ctx('p1')); perform pg_temp._own(gid,'cl-plaza-lavapies',pg_temp._ctx('p1'));
  update public.player_balances set balance=100000 where game_id=gid;
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- BR1) p1 solicita construir casa: queda pendiente (no construye aún) y aparece en la bandeja del host + en my_building.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1u text:=pg_temp._ctx('p1_uid'); code text:=pg_temp._ctx('code'); rref text; snaph jsonb; snapp jsonb; begin
  perform pg_temp._as_user(p1u); rref := (request_build_house(gid,'cl-ronda-valencia',gen_random_uuid()))->>'request_ref';
  insert into _ctx values ('rref',rref);
  snapp := get_active_snapshot_by_code(code);  -- como p1: my_building_requests
  perform pg_temp._as_user(host); snaph := get_active_snapshot_by_code(code);  -- como host: building_requests
  perform pg_temp._as_admin();
  perform pg_temp._rec('BR1) solicitud pendiente: no construye, aparece en bandeja host y en mis solicitudes',
    pg_temp._houses(gid,'cl-ronda-valencia')=0
    and (snaph#>>'{building_requests,0,action}')='build_house'
    and (snapp#>>'{my_building_requests,0,property_ref}')='cl-ronda-valencia');
end $$;

-- BR2) un NO-host no puede resolver (NOT_HOST).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); rref text:=pg_temp._ctx('rref'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform resolve_building_request(rref, true, pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('BR2) no-host no resuelve (NOT_HOST)', ok);
end $$;

-- BR3) el host APRUEBA: se construye, se cobra (50) y baja el stock.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); rref text:=pg_temp._ctx('rref'); b0 bigint; b1 bigint; st0 int; res jsonb; begin
  perform pg_temp._as_admin(); select balance into b0 from public.player_balances where game_id=gid and player_ref=p1; st0:=pg_temp._stock(gid);
  perform pg_temp._as_user(host); res := resolve_building_request(rref, true, pg_temp._ver(gid));
  perform pg_temp._as_admin(); select balance into b1 from public.player_balances where game_id=gid and player_ref=p1;
  perform pg_temp._rec('BR3) aprobar construye, cobra 50 a p1 y baja stock',
    (res->>'status')='approved' and pg_temp._houses(gid,'cl-ronda-valencia')=1 and b0-b1=50 and pg_temp._stock(gid)=st0-1);
end $$;

-- BR4) RECHAZAR no cambia nada (p1 solicita otra casa; host rechaza; sin cobro ni construcción).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); rref text; b0 bigint; b1 bigint; h0 int; begin
  perform pg_temp._as_admin(); select balance into b0 from public.player_balances where game_id=gid and player_ref=p1; h0:=pg_temp._houses(gid,'cl-plaza-lavapies');
  perform pg_temp._as_user(p1u); rref := (request_build_house(gid,'cl-plaza-lavapies',gen_random_uuid()))->>'request_ref';
  perform pg_temp._as_user(host); perform resolve_building_request(rref, false, pg_temp._ver(gid));
  perform pg_temp._as_admin(); select balance into b1 from public.player_balances where game_id=gid and player_ref=p1;
  perform pg_temp._rec('BR4) rechazar no cambia nada (sin cobro ni construcción)',
    b0=b1 and pg_temp._houses(gid,'cl-plaza-lavapies')=h0
    and (select status from public.game_building_requests where public_ref=rref)='rejected');
end $$;

-- BR5) solicitud imposible se bloquea al solicitar (NOT_OWNER: p1 no posee una estación ajena).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform request_build_house(gid,'cl-estacion-goya',gen_random_uuid()); exception when others then ok:=(sqlerrm in ('NOT_OWNER','PROPERTY_NOT_STREET')); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('BR5) solicitud imposible se bloquea al solicitar', ok);
end $$;

-- BR6) revalidación al aprobar: tras solicitar (plaza 0→1, uniforme), el saldo de p1 se vacía → INSUFFICIENT_FUNDS.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); rref text; ok boolean:=false; begin
  perform pg_temp._as_user(p1u); rref := (request_build_house(gid,'cl-plaza-lavapies',gen_random_uuid()))->>'request_ref'; -- plaza 0→1 (uniforme: ronda 1, plaza 0, min 0)
  perform pg_temp._as_admin(); update public.player_balances set balance=0 where game_id=gid and player_ref=p1;  -- se queda sin saldo
  perform pg_temp._as_user(host);
  begin perform resolve_building_request(rref, true, pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='INSUFFICIENT_FUNDS'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('BR6) revalidación al aprobar: sin saldo → INSUFFICIENT_FUNDS', ok and pg_temp._houses(gid,'cl-plaza-lavapies')=0);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
