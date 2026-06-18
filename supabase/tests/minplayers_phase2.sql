-- ============================================================================
-- Mínimo de jugadores configurable a 2 (Fase 2). Tras `supabase db reset`.
-- Demuestra: configurar min_players=2; iniciar con 2 preparados; NO iniciar con 1;
-- y que min_players=1 es inválido (el suelo del backend es 2). El default sigue siendo 6.
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

-- ── Partida G1: configurar min=2 e iniciar con 2 jugadores preparados ────────────
do $$
declare host text:='c0000000-0000-0000-0000-0000000000a1'; j1 text:='c0000000-0000-0000-0000-000000000001';
        r jsonb; gid uuid; code text; v_ver int; v_min int; ok_cfg boolean; ok_start boolean;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Min2 IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid; code := r->>'code';
  insert into _ctx values ('g1',gid::text),('g1code',code);

  -- min=2 configurable
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host);
  perform update_config(gid, jsonb_build_object('min_players',2), v_ver);
  perform pg_temp._as_admin();
  select coalesce((config->>'min_players')::int,6) into v_min from games where id=gid;
  ok_cfg := (v_min = 2);

  -- segundo jugador entra, ambos con ficha y preparados
  perform pg_temp._as_user(j1); perform join_game(code, 'P1', gen_random_uuid());
  perform choose_token(gid, 'cat'); perform set_ready(gid, true);
  perform pg_temp._as_user(host); perform choose_token(gid, 'boot'); perform set_ready(gid, true);

  -- iniciar con 2
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid, v_ver);
  perform pg_temp._as_admin();
  select (status='active') into ok_start from games where id=gid;

  perform pg_temp._rec('M1) min_players configurable a 2', ok_cfg);
  perform pg_temp._rec('M2) se inicia con 2 jugadores preparados', ok_start);
end $$;

-- ── Partida G2: con min=2 pero un solo jugador (el host) -> NOT_ENOUGH_PLAYERS ────
do $$
declare host text:='c0000000-0000-0000-0000-0000000000a2'; r jsonb; gid uuid; v_ver int; ok boolean:=false;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Solo IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid;
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host);
  perform update_config(gid, jsonb_build_object('min_players',2), v_ver);
  perform choose_token(gid, 'cat'); perform set_ready(gid, true);
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host);
  begin perform start_game(gid, v_ver); exception when others then ok := (sqlerrm='NOT_ENOUGH_PLAYERS'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('M3) NO se inicia con 1 jugador -> NOT_ENOUGH_PLAYERS', ok);
end $$;

-- ── min_players=1 es inválido (suelo 2) ─────────────────────────────────────────
do $$
declare host text:='c0000000-0000-0000-0000-0000000000a3'; r jsonb; gid uuid; v_ver int; ok boolean:=false;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Uno IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid;
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host);
  begin perform update_config(gid, jsonb_build_object('min_players',1), v_ver);
  exception when others then ok := (sqlerrm='INVALID_PLAYER_LIMITS'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('M4) min_players=1 es inválido -> INVALID_PLAYER_LIMITS', ok);
end $$;

-- ── Resumen ──────────────────────────────────────────────────────────────────────
do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── minplayers_phase2: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
