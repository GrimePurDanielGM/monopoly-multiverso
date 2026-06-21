-- ============================================================================
-- Fase 7 — Ejecución atómica e invalidaciones de tratos.
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

-- E1) invalidación: tras pasar a host_review, p1 deja de ser dueño → host aprueba → invalidated, nada cambia.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2u text:=pg_temp._ctx('p2_uid'); host text:=pg_temp._ctx('host_uid'); p1 text:=pg_temp._ctx('p1'); r jsonb; t text; begin
  perform pg_temp._as_user(p1u); r := create_trade_proposal(gid, pg_temp._ctx('p2'), 0, 100, array['cl-ronda-valencia'], null, null, null, null, gen_random_uuid()); t:=r->>'trade_ref';
  perform pg_temp._as_user(p2u); perform accept_trade_proposal(t, pg_temp._ver(gid), gen_random_uuid());
  perform pg_temp._as_admin(); update public.property_ownership set released_at=now() where game_id=gid and property_ref='cl-ronda-valencia' and released_at is null;  -- p1 ya no es dueño
  perform pg_temp._as_user(host); r := resolve_trade_proposal(t, true, pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('E1) estado cambiado al aprobar → invalidated (sin ejecutar)', (r->>'status')='invalidated' and pg_temp._tstatus(gid,t)='invalidated' and pg_temp._ownerof(gid,'cl-ronda-valencia') is null);
  perform pg_temp._reown(gid,'cl-ronda-valencia',p1);  -- restaurar para los siguientes tests
end $$;
-- E2) ejecución atómica: dinero + propiedad cambian a la vez.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2u text:=pg_temp._ctx('p2_uid'); host text:=pg_temp._ctx('host_uid'); p1 text:=pg_temp._ctx('p1'); p2 text:=pg_temp._ctx('p2'); r jsonb; t text; b1 bigint; b2 bigint; begin
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,p1); b2:=pg_temp._bal(gid,p2);
  perform pg_temp._as_user(p1u); r := create_trade_proposal(gid, p2, 200, 0, array['cl-ronda-valencia'], null, null, null, null, gen_random_uuid()); t:=r->>'trade_ref';  -- p1 da Ronda + 200
  perform pg_temp._as_user(p2u); perform accept_trade_proposal(t, pg_temp._ver(gid), gen_random_uuid());
  perform pg_temp._as_user(host); r := resolve_trade_proposal(t, true, pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('E2) ejecución atómica: dinero y propiedad juntos', (r->>'status')='executed' and pg_temp._ownerof(gid,'cl-ronda-valencia')=p2 and pg_temp._bal(gid,p1)=b1-200 and pg_temp._bal(gid,p2)=b2+200);
  perform pg_temp._reown(gid,'cl-ronda-valencia',p1);
end $$;
-- E3) carta usada/retirada antes de ejecutar → invalidated.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2u text:=pg_temp._ctx('p2_uid'); host text:=pg_temp._ctx('host_uid'); p1 text:=pg_temp._ctx('p1'); r jsonb; t text; begin
  perform pg_temp._as_admin(); perform pg_temp._givecard(gid, p1, 'past-jail-free');
  perform pg_temp._as_user(p1u); r := create_trade_proposal(gid, pg_temp._ctx('p2'), 0, 0, null, null, array['past-jail-free'], null, null, gen_random_uuid()); t:=r->>'trade_ref';
  perform pg_temp._as_user(p2u); perform accept_trade_proposal(t, pg_temp._ver(gid), gen_random_uuid());
  perform pg_temp._as_admin(); delete from public.game_held_cards where game_id=gid and player_ref=p1 and card_ref='past-jail-free';  -- carta ya no está
  perform pg_temp._as_user(host); r := resolve_trade_proposal(t, true, pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('E3) carta retirada antes de ejecutar → invalidated', (r->>'status')='invalidated');
end $$;
-- E4) saldo insuficiente al ejecutar → invalidated.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2u text:=pg_temp._ctx('p2_uid'); host text:=pg_temp._ctx('host_uid'); p1 text:=pg_temp._ctx('p1'); r jsonb; t text; begin
  perform pg_temp._as_user(p1u); r := create_trade_proposal(gid, pg_temp._ctx('p2'), 5000, 0, array['cl-ronda-valencia'], null, null, null, null, gen_random_uuid()); t:=r->>'trade_ref';
  perform pg_temp._as_user(p2u); perform accept_trade_proposal(t, pg_temp._ver(gid), gen_random_uuid());
  perform pg_temp._as_admin(); update public.player_balances set balance=10 where game_id=gid and player_ref=p1;  -- p1 sin saldo
  perform pg_temp._as_user(host); r := resolve_trade_proposal(t, true, pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('E4) sin saldo al ejecutar → invalidated', (r->>'status')='invalidated' and pg_temp._ownerof(gid,'cl-ronda-valencia')=p1);
  update public.player_balances set balance=100000 where game_id=gid;
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
