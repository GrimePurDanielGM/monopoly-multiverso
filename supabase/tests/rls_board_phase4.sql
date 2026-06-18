-- ============================================================================
-- RLS y saneado (Fase 4): board_spaces y player_positions son deny-all para authenticated;
-- el snapshot no expone ids internos. Tras `supabase db reset`.
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

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='dc000000-0000-0000-0000-0000000000d1'; j1 text:='dc000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Rls IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- R1) board_spaces: deny-all para authenticated (SELECT directo prohibido).
do $$ declare host text:=pg_temp._ctx('host'); ok boolean:=false; n int; begin
  perform pg_temp._as_user(host);
  begin select count(*) into n from public.board_spaces; exception when insufficient_privilege then ok:=true; when others then ok:=false; end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R1) board_spaces deny-all (sin SELECT directo)', ok);
end $$;

-- R2) player_positions: deny-all para authenticated (SELECT directo prohibido).
do $$ declare host text:=pg_temp._ctx('host'); ok boolean:=false; n int; begin
  perform pg_temp._as_user(host);
  begin select count(*) into n from public.player_positions; exception when insufficient_privilege then ok:=true; when others then ok:=false; end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R2) player_positions deny-all (sin SELECT directo)', ok);
end $$;

-- R3) el snapshot expone tablero/posiciones SIN ids internos (no 'id', no 'auth_uid', no 'game_id').
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); snap jsonb; blob text; begin
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  blob := snap::text;
  perform pg_temp._rec('R3) snapshot con boards/spaces/positions/my_position/current_space',
    snap ? 'boards' and snap ? 'spaces' and snap ? 'positions' and snap ? 'my_position' and snap ? 'current_space'
    and snap ? 'last_roll' and snap ? 'last_move');
  perform pg_temp._rec('R3b) snapshot saneado (sin auth_uid/game_id/"id" ni uuid de partida)',
    blob not like '%auth_uid%' and blob not like '%game_id%' and blob not like '%"id"%' and position(gid::text in blob)=0);
end $$;

-- R4) las casillas del snapshot referencian property_ref del catálogo (sin ids internos de casilla).
do $$ declare host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); snap jsonb; bad int; begin
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  select count(*) into bad from jsonb_array_elements(snap->'spaces') s
    where (s->>'space_type')='property'
      and not exists(select 1 from public.property_catalog c where c.property_ref = s->>'property_ref');
  perform pg_temp._rec('R4) casillas de propiedad del snapshot apuntan a property_ref real', bad=0);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── rls_board_phase4: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
