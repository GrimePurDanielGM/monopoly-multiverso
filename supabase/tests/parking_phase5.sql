-- ============================================================================
-- Parking gratuito (Fase 5): al caer en Parking se cobra el bote acumulado (vuelve a 0); si el bote es 0
-- no se cobra; ledger parking_pot_payout. Cruzar al Parking del otro tablero también cobra. Tras `db reset`.
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
create or replace function pg_temp._pot(gid uuid) returns bigint language sql security definer as $f$ select parking_pot from public.game_runtime where game_id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='ae000000-0000-0000-0000-0000000000a1'; j1 text:='ae000000-0000-0000-0000-000000000001';
        j2 text:='ae000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Park IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- P1) bote > 0: caer en Parking (classic idx 20) cobra el bote entero y el bote vuelve a 0.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; b1 bigint; snap jsonb; begin
  perform pg_temp._as_admin(); update public.game_runtime set parking_pot = 300 where game_id=gid;
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',19,'antes de parking',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,cur);
  perform pg_temp._rec('P1) caer en Parking cobra el bote (saldo +300), bote→0, effect=parking',
    b1 = b0 + 300 and pg_temp._pot(gid) = 0
    and (snap->'last_move'->'effect'->>'type')='parking' and (snap->'last_move'->'effect'->>'payout')='300');
end $$;

-- P2) ledger parking_pot_payout (banca -> jugador, 300).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; n int; begin
  perform pg_temp._as_admin(); cur:=pg_temp._cur(gid);
  select count(*) into n from public.ledger where game_id=gid and kind='parking_pot_payout' and from_ref is null and to_ref=cur and amount=300;
  perform pg_temp._rec('P2) ledger parking_pot_payout (banca→jugador, 300)', n>=1);
end $$;

-- P3) bote = 0: caer en Parking no cobra (saldo igual, effect.payout = 0).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; b1 bigint; snap jsonb; begin
  perform pg_temp._as_admin(); update public.game_runtime set parking_pot = 0 where game_id=gid;
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',19,'antes de parking vacío',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,cur);
  perform pg_temp._rec('P3) Parking con bote 0 no cobra (saldo igual, payout 0)',
    b1 = b0 and (snap->'last_move'->'effect'->>'payout')='0');
end $$;

-- P4) el snapshot expone parking_pot.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; snap jsonb; begin
  perform pg_temp._as_admin(); update public.game_runtime set parking_pot = 175 where game_id=gid;
  cur:=pg_temp._cur(gid);
  perform pg_temp._as_user(pg_temp._uid(gid,cur)); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  perform pg_temp._rec('P4) snapshot expone parking_pot', (snap->>'parking_pot')='175');
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── parking_phase5: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
