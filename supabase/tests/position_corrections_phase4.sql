-- ============================================================================
-- Corrección de posición por el anfitrión (Fase 4): coloca la ficha, sin cobrar salida ni
-- disparar compra/alquiler; motivo obligatorio; no-host no puede. Tras `supabase db reset`.
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
create or replace function pg_temp._pos(gid uuid, ref text) returns int language sql security definer as $f$ select space_index from public.player_positions where game_id=gid and player_ref=ref $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='cc000000-0000-0000-0000-0000000000c1'; j1 text:='cc000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Pos IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- P1) el anfitrión corrige la posición de un jugador (queda colocado).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); begin
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p1,'classic',7,'recolocar',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('P1) host coloca a un jugador en classic índice 7', pg_temp._pos(gid,p1)=7);
end $$;

-- P2) la corrección NO cobra salida aunque "dé la vuelta" (saldo intacto, sin ledger de bonus).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); b0 bigint; b1 bigint; nled int; begin
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,p1);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p1,'classic',0,'volver a salida sin cobrar',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,p1);
  select count(*) into nled from public.ledger where game_id=gid and kind='pass_start_bonus' and to_ref=p1;
  perform pg_temp._rec('P2) corrección de posición no cobra salida (saldo intacto, sin bonus)', b1=b0 and nled=0);
end $$;

-- P3) motivo obligatorio (REASON_REQUIRED).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); ok boolean:=false; begin
  perform pg_temp._as_user(host);
  begin perform host_set_player_position(gid,p1,'classic',3,'',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='REASON_REQUIRED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('P3) motivo obligatorio (REASON_REQUIRED)', ok);
end $$;

-- P4) índice fuera de rango rechazado (INVALID_SPACE).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); ok boolean:=false; ring int; begin
  ring:=public._p4_ring_size('classic'); perform pg_temp._as_user(host);
  begin perform host_set_player_position(gid,p1,'classic',ring,'fuera de rango',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='INVALID_SPACE'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('P4) índice fuera de rango (INVALID_SPACE)', ok);
end $$;

-- P5) un NO-anfitrión no puede corregir posición (NOT_HOST).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); host_ref text:=pg_temp._ctx('host_ref'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform host_set_player_position(gid,host_ref,'classic',4,'intento no-host',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('P5) no-anfitrión no corrige posición (NOT_HOST)', ok);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── position_corrections_phase4: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
