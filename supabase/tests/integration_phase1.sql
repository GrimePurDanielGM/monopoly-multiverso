-- ============================================================================
-- Fase 1 — Integración contra SUPABASE LOCAL REAL.
-- Cada escenario ACTÚA COMO 'authenticated' con su propio JWT (request.jwt.claims),
-- igual que en producción (las RPC se invocan con el rol del usuario). Las lecturas
-- y aserciones internas del test se hacen como rol privilegiado (postgres) para no
-- chocar con RLS. Ejecutar tras `supabase db reset`.
--   psql "$(supabase status -o json | jq -r .DB_URL)" -v ON_ERROR_STOP=1 -f supabase/tests/integration_phase1.sql
-- Éxito: "RESULTADO: TODOS PASAN" y exit code 0. Cualquier FAIL -> exit code != 0.
-- ============================================================================
\set ON_ERROR_STOP on

drop table if exists _t;
create temp table _t(name text primary key, ok boolean);

create or replace function pg_temp._g1() returns uuid language sql as
  $$ select id from public.games where create_request_id='aaaaaaaa-0000-0000-0000-000000000001' $$;
create or replace function pg_temp._g2() returns uuid language sql as
  $$ select id from public.games where create_request_id='bbbbbbbb-0000-0000-0000-000000000002' $$;

-- Actúa como un usuario autenticado concreto (rol + claims) y VERIFICA auth.uid().
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);            -- compat versiones antiguas
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('role', 'authenticated', true);
  if auth.uid() is null then raise exception 'auth.uid() NULL tras fijar claims (mecanismo JWT no funciona)'; end if;
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if;
end $$;
-- Vuelve al rol privilegiado de la sesión (para lecturas/aserciones del test).
create or replace function pg_temp._as_admin() returns void language plpgsql as $$
begin perform set_config('role', session_user, true); end $$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $$;

-- ===== PREFLIGHT: aborta de inmediato si el mecanismo JWT no funciona aquí =====
do $$ begin
  perform set_config('request.jwt.claims','{"sub":"0a0a0a0a-0000-0000-0000-00000000abcd","role":"authenticated"}',true);
  perform set_config('request.jwt.claim.sub','0a0a0a0a-0000-0000-0000-00000000abcd',true);
  if auth.uid() is null then raise exception 'PREFLIGHT: auth.uid()=NULL. El JWT no se aplica en este Supabase; revisa la definición de auth.uid().'; end if;
  if auth.uid() <> '0a0a0a0a-0000-0000-0000-00000000abcd' then raise exception 'PREFLIGHT: auth.uid()=% inesperado', auth.uid(); end if;
  raise notice 'PREFLIGHT OK: auth.uid() simulado = %', auth.uid();
end $$;

-- 1) creación + auth.uid correcto (RPC como authenticated)
do $$ begin
  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111');
  perform create_game_tx('Partida de Daniel','Daniel','delorean','{}','aaaaaaaa-0000-0000-0000-000000000001','HASH','SALT','PBKDF2-SHA256',600000);
  perform pg_temp._as_admin();
  perform pg_temp._rec('1) auth.uid simulado + partida creada (como authenticated)', pg_temp._g1() is not null);
end $$;

-- 2) creación idempotente
do $$ declare a text; b text; begin
  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111');
  a := (create_game_tx('x','Daniel','delorean','{}','aaaaaaaa-0000-0000-0000-000000000001','H','S','A',1)->>'code');
  perform pg_temp._as_admin();
  select code into b from games where id=pg_temp._g1();
  perform pg_temp._rec('2) create idempotente', a=b);
end $$;

-- 3) 6 jugadores: unión + ficha + ready (cada uno con su JWT)
do $$ declare uids text[]:=array['22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444','55555555-5555-5555-5555-555555555555','66666666-6666-6666-6666-666666666666'];
  names text[]:=array['Marty','Doc','Biff','Jennifer','Lorraine']; toks text[]:=array['hoverboard','einstein_dog','self_lacing_shoe','clock_tower','cowboy_hat'];
  v_code text; gid uuid; i int; n int; begin
  gid:=pg_temp._g1(); select code into v_code from games where id=gid;   -- lookup privilegiado
  for i in 1..5 loop
    perform pg_temp._as_user(uids[i]);
    perform join_game(v_code,names[i],gen_random_uuid());
    perform choose_token(gid,toks[i]);
    perform set_ready(gid,true);
  end loop;
  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111'); perform set_ready(gid,true);
  perform pg_temp._as_admin();
  select count(*) into n from players where game_id=gid and kicked_at is null and join_status='ready' and token_id is not null;
  perform pg_temp._rec('3) 6 jugadores con ficha y preparados', n=6);
end $$;

-- 4) peek_game sin uid (RPC como authenticated)
do $$ declare j jsonb; v_code text; begin
  select code into v_code from games where id=pg_temp._g1();
  perform pg_temp._as_user('22222222-2222-2222-2222-222222222222');
  j := peek_game(v_code);
  perform pg_temp._as_admin();
  perform pg_temp._rec('4) peek sin uid y 6 jugadores', j::text not ilike '%uid%' and (j->>'player_count')='6');
end $$;

-- 5) colisión de ficha
do $$ declare ok boolean:=false; gid uuid; begin
  gid:=pg_temp._g1();
  perform pg_temp._as_user('22222222-2222-2222-2222-222222222222');
  begin perform choose_token(gid,'einstein_dog'); exception when others then ok := (sqlerrm='TOKEN_TAKEN'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('5) colisión de ficha (TOKEN_TAKEN)', ok);
end $$;

-- 6) colisión de nombre
do $$ declare ok boolean:=false; v_code text; begin
  select code into v_code from games where id=pg_temp._g1();
  perform pg_temp._as_user('99999999-0000-0000-0000-000000000099');
  begin perform join_game(v_code,'  DANIEL ',gen_random_uuid()); exception when others then ok := (sqlerrm='NAME_TAKEN'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('6) colisión de nombre (NAME_TAKEN)', ok);
end $$;

-- 7) start idempotente con orden fijo
do $$ declare gid uuid; v1 jsonb; v2 jsonb; v int; begin
  gid:=pg_temp._g1(); select version into v from games where id=gid;
  perform pg_temp._as_user('11111111-1111-1111-1111-111111111111');
  v1 := start_game(gid,v);
  v2 := start_game(gid,999);
  perform pg_temp._as_admin();
  perform pg_temp._rec('7) start idempotente (mismo orden)', (v1->'turn_order')=(v2->'turn_order') and (v2->>'idempotent')='true');
end $$;

-- 7b) start con <6 bloqueado
do $$ declare gid uuid; ok boolean:=false; v int; begin
  perform pg_temp._as_user('dd000000-0000-0000-0000-0000000000d1');
  perform create_game_tx('Partida Tres','Tres','delorean','{}','cccccccc-0000-0000-0000-000000000003','H','S','A',1);
  perform pg_temp._as_admin();
  select id,version into gid,v from games where create_request_id='cccccccc-0000-0000-0000-000000000003';
  perform pg_temp._as_user('dd000000-0000-0000-0000-0000000000d1');
  perform choose_token(gid,'delorean'); perform set_ready(gid,true);
  -- 0008: el cliente ya NO lee games directo; usamos la version capturada como admin
  -- (choose_token/set_ready no alteran games.version).
  begin perform start_game(gid, v); exception when others then ok := (sqlerrm='NOT_ENOUGH_PLAYERS'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('7b) start con <6 bloqueado (NOT_ENOUGH_PLAYERS)', ok);
end $$;

-- 8) expulsión con fila histórica
do $$ declare gid uuid; v_code text; pref text; begin
  perform pg_temp._as_user('aa000000-0000-0000-0000-0000000000a1');
  perform create_game_tx('Partida Dos','Ana','delorean','{}','bbbbbbbb-0000-0000-0000-000000000002','H','S','A',1);
  perform pg_temp._as_admin(); gid:=pg_temp._g2(); select code into v_code from games where id=gid;
  perform pg_temp._as_user('bb000000-0000-0000-0000-0000000000b1'); perform join_game(v_code,'Pedro',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into pref from players where game_id=gid and display_name='Pedro' and kicked_at is null;
  perform pg_temp._as_user('aa000000-0000-0000-0000-0000000000a1'); perform kick_player(gid,pref);
  perform pg_temp._as_admin();
  perform pg_temp._rec('8) expulsión (fila histórica conservada)',
    (select count(*) from players where game_id=gid and display_name='Pedro' and kicked_at is not null)=1);
end $$;

-- 9) join de expulsado -> reentrada
do $$ declare v_code text; ok boolean:=false; begin
  select code into v_code from games where id=pg_temp._g2();
  perform pg_temp._as_user('bb000000-0000-0000-0000-0000000000b1');
  begin perform join_game(v_code,'Pedro',gen_random_uuid()); exception when others then ok := (sqlerrm='KICKED_NEEDS_REENTRY'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('9) join de expulsado redirige a reentrada', ok);
end $$;

-- 10) reentrada = fila nueva + histórica intacta
do $$ declare gid uuid; v_code text; rref text; total int; kicked int; begin
  gid:=pg_temp._g2(); select code into v_code from games where id=gid;
  perform pg_temp._as_user('bb000000-0000-0000-0000-0000000000b1');
  rref := (request_reentry(v_code,'Pedro2','iPhone')->>'request_ref');
  perform pg_temp._as_user('aa000000-0000-0000-0000-0000000000a1'); perform resolve_reentry(rref,true);
  perform pg_temp._as_admin();
  select count(*) into total from players where game_id=gid and auth_uid='bb000000-0000-0000-0000-0000000000b1';
  select count(*) into kicked from players where game_id=gid and auth_uid='bb000000-0000-0000-0000-0000000000b1' and kicked_at is not null;
  perform pg_temp._rec('10) reentrada crea fila nueva (2 filas, 1 kicked)', total=2 and kicked=1);
end $$;

-- 11) recuperación de identidad
do $$ declare gid uuid; v_code text; pref text; rref text; new_uid uuid; begin
  gid:=pg_temp._g2(); select code into v_code from games where id=gid;
  select public_ref into pref from players where game_id=gid and display_name='Ana' and kicked_at is null;
  perform pg_temp._as_user('cc000000-0000-0000-0000-0000000000c1');
  rref := (request_recovery(v_code,pref,'Android')->>'request_ref');
  perform pg_temp._as_user('aa000000-0000-0000-0000-0000000000a1'); perform resolve_recovery(rref,true);
  perform pg_temp._as_admin();
  select auth_uid into new_uid from players where public_ref=pref;
  perform pg_temp._rec('11) recuperación reasigna auth_uid', new_uid='cc000000-0000-0000-0000-0000000000c1');
end $$;

-- 12) conflicto de sesión
do $$ declare v_code text; pref text; ok boolean:=false; begin
  select code into v_code from games where id=pg_temp._g2();
  select public_ref into pref from players where game_id=pg_temp._g2() and display_name='Pedro2' and kicked_at is null;
  perform pg_temp._as_user('cc000000-0000-0000-0000-0000000000c1');
  begin perform request_recovery(v_code,pref,'x'); exception when others then ok := (sqlerrm='SESSION_HAS_ACTIVE_PLAYER'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('12) conflicto de sesión (SESSION_HAS_ACTIVE_PLAYER)', ok);
end $$;

-- 13) audit_seq monotónico
do $$ declare gid uuid; n int; mx bigint; begin
  gid:=pg_temp._g2(); select count(*),max(seq) into n,mx from audit_events where game_id=gid;
  perform pg_temp._rec('13) audit_seq monotónico (n=max)', n=mx and n>0);
end $$;

do $$ declare fails text; begin
  select string_agg(name,'; ') into fails from _t where not ok;
  raise notice '----------------------------------------';
  if fails is null then raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
  else raise exception 'RESULTADO: HAY FALLOS -> %', fails; end if;
end $$;
