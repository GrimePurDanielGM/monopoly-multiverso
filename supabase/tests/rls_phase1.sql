-- ============================================================================
-- Fase 1 — RLS contra SUPABASE LOCAL REAL. Ejecutar DESPUÉS de
-- integration_phase1.sql sobre la MISMA base (usa sus datos G1/G2).
--   psql "$(supabase status -o json | jq -r .DB_URL)" -v ON_ERROR_STOP=1 -f supabase/tests/rls_phase1.sql
-- Cada bloque actúa como 'authenticated' con su JWT, verifica auth.uid(), comprueba,
-- vuelve a rol privilegiado y registra. Deny-all aislados con EXCEPTION.
-- Éxito: "RESULTADO: TODOS PASAN" y exit code 0; cualquier FAIL -> exit code != 0.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t;
create temp table _t(name text primary key, ok boolean);

create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('role', 'authenticated', true);
  if auth.uid() is null then raise exception 'auth.uid() NULL tras fijar claims'; end if;
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if;
end $$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $$
begin perform set_config('role', session_user, true); end $$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $$;

do $$ begin
  perform set_config('request.jwt.claims','{"sub":"0a0a0a0a-0000-0000-0000-00000000abcd","role":"authenticated"}',true);
  perform set_config('request.jwt.claim.sub','0a0a0a0a-0000-0000-0000-00000000abcd',true);
  if auth.uid() <> '0a0a0a0a-0000-0000-0000-00000000abcd' then raise exception 'PREFLIGHT: auth.uid() no funciona (%).', auth.uid(); end if;
  raise notice 'PREFLIGHT OK: auth.uid() simulado = %', auth.uid();
end $$;

-- A,B) Miembro de G1 ve su partida (1) y solo activos (6)
do $$ declare ng int; np int; begin
  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111');
  select count(*) into ng from games; select count(*) into np from players;
  perform pg_temp._as_admin();
  perform pg_temp._rec('A) miembro ve su partida (games=1)', ng=1);
  perform pg_temp._rec('B) miembro ve solo activos (players=6)', np=6);
end $$;

-- F,G) Miembro de G2 (cc... = Ana): 2 activos, 0 expulsados
do $$ declare np int; nk int; begin
  perform pg_temp._as_user('cc000000-0000-0000-0000-0000000000c1');
  select count(*) into np from players;
  select count(*) filter (where kicked_at is not null) into nk from players;
  perform pg_temp._as_admin();
  perform pg_temp._rec('F) miembro G2 ve activos (players=2)', np=2);
  perform pg_temp._rec('G) expulsados invisibles (kicked=0)', nk=0);
end $$;

-- H,I) No-miembro ve 0
do $$ declare ng int; np int; begin
  perform pg_temp._as_user('f0000000-0000-0000-0000-0000000000ff');
  select count(*) into ng from games; select count(*) into np from players;
  perform pg_temp._as_admin();
  perform pg_temp._rec('H) no-miembro: games=0', ng=0);
  perform pg_temp._rec('I) no-miembro: players=0', np=0);
end $$;

-- C,D,E) deny-all (EXCEPTION aislada; no aborta la batería)
do $$ declare ok boolean; begin
  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111');
  ok:=false; begin perform 1 from host_recovery;   exception when insufficient_privilege then ok:=true; end;
  perform pg_temp._as_admin(); perform pg_temp._rec('C) host_recovery deny-all', ok);

  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111');
  ok:=false; begin perform 1 from audit_events;    exception when insufficient_privilege then ok:=true; end;
  perform pg_temp._as_admin(); perform pg_temp._rec('D) audit_events deny-all', ok);

  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111');
  ok:=false; begin perform 1 from request_secrets; exception when insufficient_privilege then ok:=true; end;
  perform pg_temp._as_admin(); perform pg_temp._rec('E) request_secrets deny-all', ok);
end $$;

-- J) authenticated SÍ ejecuta RPC concedidas
do $$ declare ok boolean; v_code text; gid uuid; begin
  select code,id into v_code,gid from games where create_request_id='aaaaaaaa-0000-0000-0000-000000000001';
  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111');
  ok:=true; begin perform peek_game(v_code); perform my_status(gid); exception when others then ok:=false; end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('J) authenticated ejecuta RPC concedidas (peek/my_status)', ok);
end $$;

-- K) authenticated NO puede ejecutar RPC de service_role
do $$ declare ok boolean; v_code text; begin
  select code into v_code from games where create_request_id='bbbbbbbb-0000-0000-0000-000000000002';
  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111');
  ok:=false; begin perform host_recovery_success(v_code,'11111111-1111-1111-1111-111111111111');
  exception when insufficient_privilege then ok:=true; when others then ok:=false; end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('K) host_recovery_success bloqueada a authenticated', ok);
end $$;

do $$ declare fails text; begin
  select string_agg(name,'; ') into fails from _t where not ok;
  raise notice '----------------------------------------';
  if fails is null then raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
  else raise exception 'RESULTADO: HAY FALLOS -> %', fails; end if;
end $$;
