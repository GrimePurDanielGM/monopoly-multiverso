-- ============================================================================
-- Fase 1 — Validación de host_token en create_game_tx (0012). Tras `supabase db reset`.
--   psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/host_token_phase1.sql
-- Demuestra: host_token obligatorio/activo/version-vigente; idempotencia; atomicidad;
-- ficha asignada al host; ninguna partida nueva queda sin ficha.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t;
create temp table _t(name text primary key, ok boolean);
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if;
end $$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $$
begin perform set_config('role', session_user, true); end $$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $$;

-- Ficha activa de OTRA versión (para el caso 5). No afecta a la v0.
insert into public.token_catalog(id,label,icon,catalog_version,provisional,active,sort_order)
values ('__v1test','V1 test','v1',1,true,true,99) on conflict (id) do nothing;

-- 1) host_token = null -> TOKEN_REQUIRED ; 8) atómico (no crea partida) ; 11)
do $$ declare ok boolean:=false; n0 int; n1 int; begin
  perform pg_temp._as_admin(); select count(*) into n0 from games;
  perform pg_temp._as_user('a0000000-0000-0000-0000-0000000000a1');
  begin perform create_game_tx('Caso Null','Host',null,'{}','11110000-0000-0000-0000-000000000001','H','S','A',1);
  exception when others then ok := (sqlerrm='TOKEN_REQUIRED'); end;
  perform pg_temp._as_admin(); select count(*) into n1 from games;
  perform pg_temp._rec('1) host_token null -> TOKEN_REQUIRED', ok);
  perform pg_temp._rec('8) atomico: fallo no crea partida', n1=n0);
end $$;

-- 2) host_token = '' -> TOKEN_REQUIRED
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user('a0000000-0000-0000-0000-0000000000a2');
  begin perform create_game_tx('Caso Vacio','Host','   ','{}','11110000-0000-0000-0000-000000000002','H','S','A',1);
  exception when others then ok := (sqlerrm='TOKEN_REQUIRED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('2) host_token vacio -> TOKEN_REQUIRED', ok);
end $$;

-- 3) ID inexistente -> TOKEN_INVALID
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user('a0000000-0000-0000-0000-0000000000a3');
  begin perform create_game_tx('Caso Inexist','Host','ficha_fantasma','{}','11110000-0000-0000-0000-000000000003','H','S','A',1);
  exception when others then ok := (sqlerrm='TOKEN_INVALID'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('3) ficha inexistente -> TOKEN_INVALID', ok);
end $$;

-- 4) Ficha existente pero INACTIVA -> TOKEN_INVALID
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user('a0000000-0000-0000-0000-0000000000a4');
  begin perform create_game_tx('Caso Inact','Host','flux_capacitor','{}','11110000-0000-0000-0000-000000000004','H','S','A',1);
  exception when others then ok := (sqlerrm='TOKEN_INVALID'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('4) ficha inactiva -> TOKEN_INVALID', ok);
end $$;

-- 5) Ficha activa de versión INCORRECTA -> TOKEN_INVALID (el servidor fuerza v0)
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user('a0000000-0000-0000-0000-0000000000a5');
  begin perform create_game_tx('Caso V1','Host','__v1test','{"token_catalog_version":1}','11110000-0000-0000-0000-000000000005','H','S','A',1);
  exception when others then ok := (sqlerrm='TOKEN_INVALID'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('5) ficha activa de version incorrecta -> TOKEN_INVALID', ok);
end $$;

-- 6) Ficha activa v0 -> creación correcta ; 9) ficha asignada al host ; 10) host nunca sin ficha
do $$ declare gid uuid; v_tok text; v_ver int; begin
  perform pg_temp._as_user('a0000000-0000-0000-0000-0000000000a6');
  perform create_game_tx('Caso OK','Host','penguin','{}','11110000-0000-0000-0000-000000000006','H','S','A',1);
  perform pg_temp._as_admin();
  select id, (config->>'token_catalog_version')::int into gid, v_ver from games where create_request_id='11110000-0000-0000-0000-000000000006';
  select token_id into v_tok from players where game_id=gid and auth_uid='a0000000-0000-0000-0000-0000000000a6';
  perform pg_temp._rec('6) ficha activa v0 -> creacion correcta', gid is not null);
  perform pg_temp._rec('9) ficha asignada al host (penguin)', v_tok='penguin');
  perform pg_temp._rec('10) host nunca sin ficha (token_id no nulo)', v_tok is not null);
  -- versión de catálogo forzada por servidor a 0 (aunque se intente otra cosa más arriba)
  perform pg_temp._rec('5b) token_catalog_version forzada a 0 por servidor', v_ver=0);
end $$;

-- 7) Reintento con el MISMO request_id sigue idempotente (incluso con token null)
do $$ declare j jsonb; ok boolean:=false; begin
  perform pg_temp._as_user('a0000000-0000-0000-0000-0000000000a6');
  begin j := create_game_tx('Caso OK','Host',null,'{}','11110000-0000-0000-0000-000000000006','H','S','A',1);
         ok := (j->>'idempotent')='true';
  exception when others then ok:=false; end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('7) reintento mismo request_id es idempotente', ok);
end $$;

do $$ declare fails text; begin
  select string_agg(name,'; ') into fails from _t where not ok;
  raise notice '----------------------------------------';
  if fails is null then raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
  else raise exception 'RESULTADO: HAY FALLOS -> %', fails; end if;
end $$;
