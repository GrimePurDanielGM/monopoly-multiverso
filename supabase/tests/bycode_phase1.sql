-- ============================================================================
-- Fase 1 — get_lobby_snapshot_by_code (0010). Ejecutar tras `supabase db reset`.
--   psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/bycode_phase1.sql
-- Cubre: code válido+miembro, minúsculas/espacios, inexistente, no-miembro,
-- expulsado, equivalencia con get_lobby_snapshot(id), sin claves internas, grants.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t;
create temp table _t(name text primary key, ok boolean);

create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  perform set_config('role', 'authenticated', true);
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if;
end $$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $$
begin perform set_config('role', session_user, true); end $$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $$;

-- ===================== FIXTURE: game BC (host + activo + expulsado) =====================
do $$ declare gid uuid; v_code text; pref text; begin
  perform pg_temp._as_user('c1c1c1c1-0000-0000-0000-0000000000c1');
  perform create_game_tx('Sala ByCode','Host','delorean','{}','cccccccc-0000-0000-0000-000000000010','H','S','A',1);
  perform pg_temp._as_admin(); select id,code into gid,v_code from games where create_request_id='cccccccc-0000-0000-0000-000000000010';
  perform pg_temp._as_user('c2c2c2c2-0000-0000-0000-0000000000c2');
  perform join_game(v_code,'Marty',gen_random_uuid()); perform choose_token(gid,'hoverboard'); perform set_ready(gid,true);
  perform pg_temp._as_user('c3c3c3c3-0000-0000-0000-0000000000c3');
  perform join_game(v_code,'Biff',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into pref from players where game_id=gid and display_name='Biff' and kicked_at is null;
  perform pg_temp._as_user('c1c1c1c1-0000-0000-0000-0000000000c1'); perform kick_player(gid,pref);
  perform pg_temp._as_admin();
end $$;

-- 1) código válido + miembro activo (host) -> snapshot correcto
do $$ declare gid uuid; v_code text; snap jsonb; begin
  select id,code into gid,v_code from games where create_request_id='cccccccc-0000-0000-0000-000000000010';
  perform pg_temp._as_user('c1c1c1c1-0000-0000-0000-0000000000c1');
  snap := get_lobby_snapshot_by_code(v_code);
  perform pg_temp._as_admin();
  perform pg_temp._rec('1) by_code válido+miembro -> snapshot (2 activos, is_host)',
    jsonb_array_length(snap->'players')=2 and (snap->'me'->>'is_host')='true' and (snap->'game'->>'code')=v_code);
end $$;

-- 2) minúsculas + espacios -> funciona igual
do $$ declare gid uuid; v_code text; s1 jsonb; s2 jsonb; begin
  select id,code into gid,v_code from games where create_request_id='cccccccc-0000-0000-0000-000000000010';
  perform pg_temp._as_user('c1c1c1c1-0000-0000-0000-0000000000c1');
  s1 := get_lobby_snapshot_by_code(v_code);
  s2 := get_lobby_snapshot_by_code('  ' || lower(v_code) || '  ');
  perform pg_temp._as_admin();
  perform pg_temp._rec('2) minúsculas+espacios equivalen', s1 = s2);
end $$;

-- 3) código inexistente -> GAME_NOT_FOUND
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user('c1c1c1c1-0000-0000-0000-0000000000c1');
  begin perform get_lobby_snapshot_by_code('ZZZZZZ'); exception when others then ok := (sqlerrm='GAME_NOT_FOUND'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('3) código inexistente -> GAME_NOT_FOUND', ok);
end $$;

-- 4) válido + no-miembro -> NOT_ACTIVE_MEMBER
do $$ declare v_code text; ok boolean:=false; begin
  select code into v_code from games where create_request_id='cccccccc-0000-0000-0000-000000000010';
  perform pg_temp._as_user('f0000000-0000-0000-0000-0000000000ff');
  begin perform get_lobby_snapshot_by_code(v_code); exception when others then ok := (sqlerrm='NOT_ACTIVE_MEMBER'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('4) no-miembro -> NOT_ACTIVE_MEMBER', ok);
end $$;

-- 5) jugador expulsado -> NOT_ACTIVE_MEMBER
do $$ declare v_code text; ok boolean:=false; begin
  select code into v_code from games where create_request_id='cccccccc-0000-0000-0000-000000000010';
  perform pg_temp._as_user('c3c3c3c3-0000-0000-0000-0000000000c3');
  begin perform get_lobby_snapshot_by_code(v_code); exception when others then ok := (sqlerrm='NOT_ACTIVE_MEMBER'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('5) expulsado -> NOT_ACTIVE_MEMBER', ok);
end $$;

-- 6) equivalencia by_code(code) == get_lobby_snapshot(id) para el mismo caller
do $$ declare gid uuid; v_code text; sa jsonb; sb jsonb; begin
  select id,code into gid,v_code from games where create_request_id='cccccccc-0000-0000-0000-000000000010';
  perform pg_temp._as_user('c1c1c1c1-0000-0000-0000-0000000000c1');
  sa := get_lobby_snapshot_by_code(v_code);
  sb := get_lobby_snapshot(gid);
  perform pg_temp._as_admin();
  perform pg_temp._rec('6) by_code == get_lobby_snapshot(id)', sa = sb);
end $$;

-- 7) sin claves internas prohibidas
do $$ declare v_code text; snap jsonb; begin
  select code into v_code from games where create_request_id='cccccccc-0000-0000-0000-000000000010';
  perform pg_temp._as_user('c1c1c1c1-0000-0000-0000-0000000000c1');
  snap := get_lobby_snapshot_by_code(v_code);
  perform pg_temp._as_admin();
  perform pg_temp._rec('7) JSON sin clave auth_uid', snap::text not ilike '%auth_uid%');
end $$;

-- 8/9) grants: authenticated SÍ, anon NO, helper interno NO concedido
do $$ declare a boolean; n boolean; h boolean; begin
  a := has_function_privilege('authenticated','public.get_lobby_snapshot_by_code(text)','execute');
  n := has_function_privilege('anon','public.get_lobby_snapshot_by_code(text)','execute');
  h := has_function_privilege('authenticated','public._lobby_snapshot(uuid,uuid)','execute');
  perform pg_temp._rec('8) authenticated puede ejecutar by_code', a = true);
  perform pg_temp._rec('9) anon NO puede ejecutar by_code', n = false);
  perform pg_temp._rec('9b) helper _lobby_snapshot NO concedido a authenticated', h = false);
end $$;

do $$ declare fails text; begin
  select string_agg(name,'; ') into fails from _t where not ok;
  raise notice '----------------------------------------';
  if fails is null then raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
  else raise exception 'RESULTADO: HAY FALLOS -> %', fails; end if;
end $$;
