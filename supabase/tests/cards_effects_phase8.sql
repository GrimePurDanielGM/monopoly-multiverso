-- ============================================================================
-- Fase 8 (C2) — Efectos enriquecidos de cartas reales: to_space (avance/retroceso), to_nearest, repairs (al bote),
-- bank_debit al bote, y la carta de elección (choice: pagar / robar Suerte). Tras `db reset`.
-- Se fija el mazo a mano y se cae en la casilla de carta moviendo 1 paso.
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
create or replace function pg_temp._pendkind(gid uuid) returns text language sql security definer as $f$ select pending_card->>'kind' from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._lastdeck(gid uuid) returns text language sql security definer as $f$ select last_card_draw->>'deck_key' from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._lastcard(gid uuid) returns text language sql security definer as $f$ select last_card_draw->>'card_ref' from public.game_runtime where game_id=gid $f$;
-- Fija un mazo concreto con una sola carta.
create or replace function pg_temp._stackd(gid uuid, deck text, ref text) returns void language plpgsql security definer as $f$
begin perform public._p5_ensure_decks(gid);
  update public.game_card_decks set draw_pile = array[ref] where game_id=gid and deck_key=deck; end $f$;
create or replace function pg_temp._clearpend(gid uuid) returns void language sql security definer as $f$
  update public.game_runtime set pending_card=null, parking_pot=0 where game_id=gid $f$;
create or replace function pg_temp._own(gid uuid, prop text, ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,ref) on conflict do nothing $f$;
create or replace function pg_temp._sethouses(gid uuid, prop text, n int) returns void language sql security definer as $f$
  insert into public.game_property_state(game_id,property_ref,houses,has_hotel) values (gid,prop,n,false)
    on conflict (game_id,property_ref) do update set houses=n, has_hotel=false $f$;
-- Coloca al jugador 1 casilla antes de `card_idx` y mueve 1 para caer y robar del mazo correspondiente.
create or replace function pg_temp._land(gid uuid, board text, card_idx int) returns void language plpgsql as $f$
declare host text:=pg_temp._ctx('host'); cur text:=pg_temp._cur(gid); uid text:=pg_temp._uid(gid,cur); begin
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,board,card_idx-1,'pre',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); end $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='bc000000-0000-0000-0000-0000000000a1'; j1 text:='bc000000-0000-0000-0000-000000000001';
        j2 text:='bc000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Cards C2','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
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

-- T1) to_space AVANCE con sueldo: desde 35 cae en Suerte(36) y la carta lo manda a Glorieta de Bilbao (11<=36 ⇒ +200).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; b0 bigint; begin
  perform pg_temp._clearpend(gid); cur:=pg_temp._cur(gid);
  perform pg_temp._as_user(pg_temp._ctx('host')); perform host_set_player_position(gid,cur,'classic',35,'pre',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); perform pg_temp._stackd(gid,'chance','chance-bilbao'); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(pg_temp._uid(gid,cur)); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('T1) to_space avance: peón a 11 y cobra +200 por pasar Salida', pg_temp._pos(gid,cur)=11 and pg_temp._bal(gid,cur)=b0+200);
end $$;

-- T2) to_space RETROCESO sin sueldo: cae en Caja(17) y la carta lo manda atrás a Ronda de Valencia (1), sin +200.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; b0 bigint; begin
  perform pg_temp._clearpend(gid); cur:=pg_temp._cur(gid); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._stackd(gid,'community_chest','cc-ronda-valencia');
  perform pg_temp._land(gid,'classic',17);
  perform pg_temp._rec('T2) to_space retroceso: peón a 1 y NO cobra Salida', pg_temp._pos(gid,cur)=1 and pg_temp._bal(gid,cur)=b0);
end $$;

-- T3) bank_debit al BOTE: multa de 15 € sale del saldo y entra al bote.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; b0 bigint; begin
  perform pg_temp._clearpend(gid); cur:=pg_temp._cur(gid); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._stackd(gid,'chance','chance-velocidad');
  perform pg_temp._land(gid,'classic',7);
  perform pg_temp._rec('T3) bank_debit: saldo -15 y bote +15', pg_temp._bal(gid,cur)=b0-15 and pg_temp._pot(gid)=15);
end $$;

-- T4) repairs al BOTE: 4 casas en una calle propia ⇒ paga 4×25=100 al bote.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; b0 bigint; begin
  perform pg_temp._clearpend(gid); cur:=pg_temp._cur(gid);
  perform pg_temp._own(gid,'cl-ronda-valencia',cur); perform pg_temp._sethouses(gid,'cl-ronda-valencia',4);
  b0:=pg_temp._bal(gid,cur);
  perform pg_temp._stackd(gid,'chance','chance-reparaciones');   -- 25/casa, 100/hotel
  perform pg_temp._land(gid,'classic',7);
  perform pg_temp._rec('T4) repairs: 4 casas → paga 100 al bote', pg_temp._bal(gid,cur)=b0-100 and pg_temp._pot(gid)=100);
end $$;

-- T5) choice PAGAR: la carta de elección deja pending kind=choice; resolve_card(pay) cobra 10 al bote.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; uid text; b0 bigint; begin
  perform pg_temp._clearpend(gid); cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._stackd(gid,'community_chest','cc-multa-o-suerte');
  perform pg_temp._land(gid,'classic',17); b0:=pg_temp._bal(gid,cur);
  if pg_temp._pendkind(gid) <> 'choice' then perform pg_temp._rec('T5) choice pagar', false);
  else
    perform pg_temp._as_user(uid); perform resolve_card(gid,gen_random_uuid(),pg_temp._ver(gid),'pay'); perform pg_temp._as_admin();
    perform pg_temp._rec('T5) choice pagar: saldo -10, bote +10, pending limpio',
      pg_temp._bal(gid,cur)=b0-10 and pg_temp._pot(gid)=10 and pg_temp._pendkind(gid) is null);
  end if;
end $$;

-- T6) choice ROBAR: resolve_card(draw) roba una carta de Suerte (last_card_draw pasa a 'chance').
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; uid text; begin
  perform pg_temp._clearpend(gid); cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._stackd(gid,'chance','chance-velocidad');           -- la Suerte que se robará
  perform pg_temp._stackd(gid,'community_chest','cc-multa-o-suerte');
  perform pg_temp._land(gid,'classic',17);
  perform pg_temp._as_user(uid); perform resolve_card(gid,gen_random_uuid(),pg_temp._ver(gid),'draw'); perform pg_temp._as_admin();
  perform pg_temp._rec('T6) choice robar: roba una carta de Suerte', pg_temp._lastdeck(gid)='chance' and pg_temp._lastcard(gid)='chance-velocidad');
end $$;

-- T7) to_nearest: en btf, cae en Pasado(22) y la carta lo lleva al transporte más cercano (idx 25); deja pendiente manual.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; begin
  perform pg_temp._clearpend(gid); cur:=pg_temp._cur(gid);
  perform pg_temp._stackd(gid,'past','past-transporte');
  perform pg_temp._land(gid,'back_to_the_future',22);
  perform pg_temp._rec('T7) to_nearest: peón al transporte 25 y pendiente manual',
    pg_temp._pos(gid,cur)=25 and pg_temp._pendkind(gid)='manual');
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
