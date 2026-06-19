-- ============================================================================
-- Restricción de solicitud de compra (Fase 4 corrección): solo si es tu turno y estás en la casilla de
-- esa propiedad. Las pujas no exigen turno. Host + 2 jugadores. Tras `supabase db reset`.
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
create or replace function pg_temp._idx(prop text) returns int language sql security definer as $f$ select space_index from public.board_spaces where property_ref=prop and active limit 1 $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='ab000000-0000-0000-0000-0000000000a1'; j1 text:='ab000000-0000-0000-0000-000000000001'; j2 text:='ab000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('PR IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- Q1) no es mi turno → NOT_CURRENT_PLAYER (aunque esté en la casilla).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; other text; ouid text; ok boolean:=false; begin
  cur:=pg_temp._cur(gid); select v into other from _ctx where k in ('p1','p2','host_ref') and v<>cur limit 1; ouid:=pg_temp._uid(gid,other);
  perform pg_temp._as_user(host); perform host_set_player_position(gid, other, 'classic', pg_temp._idx('cl-bailen'), 'situar no-actual', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(ouid);
  begin perform request_property_purchase(gid,'cl-bailen',gen_random_uuid()); exception when others then ok:=(sqlerrm='NOT_CURRENT_PLAYER'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('Q1) no es mi turno → NOT_CURRENT_PLAYER', ok);
end $$;

-- Q2) es mi turno pero NO estoy en esa casilla → NOT_ON_PROPERTY.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; cuid text; ok boolean:=false; begin
  cur:=pg_temp._cur(gid); cuid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid, cur, 'classic', 0, 'a la salida', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(cuid);
  begin perform request_property_purchase(gid,'cl-prado',gen_random_uuid()); exception when others then ok:=(sqlerrm='NOT_ON_PROPERTY'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('Q2) mi turno pero no en la casilla → NOT_ON_PROPERTY', ok);
end $$;

-- Q3) mi turno + en la casilla + disponible → solicitud creada.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; cuid text; n int; begin
  cur:=pg_temp._cur(gid); cuid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid, cur, 'classic', pg_temp._idx('cl-serrano'), 'en Serrano', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(cuid); perform request_property_purchase(gid,'cl-serrano',gen_random_uuid());
  perform pg_temp._as_admin(); select count(*) into n from property_purchase_requests where game_id=gid and property_ref='cl-serrano' and status='pending';
  perform pg_temp._rec('Q3) mi turno y en la casilla disponible → solicitud creada', n=1);
end $$;

-- Q4) en la casilla pero en subasta activa → PROPERTY_IN_AUCTION.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; cuid text; ok boolean:=false; begin
  cur:=pg_temp._cur(gid); cuid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(host); perform start_property_auction(gid,'cl-gran-via',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform host_set_player_position(gid, cur, 'classic', pg_temp._idx('cl-gran-via'), 'en Gran Via', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(cuid);
  begin perform request_property_purchase(gid,'cl-gran-via',gen_random_uuid()); exception when others then ok:=(sqlerrm='PROPERTY_IN_AUCTION'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('Q4) en subasta activa → PROPERTY_IN_AUCTION', ok);
end $$;

-- Q5) un jugador NO actual SÍ puede pujar en la subasta activa.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; other text; ouid text; aref text; hb bigint; begin
  cur:=pg_temp._cur(gid); select v into other from _ctx where k in ('p1','p2') and v<>cur limit 1; ouid:=pg_temp._uid(gid,other);
  perform pg_temp._as_admin(); select public_ref into aref from property_auctions where game_id=gid and property_ref='cl-gran-via' and status='active';
  perform pg_temp._as_user(ouid); perform place_property_bid(gid,aref,100,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); select high_bid into hb from property_auctions where public_ref=aref;
  perform pg_temp._rec('Q5) puja válida de un jugador no-actual (no exige turno)', hb=100);
end $$;

-- Q6) no se puede pujar sin saldo suficiente (INSUFFICIENT_FUNDS).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; other text; ouid text; aref text; ok boolean:=false; begin
  cur:=pg_temp._cur(gid); select v into other from _ctx where k in ('p1','p2') and v<>cur limit 1; ouid:=pg_temp._uid(gid,other);
  perform pg_temp._as_admin(); select public_ref into aref from property_auctions where game_id=gid and property_ref='cl-gran-via' and status='active';
  perform pg_temp._as_user(host); perform host_adjust_balance(gid, other, 50, 'sin fondos (test)', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(ouid);
  begin perform place_property_bid(gid,aref,500,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='INSUFFICIENT_FUNDS'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('Q6) puja sin fondos → INSUFFICIENT_FUNDS', ok);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── purchase_restriction_phase4: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
