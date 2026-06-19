-- ============================================================================
-- Movimiento (Fase 4): posiciones iniciales, mover manual, dados, límites, permisos,
-- pausa/finalización, caer en propiedad. Host + 2 jugadores. Tras `supabase db reset`.
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
create or replace function pg_temp._cur(gid uuid) returns text language sql security definer as $f$ select turn_order_refs[turn_index] from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._uid(gid uuid, ref text) returns text language sql security definer as $f$ select auth_uid::text from public.players where game_id=gid and public_ref=ref $f$;
create or replace function pg_temp._pos(gid uuid, ref text) returns int language sql security definer as $f$ select space_index from public.player_positions where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._board(gid uuid, ref text) returns text language sql security definer as $f$ select board_key from public.player_positions where game_id=gid and player_ref=ref $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='ac000000-0000-0000-0000-0000000000a1'; j1 text:='ac000000-0000-0000-0000-000000000001';
        j2 text:='ac000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Move IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j2); perform join_game(code,'P2',gen_random_uuid());
  perform pg_temp._as_admin();
  insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx select 'p2', public_ref from players where game_id=gid and auth_uid=j2::uuid;
  insert into _ctx values ('p1_uid',j1),('p2_uid',j2);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(j2); perform choose_token(gid,'roadster'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- M1) posiciones iniciales: los 3 jugadores en classic, índice 0.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; n int; begin
  select count(*) into n from public.player_positions where game_id=gid and board_key='classic' and space_index=0;
  perform pg_temp._rec('M1) posiciones iniciales en salida (classic, índice 0) x3', n=3);
end $$;

-- M2) mover manual N pasos: avanza dentro del tablero (sin pasar salida).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); old int; nw int; ring int; begin
  old := pg_temp._pos(gid,cur); ring := public._p4_ring_size('classic');
  perform pg_temp._as_user(pg_temp._uid(gid,cur)); perform move_player(gid,5,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); nw := pg_temp._pos(gid,cur);
  perform pg_temp._rec('M2) mover 5 pasos avanza a (old+5) mod ring', nw = (old+5) % ring);
end $$;

-- M3) límites: 0, negativo y >12 rechazados (INVALID_STEPS); 1 y 12 válidos.
-- (Se coloca en una zona sin la bifurcación de la cárcel-guardián para probar el avance simple.)
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; ok0 boolean:=false; okn boolean:=false; ok13 boolean:=false; ok1 boolean:=false; ok12 boolean:=false; old int; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(uid);
  begin perform move_player(gid,0,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok0:=(sqlerrm='INVALID_STEPS'); end;
  begin perform move_player(gid,-3,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okn:=(sqlerrm='INVALID_STEPS'); end;
  begin perform move_player(gid,13,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok13:=(sqlerrm='INVALID_STEPS'); end;
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',21,'situar lejos cárcel',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); old:=pg_temp._pos(gid,cur);
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); ok1:=(pg_temp._pos(gid,cur)=(old+1)%public._p4_ring_size('classic'));
  perform pg_temp._as_admin(); old:=pg_temp._pos(gid,cur);
  perform pg_temp._as_user(uid); perform move_player(gid,12,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); ok12:=(pg_temp._pos(gid,cur)=(old+12)%public._p4_ring_size('classic'));
  perform pg_temp._rec('M3) límites de pasos: 0/neg/>12 → INVALID_STEPS; 1 y 12 válidos', ok0 and okn and ok13 and ok1 and ok12);
end $$;

-- M4) solo el jugador actual puede mover (otro → NOT_CURRENT_PLAYER).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; other text; ok boolean:=false; begin
  cur:=pg_temp._cur(gid);
  select v into other from _ctx where k in ('p1','p2','host_ref') and v<>cur limit 1;
  perform pg_temp._as_user(pg_temp._uid(gid,other));
  begin perform move_player(gid,3,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='NOT_CURRENT_PLAYER'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('M4) solo el actual mueve (otro → NOT_CURRENT_PLAYER)', ok);
end $$;

-- M5) caer en propiedad disponible: el snapshot del jugador lo refleja (current_space + properties).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host'); cur text; uid text;
            snap jsonb; pref text; avail boolean; buyable boolean; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  -- el anfitrión coloca al actual en la salida; luego avanza 1 → índice 1 (primera propiedad).
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',0,'reset prueba',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  snap := get_active_snapshot_by_code(code);
  perform pg_temp._as_admin();
  pref := snap->'current_space'->>'property_ref';
  select (p->>'owner_ref') is null, (p->>'is_buyable')::boolean into avail, buyable
    from jsonb_array_elements(snap->'properties') p where p->>'property_ref'=pref;
  perform pg_temp._rec('M5) caer en propiedad: current_space tiene property_ref y está disponible',
    pref is not null and (snap->'current_space'->>'space_type')='property' and avail and buyable);
end $$;

-- M6) espectador/bancarrota no mueve (NOT_ACTIVE_MEMBER).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2 text:=pg_temp._ctx('p2'); p2u text:=pg_temp._ctx('p2_uid'); rref text; ok boolean:=false; begin
  perform pg_temp._as_user(p2u); perform request_bankruptcy(gid,'to_bank',null,'sin liquidez',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into rref from bankruptcy_requests where game_id=gid and requester_ref=p2 and status='pending';
  perform pg_temp._as_user(host); perform resolve_bankruptcy(rref,true,pg_temp._ver(gid));
  perform pg_temp._as_user(p2u);
  begin perform roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='NOT_ACTIVE_MEMBER'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('M6) jugador en bancarrota (espectador) no mueve (NOT_ACTIVE_MEMBER)', ok);
end $$;

-- M7) pausa y finalización bloquean el movimiento.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; okp boolean:=false; okf boolean:=false; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(host); perform pause_game_runtime(gid,'',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid);
  begin perform move_player(gid,2,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okp:=(sqlerrm='GAME_PAUSED'); end;
  perform pg_temp._as_user(host); perform resume_game_runtime(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform finish_game_runtime(gid,'',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid);
  begin perform move_player(gid,2,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okf:=(sqlerrm='GAME_FINISHED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('M7) pausa (GAME_PAUSED) y finalización (GAME_FINISHED) bloquean mover', okp and okf);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── movement_phase4: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
