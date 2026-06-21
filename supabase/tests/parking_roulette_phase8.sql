-- ============================================================================
-- Fase 8 (C4) — Ruleta de Parking. Tras `db reset`. Se fuerza cada resultado (p_force) y se verifica el efecto;
-- también que parking_mode='roulette' dispara la ruleta al caer en Parking y 'pot' cobra el bote.
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
create or replace function pg_temp._pot(gid uuid) returns bigint language sql security definer as $f$ select parking_pot from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._setpot(gid uuid, n bigint) returns void language sql security definer as $f$ update public.game_runtime set parking_pot=n where game_id=gid $f$;
create or replace function pg_temp._owns(gid uuid, prop text, ref text) returns boolean language sql security definer as $f$
  select exists(select 1 from public.property_ownership where game_id=gid and property_ref=prop and owner_ref=ref and released_at is null) $f$;
create or replace function pg_temp._own(gid uuid, prop text, ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,ref) on conflict do nothing $f$;
create or replace function pg_temp._evt(gid uuid) returns text language sql security definer as $f$ select last_global_event->>'outcome' from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._evtkind(gid uuid) returns text language sql security definer as $f$ select last_global_event->>'kind' from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._injail(gid uuid, ref text) returns boolean language sql security definer as $f$ select exists(select 1 from public.game_jail where game_id=gid and player_ref=ref) $f$;
create or replace function pg_temp._setmode(gid uuid, m text) returns void language sql security definer as $f$ update public.games set config = config || jsonb_build_object('parking_mode', m) where id=gid $f$;
-- gira la ruleta forzando un resultado, como admin (la función está revocada a authenticated).
create or replace function pg_temp._spin(gid uuid, ref text, force int) returns void language sql security definer as $f$
  select public._p5_parking_roulette(gid, (select p from public.players p where p.game_id=gid and p.public_ref=ref), 'classic', force) $f$;
create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='bd000000-0000-0000-0000-0000000000a1'; j1 text:='bd000000-0000-0000-0000-000000000001';
        j2 text:='bd000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Roulette C4','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j2); perform join_game(code,'P2',gen_random_uuid());
  perform pg_temp._as_admin();
  insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(j2); perform choose_token(gid,'roadster'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
  update public.player_balances set balance=100000 where game_id=gid;
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- R-collect) resultado 2 (cobrar bote): bote 1000 → jugador +1000, bote a 0.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); b0 bigint; begin
  perform pg_temp._setpot(gid,1000); b0:=pg_temp._bal(gid,cur); perform pg_temp._spin(gid,cur,2);
  perform pg_temp._rec('R2) cobrar bote: +1000 y bote a 0', pg_temp._bal(gid,cur)=b0+1000 and pg_temp._pot(gid)=0 and pg_temp._evt(gid)='collect_pot');
end $$;
-- R-jail) resultado 3: a la cárcel (pos 10).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); begin
  perform pg_temp._spin(gid,cur,3);
  perform pg_temp._rec('R3) ir a la cárcel: en la cárcel y pos 10', pg_temp._injail(gid,cur) and pg_temp._pos(gid,cur)=10 and pg_temp._evt(gid)='go_to_jail');
  perform pg_temp._as_admin(); delete from public.game_jail where game_id=gid;  -- limpiar para siguientes
end $$;
-- R-most) resultado 4: pierde la propiedad más valiosa (Gran Vía 320, no Ronda 60).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); begin
  perform pg_temp._own(gid,'cl-ronda-valencia',cur); perform pg_temp._own(gid,'cl-gran-via',cur);
  perform pg_temp._spin(gid,cur,4);
  perform pg_temp._rec('R4) pierde la MÁS valiosa (Gran Vía) a la banca; conserva Ronda',
    not pg_temp._owns(gid,'cl-gran-via',cur) and pg_temp._owns(gid,'cl-ronda-valencia',cur) and pg_temp._evt(gid)='lose_most_valuable');
end $$;
-- R-least) resultado 5: pierde la menos valiosa (Ronda 60).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); begin
  perform pg_temp._spin(gid,cur,5);
  perform pg_temp._rec('R5) pierde la MENOS valiosa (Ronda) a la banca',
    not pg_temp._owns(gid,'cl-ronda-valencia',cur) and pg_temp._evt(gid)='lose_least_valuable');
end $$;
-- R-pay) resultado 6: paga 500 al bote.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); b0 bigint; begin
  perform pg_temp._setpot(gid,0); b0:=pg_temp._bal(gid,cur); perform pg_temp._spin(gid,cur,6);
  perform pg_temp._rec('R6) paga 500 al bote: saldo -500, bote +500', pg_temp._bal(gid,cur)=b0-500 and pg_temp._pot(gid)=500 and pg_temp._evt(gid)='pay_500');
end $$;
-- R-draw) resultado 1: roba una carta (last_card_draw del jugador).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); ok boolean; begin
  perform pg_temp._spin(gid,cur,1);
  perform pg_temp._as_admin(); select (last_global_event->>'outcome')='draw_card' and (last_card_draw->>'player_ref')=cur into ok from public.game_runtime where game_id=gid;
  perform pg_temp._rec('R1) robar carta: se roba una carta para el jugador', ok);
  update public.game_runtime set pending_card=null where game_id=gid;
end $$;
-- INT) parking_mode='roulette' dispara la ruleta al caer en Parking (idx 20 classic).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); uid text:=pg_temp._uid(gid,cur); begin
  perform pg_temp._setmode(gid,'roulette');
  perform pg_temp._as_user(pg_temp._ctx('host')); perform host_set_player_position(gid,cur,'classic',19,'pre',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('INT) parking_mode=roulette dispara la ruleta al caer en Parking', pg_temp._evtkind(gid)='parking_roulette');
  perform pg_temp._as_admin(); update public.game_runtime set pending_card=null where game_id=gid; delete from public.game_jail where game_id=gid;
end $$;
-- INT2) parking_mode='pot' (por defecto) cobra el bote al caer en Parking.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); uid text:=pg_temp._uid(gid,cur); b0 bigint; begin
  perform pg_temp._setmode(gid,'pot'); perform pg_temp._setpot(gid,777); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(pg_temp._ctx('host')); perform host_set_player_position(gid,cur,'classic',19,'pre',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('INT2) parking_mode=pot cobra el bote (777) al caer en Parking', pg_temp._bal(gid,cur)=b0+777 and pg_temp._pot(gid)=0);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
