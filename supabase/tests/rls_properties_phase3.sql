-- ============================================================================
-- Seguridad de propiedades (Fase 3): deny-all en property_catalog y property_ownership,
-- helpers revocados, acciones de host solo del host. Tras `supabase db reset`.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
drop table if exists _ctx; create temp table _ctx(k text primary key, v text);
grant select, insert, update, delete on _t, _ctx to authenticated;
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if;
end $f$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $f$
begin perform set_config('role', session_user, true); end $f$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;
create or replace function pg_temp._ctx(k text) returns text language sql as $f$ select v from _ctx where k=$1 $f$;

create or replace function pg_temp._build3() returns void language plpgsql as $f$
declare host text:='c2000000-0000-0000-0000-0000000000a1';
        u text[]:=array['c2000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002'];
        toks text[]:=array['cat','boot']; r jsonb; gid uuid; code text; v_ver int; ref text; i int;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('RLS3 IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid; code := r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v_ver);
  for i in 1..2 loop
    perform pg_temp._as_user(u[i]); perform join_game(code,'P'||i,gen_random_uuid());
    perform pg_temp._as_admin(); select public_ref into ref from players where game_id=gid and auth_uid=u[i]::uuid;
    insert into _ctx values ('p'||i, ref),('p'||i||'_uid', u[i]);
    perform pg_temp._as_user(u[i]); perform choose_token(gid, toks[i]); perform set_ready(gid,true);
  end loop;
  perform pg_temp._as_user(host); perform choose_token(gid,'thimble'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid, v_ver);
  perform pg_temp._as_admin();
end $f$;

do $$ begin perform pg_temp._build3(); end $$;

-- S1) property_catalog: SELECT directo como authenticated -> denegado (deny-all).
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user(pg_temp._ctx('host'));
  begin perform 1 from public.property_catalog limit 1; exception when others then ok := (sqlstate='42501'); end; -- insufficient_privilege
  perform pg_temp._as_admin();
  perform pg_temp._rec('S1) property_catalog deny-all (SELECT directo denegado)', ok);
end $$;

-- S2) property_ownership: SELECT directo como authenticated -> denegado.
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user(pg_temp._ctx('host'));
  begin perform 1 from public.property_ownership limit 1; exception when others then ok := (sqlstate='42501'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('S2) property_ownership deny-all (SELECT directo denegado)', ok);
end $$;

-- S3) INSERT directo en property_ownership como authenticated -> denegado (no inventar posesión).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; ok boolean:=false; begin
  perform pg_temp._as_user(pg_temp._ctx('p1_uid'));
  begin insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,'cl-marron-1',pg_temp._ctx('p1'));
    exception when others then ok := (sqlstate='42501'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('S3) no se puede inventar posesión por INSERT directo', ok);
end $$;

-- S4) helper interno _p2_remove_player NO concedido a authenticated.
do $$ declare h boolean; begin
  perform pg_temp._as_admin();
  h := has_function_privilege('authenticated','public._p2_remove_player(uuid,public.players,text,text,text)','execute');
  perform pg_temp._rec('S4) helper _p2_remove_player no ejecutable por authenticated', h = false);
end $$;

-- S5) buy_property y pay_rent SÍ concedidas a authenticated (RPC pública controlada).
do $$ declare b boolean; p boolean; begin
  perform pg_temp._as_admin();
  b := has_function_privilege('authenticated','public.buy_property(uuid,text,uuid,bigint)','execute');
  p := has_function_privilege('authenticated','public.pay_rent(uuid,text,uuid,bigint)','execute');
  perform pg_temp._rec('S5) buy_property y pay_rent ejecutables por authenticated', b and p);
end $$;

-- S6) acciones de host: un jugador normal no puede expulsar (NOT_HOST).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._ctx('p1_uid'));
  begin perform remove_active_player(gid, pg_temp._ctx('p2'), 'to_bank', 'x', gen_random_uuid(), v_ver);
    exception when others then ok := (sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('S6) un no-host no puede expulsar (acción de host) -> NOT_HOST', ok);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── rls_properties_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
