-- ============================================================================
-- Fase 6 (pulido) — Stock inicial configurable (mín 32/12) y "construir sin grupo completo". Tras `db reset`.
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
create or replace function pg_temp._gv(gid uuid) returns int language sql security definer as $f$ select version from public.games where id=gid $f$;
create or replace function pg_temp._own(gid uuid, prop text, owner_ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,owner_ref) on conflict do nothing $f$;
create or replace function pg_temp._bldreq(gid uuid, owner_uid text, host_uid text, prop text) returns jsonb language plpgsql as $f$
declare rref text; r jsonb; begin
  perform pg_temp._as_user(owner_uid); rref := (request_build_house(gid, prop, gen_random_uuid()))->>'request_ref';
  perform pg_temp._as_user(host_uid); r := resolve_building_request(rref, true, pg_temp._ver(gid));
  perform pg_temp._as_admin(); return r;
end $f$;
create or replace function pg_temp._houses(gid uuid, prop text) returns int language sql security definer as $f$
  select coalesce((select houses from public.game_property_state where game_id=gid and property_ref=prop),0) $f$;

-- _build(houses, hotels, allow_no_mono): crea una partida con stock y regla configurados antes de iniciar.
create or replace function pg_temp._build(p_houses int, p_hotels int, p_nomono boolean) returns void language plpgsql as $f$
declare host text:='f7000000-0000-0000-0000-0000000000a1'; j1 text:='f7000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Stock IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code'; href:=r->>'host_public_ref';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',href),('host_uid',host) on conflict (k) do update set v=excluded.v;
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2,
    'initial_houses_available',p_houses,'initial_hotels_available',p_hotels,'allow_build_without_monopoly',p_nomono), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid on conflict (k) do update set v=excluded.v;
  insert into _ctx values ('p1_uid',j1) on conflict (k) do update set v=excluded.v;
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;

-- C1) default 32/12 cuando no se configura nada.
do $$ declare gid uuid; begin
  perform pg_temp._build(32, 12, false); gid:=pg_temp._ctx('gid')::uuid;
  perform pg_temp._rec('C1) default 32/12',
    (select houses_available from public.game_runtime where game_id=gid)=32
    and (select hotels_available from public.game_runtime where game_id=gid)=12);
end $$;

-- C2) el anfitrión NO puede bajar de 32/12 (INVALID_BUILDING_STOCK).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok1 boolean:=false; ok2 boolean:=false; begin
  -- en una partida ya activa update_config falla con NOT_IN_LOBBY; usamos otra partida en lobby:
  perform pg_temp._as_user('f7000000-0000-0000-0000-0000000000b1');
  declare r jsonb; g2 uuid; v int; begin
    r:=create_game_tx('Stock2','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1); g2:=(r->>'game_id')::uuid;
    perform pg_temp._as_admin(); select version into v from games where id=g2;
    perform pg_temp._as_user('f7000000-0000-0000-0000-0000000000b1');
    begin perform update_config(g2, jsonb_build_object('initial_houses_available',20), v); exception when others then ok1:=(sqlerrm='INVALID_BUILDING_STOCK'); end;
    begin perform update_config(g2, jsonb_build_object('initial_hotels_available',8), v); exception when others then ok2:=(sqlerrm='INVALID_BUILDING_STOCK'); end;
  end;
  perform pg_temp._as_admin(); perform pg_temp._rec('C2) no puede bajar de 32/12 (INVALID_BUILDING_STOCK)', ok1 and ok2);
end $$;

-- C3) al iniciar con stock configurado (64/24), el runtime y el snapshot lo reflejan.
do $$ declare gid uuid; code text; snap jsonb; begin
  perform pg_temp._build(64, 24, false); gid:=pg_temp._ctx('gid')::uuid; code:=pg_temp._ctx('code');
  perform pg_temp._as_user(pg_temp._ctx('host')); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  perform pg_temp._rec('C3) stock configurado 64/24 en runtime y snapshot',
    (select houses_available from public.game_runtime where game_id=gid)=64
    and (snap#>>'{building_stock,houses_available}')='64' and (snap#>>'{building_stock,hotels_available}')='24');
end $$;

-- C4) regla DESACTIVADA: sin grupo completo no se puede construir (GROUP_NOT_COMPLETE).
do $$ declare gid uuid; href text; p1u text; ok boolean:=false; begin
  perform pg_temp._build(32, 12, false); gid:=pg_temp._ctx('gid')::uuid; href:=pg_temp._ctx('host_ref'); p1u:=pg_temp._ctx('host_uid');
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-ronda-valencia',href);  -- solo 1 de 2
  perform pg_temp._as_user(p1u);
  begin perform request_build_house(gid,'cl-ronda-valencia',gen_random_uuid()); exception when others then ok:=(sqlerrm='GROUP_NOT_COMPLETE'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('C4) regla off: sin grupo completo no construye', ok);
end $$;

-- C5) regla ACTIVADA: se puede construir sin grupo completo; el snapshot expone la config y se cobra rent_1 con 1 casa.
do $$ declare gid uuid; href text; host text; p1 text; p1u text; code text; snap jsonb; res jsonb; rent int; begin
  perform pg_temp._build(32, 12, true); gid:=pg_temp._ctx('gid')::uuid; href:=pg_temp._ctx('host_ref'); host:=pg_temp._ctx('host_uid'); code:=pg_temp._ctx('code');
  insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid='f7000000-0000-0000-0000-000000000001'::uuid on conflict (k) do update set v=excluded.v;
  p1:=pg_temp._ctx('p1'); p1u:=pg_temp._ctx('p1_uid');
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-ronda-valencia',href);  -- el host posee solo 1 de 2
  update public.player_balances set balance=100000 where game_id=gid;
  res := pg_temp._bldreq(gid, host, host, 'cl-ronda-valencia');  -- construir sin grupo completo
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  -- p1 cae y paga: 1 casa → rent_1 (10) aunque el host no tenga el grupo completo
  update public.game_runtime set landing_seq=landing_seq+1 where game_id=gid;
  update public.game_runtime set last_roll = jsonb_build_object('total',7,'player_ref',p1) where game_id=gid;
  perform pg_temp._as_user(p1u); res := pay_rent(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('C5) regla on: construye sin grupo completo, snapshot expone config y cobra rent_1',
    pg_temp._gv(gid) >= 0 and (snap#>>'{game,config,allow_build_without_monopoly}')='true'
    and (snap#>>'{building_stock,houses_available}')='31' and (res->>'amount')='10');
end $$;

-- C6) regla on, sin casas y sin grupo completo: cobra BASE (no doble).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; href text:=pg_temp._ctx('host_ref'); host text:=pg_temp._ctx('host_uid'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-plaza-lavapies',href);  -- ahora el host SÍ tiene el grupo completo (monopolio)
  -- vendemos la casa de ronda para dejar el grupo sin construcciones y comprobar el doble por monopolio
  perform pg_temp._as_admin(); delete from public.game_property_state where game_id=gid and property_ref='cl-ronda-valencia';
  update public.game_runtime set houses_available=houses_available+1, landing_seq=landing_seq+1 where game_id=gid;
  perform pg_temp._as_user(p1u); res := pay_rent(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('C6) monopolio sin casas cobra doble (base 2 → 4)', (res->>'amount')='4');
end $$;

-- C7) regla ON: SIN construcción uniforme, ni siquiera con el grupo COMPLETO. celeste (classic) = 3 calles.
do $$ declare gid uuid; href text; host text; begin
  perform pg_temp._build(32, 12, true); gid:=pg_temp._ctx('gid')::uuid; href:=pg_temp._ctx('host_ref'); host:=pg_temp._ctx('host_uid');
  perform pg_temp._as_admin();
  perform pg_temp._own(gid,'cl-cuatro-caminos',href); perform pg_temp._own(gid,'cl-reina-victoria',href); perform pg_temp._own(gid,'cl-bravo-murillo',href);
  update public.player_balances set balance=100000 where game_id=gid;  -- grupo COMPLETO (monopolio) + saldo holgado
  -- Construir 3 casas en cuatro-caminos dejando las otras a 0 (desnivel total): debe permitirse con la regla ON.
  perform pg_temp._bldreq(gid, host, host, 'cl-cuatro-caminos');
  perform pg_temp._bldreq(gid, host, host, 'cl-cuatro-caminos');
  perform pg_temp._bldreq(gid, host, host, 'cl-cuatro-caminos');
  perform pg_temp._rec('C7) regla on: construcción NO uniforme con grupo completo (3-0-0)',
    pg_temp._houses(gid,'cl-cuatro-caminos')=3 and pg_temp._houses(gid,'cl-reina-victoria')=0 and pg_temp._houses(gid,'cl-bravo-murillo')=0);
end $$;

-- C8) regla ON: vender de forma NO uniforme (vender 1 casa de la que tiene 3, dejando 2-0-0) también se permite.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); begin
  perform pg_temp._bldreq(gid, host, host, 'cl-cuatro-caminos');  -- 3→4 primero (sigue sin uniformidad)
  perform pg_temp._as_user(host);
  declare rref text; begin rref := (request_sell_house(gid, 'cl-cuatro-caminos', gen_random_uuid()))->>'request_ref';
    perform resolve_building_request(rref, true, pg_temp._ver(gid)); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('C8) regla on: venta NO uniforme permitida (4→3, resto a 0)',
    pg_temp._houses(gid,'cl-cuatro-caminos')=3 and pg_temp._houses(gid,'cl-reina-victoria')=0);
end $$;

-- C9) regla OFF: la uniformidad SIGUE obligatoria (no se rompe el comportamiento estándar).
do $$ declare gid uuid; href text; host text; ok_uneven boolean:=false; begin
  perform pg_temp._build(32, 12, false); gid:=pg_temp._ctx('gid')::uuid; href:=pg_temp._ctx('host_ref'); host:=pg_temp._ctx('host_uid');
  perform pg_temp._as_admin();
  perform pg_temp._own(gid,'cl-cuatro-caminos',href); perform pg_temp._own(gid,'cl-reina-victoria',href); perform pg_temp._own(gid,'cl-bravo-murillo',href);
  update public.player_balances set balance=100000 where game_id=gid;
  perform pg_temp._bldreq(gid, host, host, 'cl-cuatro-caminos');  -- 0→1 (uniforme: todas a 0)
  begin perform pg_temp._bldreq(gid, host, host, 'cl-cuatro-caminos');  -- 1→2 con el resto a 0 → UNEVEN
    exception when others then ok_uneven:=(sqlerrm='UNEVEN_BUILDING'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('C9) regla off: uniformidad sigue obligatoria (bloquea 2-0-0)',
    ok_uneven and pg_temp._houses(gid,'cl-cuatro-caminos')=1);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
