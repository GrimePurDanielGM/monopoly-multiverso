-- ============================================================================
-- Fase 7 (A2 + A3) — Tratos con propiedades hipotecadas y/o construidas.
-- Tras `supabase db reset`. Setup: partida activa host(H)/p1/p2; p1 posee Ronda (calle), p2 la estación de Goya.
-- A3: la hipoteca (y casas/hotel) deben CONSERVARSE al transferir por trato (no las resetea el trigger de release).
-- A2: opción allow_trade_built_properties — OFF bloquea propiedades construidas; ON permite y conserva construcciones.
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
create or replace function pg_temp._gver(gid uuid) returns int language sql security definer as $f$ select version from public.games where id=gid $f$;
create or replace function pg_temp._own(gid uuid, prop text, ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,ref) on conflict do nothing $f$;
create or replace function pg_temp._reown(gid uuid, prop text, ref text) returns void language sql security definer as $f$
  with rel as (update public.property_ownership set released_at=now(), released_reason='test' where game_id=gid and property_ref=prop and released_at is null returning 1)
  insert into public.property_ownership(game_id,property_ref,owner_ref) select gid,prop,ref from (select 1) s left join rel on true $f$;
create or replace function pg_temp._tstatus(gid uuid, tref text) returns text language sql security definer as $f$
  select status::text from public.game_trade_proposals where game_id=gid and public_ref=tref $f$;
create or replace function pg_temp._ownerof(gid uuid, prop text) returns text language sql security definer as $f$
  select owner_ref from public.property_ownership where game_id=gid and property_ref=prop and released_at is null $f$;
-- estado de construcción/hipoteca
create or replace function pg_temp._mortof(gid uuid, prop text) returns boolean language sql security definer as $f$
  select coalesce((select mortgaged from public.game_property_state where game_id=gid and property_ref=prop), false) $f$;
create or replace function pg_temp._housesof(gid uuid, prop text) returns int language sql security definer as $f$
  select coalesce((select houses from public.game_property_state where game_id=gid and property_ref=prop), 0) $f$;
create or replace function pg_temp._hotelof(gid uuid, prop text) returns boolean language sql security definer as $f$
  select coalesce((select has_hotel from public.game_property_state where game_id=gid and property_ref=prop), false) $f$;
create or replace function pg_temp._clearstate(gid uuid, prop text) returns void language sql security definer as $f$
  delete from public.game_property_state where game_id=gid and property_ref=prop $f$;
create or replace function pg_temp._sethouses(gid uuid, prop text, n int) returns void language sql security definer as $f$
  insert into public.game_property_state(game_id,property_ref,houses,has_hotel,mortgaged) values (gid,prop,n,false,false)
    on conflict (game_id,property_ref) do update set houses=n, has_hotel=false $f$;
create or replace function pg_temp._sethotel(gid uuid, prop text) returns void language sql security definer as $f$
  insert into public.game_property_state(game_id,property_ref,houses,has_hotel,mortgaged) values (gid,prop,0,true,false)
    on conflict (game_id,property_ref) do update set houses=0, has_hotel=true $f$;
create or replace function pg_temp._optbuilt(gid uuid, on_ boolean) returns void language sql security definer as $f$
  update public.games set config = config || jsonb_build_object('allow_trade_built_properties', on_) where id=gid $f$;
create or replace function pg_temp._stockh(gid uuid) returns int language sql security definer as $f$ select houses_available from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._stockt(gid uuid) returns int language sql security definer as $f$ select hotels_available from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._rentdue(gid uuid, prop text) returns int language sql security definer as $f$ select public._p6_rent_due(gid,prop) $f$;
create or replace function pg_temp._catrent(prop text, col text) returns int language plpgsql security definer as $f$
declare v int; begin execute format('select %I from public.property_catalog where property_ref=$1', col) into v using prop; return v; end $f$;
-- crea+acepta+aprueba un trato de p1 ofreciendo `props` a p2 (requiere anfitrión). Devuelve el estado final.
create or replace function pg_temp._dotrade(gid uuid, props text[]) returns text language plpgsql as $f$
declare p1u text:=pg_temp._ctx('p1_uid'); p2u text:=pg_temp._ctx('p2_uid'); host text:=pg_temp._ctx('host_uid'); p2 text:=pg_temp._ctx('p2'); r jsonb; t text; begin
  perform pg_temp._as_user(p1u); r:=create_trade_proposal(gid, p2, 0, 0, props, null, null, null, null, gen_random_uuid()); t:=r->>'trade_ref';
  perform pg_temp._as_user(p2u); perform accept_trade_proposal(t, pg_temp._ver(gid), gen_random_uuid());
  perform pg_temp._as_user(host); r:=resolve_trade_proposal(t, true, pg_temp._ver(gid));
  perform pg_temp._as_admin(); return r->>'status'; end $f$;
create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='f9000000-0000-0000-0000-0000000000a1'; j1 text:='f9000000-0000-0000-0000-000000000001';
        j2 text:='f9000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Tratos A2A3','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- ── A3) HIPOTECA conservada al transferir ─────────────────────────────────────
-- A3a) p1 hipoteca Ronda (RPC real).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); begin
  perform pg_temp._as_user(p1u); perform mortgage_property(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid)); perform pg_temp._as_admin();
  perform pg_temp._rec('A3a) hipotecar Ronda → mortgaged=true', pg_temp._mortof(gid,'cl-ronda-valencia'));
end $$;
-- A3b) trato p1→p2 con la propiedad hipotecada → ejecutado, nuevo dueño p2, sigue hipotecada, no genera alquiler.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p2 text:=pg_temp._ctx('p2'); st text; begin
  st := pg_temp._dotrade(gid, array['cl-ronda-valencia']);
  perform pg_temp._rec('A3b) trato ejecuta: nuevo dueño p2, mortgaged conservada, alquiler 0',
    st='executed' and pg_temp._ownerof(gid,'cl-ronda-valencia')=p2 and pg_temp._mortof(gid,'cl-ronda-valencia') and pg_temp._rentdue(gid,'cl-ronda-valencia')=0);
end $$;
-- A3c) p2 (nuevo dueño) deshipoteca → desde entonces sí genera alquiler (base_rent, calle suelta).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p2u text:=pg_temp._ctx('p2_uid'); rd int; base int; begin
  perform pg_temp._as_user(p2u); perform unmortgage_property(gid,'cl-ronda-valencia',gen_random_uuid(),pg_temp._ver(gid)); perform pg_temp._as_admin();
  rd := pg_temp._rentdue(gid,'cl-ronda-valencia'); base := pg_temp._catrent('cl-ronda-valencia','base_rent');
  perform pg_temp._rec('A3c) deshipotecar → mortgaged=false y alquiler>0 (=base_rent)',
    not pg_temp._mortof(gid,'cl-ronda-valencia') and rd>0 and rd=base);
  -- restaurar: Ronda vuelve a p1, estado limpio.
  perform pg_temp._reown(gid,'cl-ronda-valencia',pg_temp._ctx('p1')); perform pg_temp._clearstate(gid,'cl-ronda-valencia');
end $$;

-- ── A2) Propiedades CONSTRUIDAS según configuración ───────────────────────────
-- A2a) opción OFF (default): Ronda con 2 casas NO puede entrar en trato.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); ok boolean; begin
  perform pg_temp._optbuilt(gid,false); perform pg_temp._sethouses(gid,'cl-ronda-valencia',2);
  begin
    perform pg_temp._as_user(p1u);
    perform create_trade_proposal(gid, p2, 0, 0, array['cl-ronda-valencia'], null, null, null, null, gen_random_uuid());
    ok := false;
  exception when others then ok := (sqlerrm = 'PROPERTY_HAS_BUILDINGS');
  end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('A2a) OFF: propiedad con casas no entra en trato (PROPERTY_HAS_BUILDINGS)', ok);
end $$;
-- A2b) opción ON: Ronda con 2 casas sí entra; al ejecutar el nuevo dueño conserva las casas y el stock no cambia.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p2 text:=pg_temp._ctx('p2'); st text; h0 int; t0 int; begin
  perform pg_temp._optbuilt(gid,true);
  h0 := pg_temp._stockh(gid); t0 := pg_temp._stockt(gid);
  st := pg_temp._dotrade(gid, array['cl-ronda-valencia']);
  perform pg_temp._rec('A2b) ON: trato con casas ejecuta; nuevo dueño conserva 2 casas; stock intacto',
    st='executed' and pg_temp._ownerof(gid,'cl-ronda-valencia')=p2 and pg_temp._housesof(gid,'cl-ronda-valencia')=2
    and pg_temp._stockh(gid)=h0 and pg_temp._stockt(gid)=t0);
end $$;
-- A2c) alquiler avanzado tras la transferencia usa el nuevo propietario y las casas conservadas (= rent_2).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p2 text:=pg_temp._ctx('p2'); rd int; r2 int; begin
  rd := pg_temp._rentdue(gid,'cl-ronda-valencia'); r2 := pg_temp._catrent('cl-ronda-valencia','rent_2');
  perform pg_temp._rec('A2c) alquiler tras transferir = rent_2 (casas conservadas, dueño p2)',
    pg_temp._ownerof(gid,'cl-ronda-valencia')=p2 and rd=r2 and rd>0);
  perform pg_temp._reown(gid,'cl-ronda-valencia',pg_temp._ctx('p1')); perform pg_temp._clearstate(gid,'cl-ronda-valencia');
end $$;
-- A2d) HOTEL: ON, Ronda con hotel → trato ejecuta, hotel conservado, alquiler = rent_hotel, stock intacto.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p2 text:=pg_temp._ctx('p2'); st text; h0 int; t0 int; rd int; rh int; begin
  perform pg_temp._optbuilt(gid,true); perform pg_temp._sethotel(gid,'cl-ronda-valencia');
  h0 := pg_temp._stockh(gid); t0 := pg_temp._stockt(gid);
  st := pg_temp._dotrade(gid, array['cl-ronda-valencia']);
  rd := pg_temp._rentdue(gid,'cl-ronda-valencia'); rh := pg_temp._catrent('cl-ronda-valencia','rent_hotel');
  perform pg_temp._rec('A2d) ON: hotel se conserva, alquiler=rent_hotel, stock intacto',
    st='executed' and pg_temp._hotelof(gid,'cl-ronda-valencia') and pg_temp._housesof(gid,'cl-ronda-valencia')=0
    and rd=rh and pg_temp._stockh(gid)=h0 and pg_temp._stockt(gid)=t0);
  perform pg_temp._reown(gid,'cl-ronda-valencia',pg_temp._ctx('p1')); perform pg_temp._clearstate(gid,'cl-ronda-valencia');
end $$;
-- A2e) el snapshot expone la configuración allow_trade_built_properties.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host_uid'); snap jsonb; begin
  perform pg_temp._optbuilt(gid,true);
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(pg_temp._ctx('code')); perform pg_temp._as_admin();
  perform pg_temp._rec('A2e) snapshot expone allow_trade_built_properties=true',
    (snap->'game'->'config'->>'allow_trade_built_properties')::boolean = true);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
