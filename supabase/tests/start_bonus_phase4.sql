-- ============================================================================
-- Paso por salida (Fase 4): cobro de 200, reconciliación y no doble cobro por idempotencia.
-- Host + 2 jugadores. Tras `supabase db reset`.
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
create or replace function pg_temp._bal(gid uuid, ref text) returns bigint language sql security definer as $f$ select balance from public.player_balances where game_id=gid and player_ref=ref $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='bc000000-0000-0000-0000-0000000000b1'; j1 text:='bc000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Bonus IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- S1) pasar por salida cobra 200 (ring=29; colocar en índice 27 y avanzar 5 → da la vuelta).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; b1 bigint; ring int; expidx int; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur); ring:=public._p4_ring_size('classic');
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',ring-2,'preparar vuelta',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,cur); expidx:=((ring-2)+5)%ring;
  perform pg_temp._as_user(uid); perform move_player(gid,5,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,cur);
  perform pg_temp._rec('S1) pasar por salida cobra 200 y coloca en el índice correcto',
    b1 = b0 + 200
    and (select space_index from public.player_positions where game_id=gid and player_ref=cur) = expidx);
end $$;

-- S2) ledger pass_start_bonus: banca → jugador, importe 200, reconciliable.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); n int; begin
  select count(*) into n from public.ledger where game_id=gid and kind='pass_start_bonus' and from_ref is null and to_ref=cur and amount=200;
  perform pg_temp._rec('S2) ledger pass_start_bonus (banca→jugador, 200)', n=1);
end $$;

-- S3) caer EXACTAMENTE en salida tras dar la vuelta también cobra.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; b1 bigint; ring int; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur); ring:=public._p4_ring_size('classic');
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',ring-3,'preparar exacta',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(uid); perform move_player(gid,3,gen_random_uuid(),pg_temp._ver(gid));  -- cae en índice 0
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,cur);
  perform pg_temp._rec('S3) caer exactamente en salida cobra 200',
    b1 = b0 + 200 and (select space_index from public.player_positions where game_id=gid and player_ref=cur)=0);
end $$;

-- S4) idempotencia: reintentar el MISMO request_id no cobra dos veces.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; rid uuid:=gen_random_uuid(); b0 bigint; b1 bigint; ring int; nled int; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur); ring:=public._p4_ring_size('classic');
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',ring-1,'preparar idem',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(uid); perform move_player(gid,2,rid,pg_temp._ver(gid));   -- da la vuelta: +200
  -- reintento exacto (misma request_id y versión ya consumida): devuelve el resultado guardado, sin reefecto
  perform move_player(gid,2,rid,pg_temp._ver(gid)-1);
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,cur);
  select count(*) into nled from public.ledger where game_id=gid and kind='pass_start_bonus' and request_id=rid;
  perform pg_temp._rec('S4) no doble cobro por idempotencia (un solo ledger, +200 una vez)', b1 = b0 + 200 and nled = 1);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── start_bonus_phase4: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
