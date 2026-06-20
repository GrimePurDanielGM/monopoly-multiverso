-- ============================================================================
-- Fase 6 — Hipotecas: dan dinero; bloquean alquiler; no se hipoteca con construcciones; no se construye
-- en un grupo con hipoteca; deshipotecar paga hipoteca+10%. Tras `db reset`.
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
create or replace function pg_temp._own(gid uuid, prop text, owner_ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,owner_ref) on conflict do nothing $f$;
create or replace function pg_temp._land(gid uuid) returns void language sql security definer as $f$ update public.game_runtime set landing_seq=landing_seq+1 where game_id=gid $f$;
create or replace function pg_temp._mort(gid uuid, prop text) returns boolean language sql security definer as $f$ select coalesce((select mortgaged from public.game_property_state where game_id=gid and property_ref=prop),false) $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='f3000000-0000-0000-0000-0000000000a1'; j1 text:='f3000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Mort IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code'; href:=r->>'host_public_ref';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',href),('host_uid',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v);
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-ronda-valencia',href); perform pg_temp._own(gid,'cl-plaza-lavapies',href);
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- M1) hipotecar da dinero (30) y marca mortgaged; ledger mortgage_received.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); b0 bigint; b1 bigint; nled int; begin
  perform pg_temp._as_admin(); select balance into b0 from public.player_balances where game_id=gid and player_ref=href;
  perform pg_temp._as_user(host); perform mortgage_property(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); select balance into b1 from public.player_balances where game_id=gid and player_ref=href;
  select count(*) into nled from public.ledger where game_id=gid and kind='mortgage_received';
  perform pg_temp._rec('M1) hipotecar da 30, mortgaged=true, ledger mortgage_received', b1-b0=30 and pg_temp._mort(gid,'cl-ronda-valencia') and nled=1);
end $$;

-- M6a) hipotecar otra vez → ALREADY_MORTGAGED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host);
  begin perform mortgage_property(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='ALREADY_MORTGAGED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('M6a) re-hipotecar → ALREADY_MORTGAGED', ok);
end $$;

-- M3) hipotecada no cobra alquiler: p1 paga sobre la calle hipotecada → NO_RENT_DUE.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); ok boolean:=false; begin
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  perform pg_temp._as_user(p1u);
  begin perform pay_rent(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='NO_RENT_DUE'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('M3) calle hipotecada no cobra alquiler (NO_RENT_DUE)', ok);
end $$;

-- M4) no se puede construir si el grupo tiene una hipoteca (GROUP_HAS_MORTGAGE).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host);
  begin perform build_house(gid,'cl-plaza-lavapies',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='GROUP_HAS_MORTGAGE'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('M4) construir con hipoteca en el grupo → GROUP_HAS_MORTGAGE', ok);
end $$;

-- M5) deshipotecar paga hipoteca+10% (30→33); ledger unmortgage_payment; mortgaged=false.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); b0 bigint; b1 bigint; nled int; begin
  perform pg_temp._as_admin(); select balance into b0 from public.player_balances where game_id=gid and player_ref=href;
  perform pg_temp._as_user(host); perform unmortgage_property(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); select balance into b1 from public.player_balances where game_id=gid and player_ref=href;
  select count(*) into nled from public.ledger where game_id=gid and kind='unmortgage_payment';
  perform pg_temp._rec('M5) deshipotecar paga 33 (30+10%), mortgaged=false, ledger unmortgage_payment',
    b0-b1=33 and not pg_temp._mort(gid,'cl-ronda-valencia') and nled=1);
end $$;

-- M6b) deshipotecar una no hipotecada → NOT_MORTGAGED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host);
  begin perform unmortgage_property(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='NOT_MORTGAGED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('M6b) deshipotecar no hipotecada → NOT_MORTGAGED', ok);
end $$;

-- M2) no se puede hipotecar con construcciones en el grupo (HAS_BUILDINGS).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host); perform build_house(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid)); -- 1 casa en el grupo
  begin perform mortgage_property(gid,'cl-plaza-lavapies',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='HAS_BUILDINGS'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('M2) hipotecar con construcciones en el grupo → HAS_BUILDINGS', ok);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
