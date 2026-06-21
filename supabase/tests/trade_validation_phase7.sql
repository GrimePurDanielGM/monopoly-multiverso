-- ============================================================================
-- Fase 7 — Validaciones de tratos (saldo, construcciones, hipoteca, self, eliminado, vacío, ajena, duplicado, carta).
-- Tras `supabase db reset`. Setup: partida activa con host (H), p1, p2; p1 posee Ronda (calle), p2 la estación de Goya.
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
create or replace function pg_temp._bal(gid uuid, ref text) returns bigint language sql security definer as $f$ select balance from public.player_balances where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._own(gid uuid, prop text, ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,ref) on conflict do nothing $f$;
create or replace function pg_temp._reown(gid uuid, prop text, ref text) returns void language sql security definer as $f$
  with rel as (update public.property_ownership set released_at=now() where game_id=gid and property_ref=prop and released_at is null returning 1)
  insert into public.property_ownership(game_id,property_ref,owner_ref) select gid,prop,ref from (select 1) s left join rel on true $f$;
create or replace function pg_temp._tstatus(gid uuid, tref text) returns text language sql security definer as $f$
  select status::text from public.game_trade_proposals where game_id=gid and public_ref=tref $f$;
create or replace function pg_temp._ownerof(gid uuid, prop text) returns text language sql security definer as $f$
  select owner_ref from public.property_ownership where game_id=gid and property_ref=prop and released_at is null $f$;
create or replace function pg_temp._cardcount(gid uuid, ref text) returns int language sql security definer as $f$
  select count(*)::int from public.game_held_cards where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._givecard(gid uuid, ref text, card text) returns void language sql security definer as $f$
  insert into public.game_held_cards(game_id,player_ref,card_ref) values (gid,ref,card) $f$;
create or replace function pg_temp._sethouses(gid uuid, prop text, n int) returns void language sql security definer as $f$
  insert into public.game_property_state(game_id,property_ref,houses) values (gid,prop,n)
    on conflict (game_id,property_ref) do update set houses=n $f$;
create or replace function pg_temp._setmort(gid uuid, prop text) returns void language sql security definer as $f$
  insert into public.game_property_state(game_id,property_ref,mortgaged) values (gid,prop,true)
    on conflict (game_id,property_ref) do update set mortgaged=true $f$;
create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='f8000000-0000-0000-0000-0000000000a1'; j1 text:='f8000000-0000-0000-0000-000000000001';
        j2 text:='f8000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Tratos IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_uid',host) on conflict (k) do update set v=excluded.v;
  perform pg_temp._as_admin(); insert into _ctx select 'host_ref', public_ref from players where game_id=gid and auth_uid=host::uuid on conflict (k) do update set v=excluded.v;
  select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j2); perform join_game(code,'P2',gen_random_uuid());
  perform pg_temp._as_admin();
  insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid on conflict (k) do update set v=excluded.v;
  insert into _ctx select 'p2', public_ref from players where game_id=gid and auth_uid=j2::uuid on conflict (k) do update set v=excluded.v;
  insert into _ctx values ('p1_uid',j1),('p2_uid',j2) on conflict (k) do update set v=excluded.v;
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(j2); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'iron'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v);
  perform pg_temp._as_admin();
  perform pg_temp._own(gid,'cl-ronda-valencia',pg_temp._ctx('p1'));
  perform pg_temp._own(gid,'cl-estacion-goya',pg_temp._ctx('p2'));
  update public.player_balances set balance=100000 where game_id=gid;
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- V1) más dinero del saldo → INSUFFICIENT_FUNDS.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform create_trade_proposal(gid, p2, 999999, 0, null, null, null, null, null, gen_random_uuid()); exception when others then ok:=(sqlerrm='INSUFFICIENT_FUNDS'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('V1) más dinero del saldo → INSUFFICIENT_FUNDS', ok);
end $$;
-- V2) propiedad con casas no se puede ofrecer → PROPERTY_HAS_BUILDINGS.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); ok boolean:=false; begin
  perform pg_temp._as_admin(); perform pg_temp._sethouses(gid,'cl-ronda-valencia',2);
  perform pg_temp._as_user(p1u);
  begin perform create_trade_proposal(gid, p2, 0, 0, array['cl-ronda-valencia'], null, null, null, null, gen_random_uuid()); exception when others then ok:=(sqlerrm='PROPERTY_HAS_BUILDINGS'); end;
  perform pg_temp._as_admin(); perform pg_temp._sethouses(gid,'cl-ronda-valencia',0);
  perform pg_temp._rec('V2) propiedad con casas no se ofrece → PROPERTY_HAS_BUILDINGS', ok);
end $$;
-- V3) propiedad hipotecada SÍ se puede ofrecer (y queda marcada en el trato).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); r jsonb; m boolean; begin
  perform pg_temp._as_admin(); perform pg_temp._setmort(gid,'cl-ronda-valencia');
  perform pg_temp._as_user(p1u); r := create_trade_proposal(gid, p2, 0, 0, array['cl-ronda-valencia'], null, null, null, null, gen_random_uuid());
  perform pg_temp._as_admin();
  select (i->>'mortgaged')::boolean into m from jsonb_array_elements(public._p7_props_json(gid, (select id from public.game_trade_proposals where game_id=gid and public_ref=r->>'trade_ref'), 'from')) i limit 1;
  perform pg_temp._rec('V3) propiedad hipotecada se ofrece y queda marcada', (r->>'status')='pending' and m=true);
  perform pg_temp._as_admin(); update public.game_property_state set mortgaged=false where game_id=gid and property_ref='cl-ronda-valencia';
  delete from public.game_trade_proposals where game_id=gid and status in ('pending','countered','host_review');
end $$;
-- V4) self-trade → SELF_TRADE_NOT_ALLOWED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p1 text:=pg_temp._ctx('p1'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform create_trade_proposal(gid, p1, 100, 0, null, null, null, null, null, gen_random_uuid()); exception when others then ok:=(sqlerrm='SELF_TRADE_NOT_ALLOWED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('V4) self-trade → SELF_TRADE_NOT_ALLOWED', ok);
end $$;
-- V5) jugador en bancarrota no puede recibir trato → PLAYER_NOT_ACTIVE.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); ok boolean:=false; begin
  perform pg_temp._as_admin(); update public.players set bankrupt_at=now() where game_id=gid and public_ref=p2;
  perform pg_temp._as_user(p1u);
  begin perform create_trade_proposal(gid, p2, 100, 0, null, null, null, null, null, gen_random_uuid()); exception when others then ok:=(sqlerrm='PLAYER_NOT_ACTIVE'); end;
  perform pg_temp._as_admin(); update public.players set bankrupt_at=null where game_id=gid and public_ref=p2;
  perform pg_temp._rec('V5) jugador eliminado no recibe trato → PLAYER_NOT_ACTIVE', ok);
end $$;
-- V6) trato vacío → EMPTY_TRADE.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform create_trade_proposal(gid, p2, 0, 0, null, null, null, null, null, gen_random_uuid()); exception when others then ok:=(sqlerrm='EMPTY_TRADE'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('V6) trato vacío → EMPTY_TRADE', ok);
end $$;
-- V7) ofrecer propiedad ajena → PROPERTY_NOT_OWNED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform create_trade_proposal(gid, p2, 0, 0, array['cl-estacion-goya'], null, null, null, null, gen_random_uuid()); exception when others then ok:=(sqlerrm='PROPERTY_NOT_OWNED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('V7) ofrecer propiedad ajena → PROPERTY_NOT_OWNED', ok);
end $$;
-- V8) propiedad ya en otro trato pendiente → PROPERTY_ALREADY_IN_PENDING_TRADE.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); ok boolean:=false; begin
  perform pg_temp._as_admin(); delete from public.game_trade_proposals where game_id=gid and status in ('pending','countered','host_review');
  perform pg_temp._as_user(p1u); perform create_trade_proposal(gid, p2, 0, 0, array['cl-ronda-valencia'], null, null, null, null, gen_random_uuid());
  begin perform create_trade_proposal(gid, p2, 0, 0, array['cl-ronda-valencia'], null, null, null, null, gen_random_uuid()); exception when others then ok:=(sqlerrm='PROPERTY_ALREADY_IN_PENDING_TRADE'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('V8) propiedad en otro trato pendiente → bloqueada', ok);
end $$;
-- V9) ofrecer carta que no se tiene → CARD_NOT_OWNED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform create_trade_proposal(gid, p2, 0, 0, null, null, array['chance-jail-free'], null, null, gen_random_uuid()); exception when others then ok:=(sqlerrm='CARD_NOT_OWNED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('V9) ofrecer carta sin tenerla → CARD_NOT_OWNED', ok);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
