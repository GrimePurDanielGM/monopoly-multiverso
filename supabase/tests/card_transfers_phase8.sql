-- ============================================================================
-- Fase 8 (C3) — Cobros/pagos «a cada jugador» con autorización. Tras `db reset`.
-- Robar una carta each_player crea transferencias PENDIENTES (no mueve dinero); cada pagador (authorizer) las
-- autoriza y entonces se mueve el dinero. El snapshot expone my_card_transfers a quien debe autorizar.
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
create or replace function pg_temp._other(gid uuid, notref text) returns text language sql security definer as $f$
  select p.public_ref from public.players p join public.game_runtime rt on rt.game_id=p.game_id
   where p.game_id=gid and p.public_ref<>notref and p.public_ref = any(rt.turn_order_refs) order by p.public_ref limit 1 $f$;
create or replace function pg_temp._npend(gid uuid) returns int language sql security definer as $f$ select count(*)::int from public.game_card_transfers where game_id=gid and status='pending' $f$;
create or replace function pg_temp._transref(gid uuid, auth_ref text) returns uuid language sql security definer as $f$
  select public_ref from public.game_card_transfers where game_id=gid and authorizer_ref=auth_ref and status='pending' order by created_at limit 1 $f$;
create or replace function pg_temp._mytrans(gid uuid, ref text) returns int language sql security definer as $f$
  select jsonb_array_length(coalesce(public.get_active_snapshot_by_code((select code from public.games where id=gid))->'my_card_transfers','[]')) $f$;  -- nota: se llama como el usuario
create or replace function pg_temp._stackd(gid uuid, deck text, ref text) returns void language plpgsql security definer as $f$
begin perform public._p5_ensure_decks(gid);
  update public.game_card_decks set draw_pile = array[ref] where game_id=gid and deck_key=deck; end $f$;
create or replace function pg_temp._land(gid uuid, board text, card_idx int) returns void language plpgsql as $f$
declare host text:=pg_temp._ctx('host'); cur text:=pg_temp._cur(gid); uid text:=pg_temp._uid(gid,cur); begin
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,board,card_idx-1,'pre',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); end $f$;
create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='be000000-0000-0000-0000-0000000000a1'; j1 text:='be000000-0000-0000-0000-000000000001';
        j2 text:='be000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Transfers C3','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j2); perform join_game(code,'P2',gen_random_uuid());
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(j2); perform choose_token(gid,'roadster'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
  update public.player_balances set balance=100000 where game_id=gid;
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- EC1) cobra 10 de cada jugador: al robar se crean 2 pendientes (otros pagan al que robó); sin mover dinero aún.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; b0 bigint; begin
  cur:=pg_temp._cur(gid); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._stackd(gid,'community_chest','cc-cumpleanos');   -- each_player_credit 10
  perform pg_temp._land(gid,'classic',17);
  perform pg_temp._rec('EC1) cobra de cada uno: 2 pendientes y saldo del que robó sin cambiar',
    pg_temp._npend(gid)=2 and pg_temp._bal(gid,cur)=b0);
end $$;
-- EC1b) el snapshot muestra my_card_transfers a un pagador (otro jugador).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; oth text; n int; begin
  cur:=pg_temp._cur(gid); oth:=pg_temp._other(gid,cur);
  perform pg_temp._as_user(pg_temp._uid(gid,oth)); n:=pg_temp._mytrans(gid,oth); perform pg_temp._as_admin();
  perform pg_temp._rec('EC1b) el pagador ve 1 transferencia a autorizar en su snapshot', n=1);
end $$;
-- EC2) el otro autoriza → paga 10 al que robó.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; oth text; bo0 bigint; bc0 bigint; tref uuid; begin
  cur:=pg_temp._cur(gid); oth:=pg_temp._other(gid,cur); bo0:=pg_temp._bal(gid,oth); bc0:=pg_temp._bal(gid,cur);
  tref:=pg_temp._transref(gid,oth);
  perform pg_temp._as_user(pg_temp._uid(gid,oth)); perform authorize_card_transfer(gid,tref,gen_random_uuid(),pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('EC2) autorizar: el pagador -10, el que robó +10, 1 pendiente menos',
    pg_temp._bal(gid,oth)=bo0-10 and pg_temp._bal(gid,cur)=bc0+10 and pg_temp._npend(gid)=1);
end $$;
-- EC3) sólo el authorizer puede autorizar (otro jugador → NOT_TRANSFER_AUTHORIZER).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; oth text; tref uuid; ok boolean; begin
  perform pg_temp._as_admin(); delete from public.game_card_transfers where game_id=gid;  -- limpiar EC
  cur:=pg_temp._cur(gid);
  perform pg_temp._stackd(gid,'community_chest','cc-cumpleanos'); perform pg_temp._land(gid,'classic',17);
  oth:=pg_temp._other(gid,cur); tref:=pg_temp._transref(gid,oth);
  begin perform pg_temp._as_user(pg_temp._uid(gid,cur)); perform authorize_card_transfer(gid,tref,gen_random_uuid(),pg_temp._ver(gid)); ok:=false;
  exception when others then ok:=(sqlerrm='NOT_TRANSFER_AUTHORIZER'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('EC3) sólo el pagador autoriza (otro → NOT_TRANSFER_AUTHORIZER)', ok);
end $$;
-- ED1) paga 50 a cada jugador: el que robó autoriza cada pago (authorizer = el que robó).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; oth text; bc0 bigint; bo0 bigint; tref uuid; begin
  perform pg_temp._as_admin(); delete from public.game_card_transfers where game_id=gid;
  cur:=pg_temp._cur(gid);
  perform pg_temp._stackd(gid,'past','past-paga-cada-50'); perform pg_temp._land(gid,'back_to_the_future',22);
  oth:=pg_temp._other(gid,cur); bc0:=pg_temp._bal(gid,cur); bo0:=pg_temp._bal(gid,oth);
  tref:=pg_temp._transref(gid,cur);   -- authorizer = el que robó
  perform pg_temp._as_user(pg_temp._uid(gid,cur)); perform authorize_card_transfer(gid,tref,gen_random_uuid(),pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('ED1) pago a cada uno: el que robó autoriza y paga 50 a un jugador',
    pg_temp._bal(gid,cur)=bc0-50 and pg_temp._bal(gid,oth)=bo0+50);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
