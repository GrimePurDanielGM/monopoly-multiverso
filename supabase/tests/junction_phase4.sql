-- ============================================================================
-- Cruce entre tableros (Fase 4 corrección 4): la cárcel-guardián es bifurcación; el movimiento se
-- detiene y el jugador elige seguir (gratis) o cruzar (peaje), el guardián se mueve, paso por salida.
-- Host + 1 jugador. Tras `supabase db reset`.
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
create or replace function pg_temp._pos(gid uuid, ref text) returns text language sql security definer as $f$ select board_key||':'||space_index from public.player_positions where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._pend(gid uuid) returns jsonb language sql security definer as $f$ select pending_junction from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._guards(gid uuid, bk text) returns text language sql security definer as $f$ select guards from public.game_guardians where game_id=gid and board_key=bk $f$;
create or replace function pg_temp._bal(gid uuid, ref text) returns bigint language sql security definer as $f$ select balance from public.player_balances where game_id=gid and player_ref=ref $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='cc100000-0000-0000-0000-0000000000c1'; j1 text:='cc100000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Junc IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- Helper: pone el turno al jugador y lo coloca en una casilla del Classic.
create or replace function pg_temp._goto(gid uuid, host text, ref text, ix int) returns void language plpgsql as $f$
begin
  perform pg_temp._as_user(host); perform host_set_turn(gid, ref, 'turno cruce test', gen_random_uuid(), pg_temp._ver(gid));
  perform host_set_player_position(gid, ref, 'classic', ix, 'situar cruce test', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin();
end $f$;

-- J1) desde Salida con 12: se DETIENE en la cárcel (10) con 2 restantes; no avanza solo a Electricidad.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; pj jsonb; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._goto(gid, host, cur, 0);
  perform pg_temp._as_user(uid); perform move_player(gid, 12, gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin(); pj := pg_temp._pend(gid);
  perform pg_temp._rec('J1) 12 desde Salida se detiene en la cárcel (pending, 2 restantes), no avanza solo',
    pj is not null and (pj->>'junction_index')='10' and (pj->>'remaining')='2' and pg_temp._pos(gid,cur)='classic:10');
end $$;

-- J2) con decisión pendiente no se puede volver a tirar/mover (JUNCTION_PENDING).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); uid text; ok boolean:=false; begin
  uid:=pg_temp._uid(gid,cur); perform pg_temp._as_user(uid);
  begin perform move_player(gid,3,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='JUNCTION_PENDING'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('J2) con cruce pendiente no se puede mover (JUNCTION_PENDING)', ok);
end $$;

-- J3) elegir SEGUIR (own): gratis (guardián custodia el cruce), avanza a Electricidad (12); guardián pasa a 'own'.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); uid text; b0 bigint; begin
  uid:=pg_temp._uid(gid,cur); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(uid); perform resolve_junction(gid,'own',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J3) seguir es gratis y avanza a Electricidad (classic:12); guardián se mueve a own',
    pg_temp._pos(gid,cur)='classic:12' and pg_temp._bal(gid,cur)=b0 and pg_temp._pend(gid) is null and pg_temp._guards(gid,'classic')='own');
end $$;

-- J4) ahora el guardián custodia 'own': cruzar es GRATIS → cae en el Parking del RdF; guardián pasa a 'cross'.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._goto(gid, host, cur, 9);                       -- 1 antes de la cárcel
  perform pg_temp._as_user(uid); perform move_player(gid, 2, gen_random_uuid(), pg_temp._ver(gid));  -- llega a 10 con 1 restante
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(uid); perform resolve_junction(gid,'cross',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J4) cruzar (libre ahora) cae en Parking RdF (back_to_the_future:20), gratis; guardián a cross',
    pg_temp._pos(gid,cur)='back_to_the_future:20' and pg_temp._bal(gid,cur)=b0 and pg_temp._guards(gid,'classic')='cross');
end $$;

-- J5) cruzar cuando el guardián custodia el cruce: paga el peaje 100.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; nled int; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_admin(); if pg_temp._guards(gid,'classic')<>'cross' then
    perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',9,'reset',gen_random_uuid(),pg_temp._ver(gid)); end if;
  perform pg_temp._goto(gid, host, cur, 9);
  -- asegurar que el guardián custodia el cruce
  perform pg_temp._as_admin(); update public.game_guardians set guards='cross' where game_id=gid and board_key='classic';
  perform pg_temp._as_user(uid); perform move_player(gid, 3, gen_random_uuid(), pg_temp._ver(gid));  -- 9→cárcel(10) +2 restantes
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(uid); perform resolve_junction(gid,'cross',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  select count(*) into nled from public.ledger where game_id=gid and kind='guardian_toll' and from_ref=cur and amount=100;
  perform pg_temp._rec('J5) cruzar por la entrada custodiada paga peaje 100 (ledger guardian_toll)',
    pg_temp._bal(gid,cur)=b0-100 and nled=1 and pg_temp._guards(gid,'classic')='cross');
end $$;

-- J6) sin decisión pendiente, resolve_junction falla (NO_PENDING_JUNCTION).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); uid text; ok boolean:=false; begin
  uid:=pg_temp._uid(gid,cur); perform pg_temp._as_user(uid);
  begin perform resolve_junction(gid,'own',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='NO_PENDING_JUNCTION'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('J6) sin bifurcación pendiente → NO_PENDING_JUNCTION', ok);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── junction_phase4: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
