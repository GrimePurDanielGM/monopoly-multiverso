-- ============================================================================
-- Fase 1 — Sustitución del catálogo de fichas (0011). Ejecutar tras `supabase db reset`.
--   psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/tokens_phase1.sql
-- Verifica: 7 antiguas inactivas pero existentes; 7 nuevas activas; 20 activas v0; >=16;
-- FK histórica intacta (una antigua puede seguir asignada); el set activo excluye antiguas;
-- crear acepta nueva y no ofrece antigua; cambiar a nueva OK; cambiar a antigua -> TOKEN_INVALID.
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

-- Conjuntos
create or replace function pg_temp._old() returns text[] language sql immutable as
  $$ select array['flux_capacitor','plutonium_case','sports_almanac','time_train','guitar','mr_fusion','battleship'] $$;
create or replace function pg_temp._new() returns text[] language sql immutable as
  $$ select array['penguin','t_rex','rider','spinning_wheel','iron','peter_mayday','babypool'] $$;

-- 1) Las 7 antiguas EXISTEN pero quedan inactivas
do $$ declare n_exist int; n_inactive int; begin
  select count(*) into n_exist    from token_catalog where id = any(pg_temp._old());
  select count(*) into n_inactive from token_catalog where id = any(pg_temp._old()) and active = false;
  perform pg_temp._rec('1) 7 antiguas existen y están inactivas', n_exist=7 and n_inactive=7);
end $$;

-- 2) Las 7 nuevas existen y están activas (v0)
do $$ declare n int; begin
  select count(*) into n from token_catalog where id = any(pg_temp._new()) and active and catalog_version=0;
  perform pg_temp._rec('2) 7 nuevas activas (v0)', n=7);
end $$;

-- 3) y 4) Exactamente 20 activas v0 (>=16)
do $$ declare n int; begin
  select count(*) into n from token_catalog where active and catalog_version=0;
  perform pg_temp._rec('3) exactamente 20 activas v0', n=20);
  perform pg_temp._rec('4) al menos 16 activas', n>=16);
end $$;

-- 6) El set activo incluye nuevas y excluye antiguas (equivalente a listActiveTokens)
do $$ declare ids text[]; begin
  select array_agg(id) into ids from token_catalog where active and catalog_version=0;
  perform pg_temp._rec('6) set activo incluye nuevas y excluye antiguas',
    ('penguin' = any(ids)) and ('t_rex' = any(ids)) and not ('flux_capacitor' = any(ids)) and not ('battleship' = any(ids)));
end $$;

-- 7) Crear partida acepta una ficha nueva; 9/10) cambiar a nueva OK, a antigua -> TOKEN_INVALID; 8) peek no ofrece antigua
do $$ declare gid uuid; v_code text; ok9 boolean:=false; ok10 boolean:=false; j jsonb; begin
  perform pg_temp._as_user('f1f1f1f1-0000-0000-0000-0000000000f1');
  perform create_game_tx('Tokens A','HostA','penguin','{}','ffffffff-0000-0000-0000-0000000000f1','H','S','A',1);  -- ficha nueva
  perform pg_temp._as_admin(); select id,code into gid,v_code from games where create_request_id='ffffffff-0000-0000-0000-0000000000f1';
  perform pg_temp._rec('7) crear partida acepta ficha nueva (penguin)', gid is not null);

  perform pg_temp._as_user('f2f2f2f2-0000-0000-0000-0000000000f2');
  perform join_game(v_code,'Jot',gen_random_uuid());
  begin perform choose_token(gid,'t_rex'); ok9:=true; exception when others then ok9:=false; end;          -- nueva
  begin perform choose_token(gid,'flux_capacitor'); exception when others then ok10:=(sqlerrm='TOKEN_INVALID'); end;  -- antigua
  perform pg_temp._as_user('f1f1f1f1-0000-0000-0000-0000000000f1'); j := peek_game(v_code);                 -- peek como miembro
  perform pg_temp._as_admin();
  perform pg_temp._rec('9) cambiar a ficha nueva permitido (t_rex)', ok9);
  perform pg_temp._rec('10) cambiar a ficha antigua -> TOKEN_INVALID', ok10);
  perform pg_temp._rec('8) peek no ofrece antiguas e incluye nuevas',
    (j->'available_tokens')::text not like '%flux_capacitor%' and (j->'available_tokens')::text like '%rider%');
end $$;

-- 5) FK histórica intacta: una ficha ANTIGUA (inactiva) puede seguir ASIGNADA (la fila existe).
--    Tras 0012 ya no se puede CREAR con una ficha inactiva, así que simulamos una asignación
--    histórica con un UPDATE admin (la FK sigue válida porque la fila antigua no se borró).
do $$ declare gid uuid; v_tok text; begin
  perform pg_temp._as_user('f3f3f3f3-0000-0000-0000-0000000000f3');
  perform create_game_tx('Tokens B','HostB','penguin','{}','ffffffff-0000-0000-0000-0000000000f2','H','S','A',1); -- ficha válida (0012)
  perform pg_temp._as_admin();
  select id into gid from games where create_request_id='ffffffff-0000-0000-0000-0000000000f2';
  update players set token_id='flux_capacitor' where game_id=gid and auth_uid='f3f3f3f3-0000-0000-0000-0000000000f3'; -- histórica (FK ok)
  select token_id into v_tok from players where game_id=gid and auth_uid='f3f3f3f3-0000-0000-0000-0000000000f3';
  perform pg_temp._rec('5) FK histórica: ficha antigua (inactiva) sigue asignable', v_tok='flux_capacitor');
end $$;

do $$ declare fails text; begin
  select string_agg(name,'; ') into fails from _t where not ok;
  raise notice '----------------------------------------';
  if fails is null then raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
  else raise exception 'RESULTADO: HAY FALLOS -> %', fails; end if;
end $$;
