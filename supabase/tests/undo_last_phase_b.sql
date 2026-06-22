-- ============================================================================
-- Bug B — host_undo_last: deshacer la última acción (dinero + estado). Tras `db reset`.
-- Cubre: dinero puro, compra de propiedad (libera posesión), construir casa (casas+stock),
-- hipotecar (flag + dinero), deshacer secuencial, y guardas (NOT_HOST, REASON_REQUIRED).
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
create or replace function pg_temp._own(gid uuid, prop text, owner_ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,owner_ref) on conflict do nothing $f$;
create or replace function pg_temp._houses(gid uuid, prop text) returns int language sql security definer as $f$
  select coalesce((select houses from public.game_property_state where game_id=gid and property_ref=prop),0) $f$;
create or replace function pg_temp._mort(gid uuid, prop text) returns boolean language sql security definer as $f$
  select coalesce((select mortgaged from public.game_property_state where game_id=gid and property_ref=prop),false) $f$;
create or replace function pg_temp._stock(gid uuid) returns int language sql security definer as $f$
  select houses_available from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._active_owner(gid uuid, prop text) returns text language sql security definer as $f$
  select owner_ref from public.property_ownership where game_id=gid and property_ref=prop and released_at is null $f$;
create or replace function pg_temp._bld(gid uuid, owner_uid text, host_uid text, prop text, action text) returns jsonb language plpgsql as $f$
declare rref text; r jsonb; begin
  perform pg_temp._as_user(owner_uid);
  rref := (case action when 'build_house' then request_build_house(gid, prop, gen_random_uuid())
                       when 'sell_house'  then request_sell_house(gid, prop, gen_random_uuid()) end)->>'request_ref';
  perform pg_temp._as_user(host_uid); r := resolve_building_request(rref, true, pg_temp._ver(gid));
  perform pg_temp._as_admin(); return r;
end $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='c1000000-0000-0000-0000-0000000000a1'; j1 text:='c1000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Undo IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code'; href:=r->>'host_public_ref';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',href),('host_uid',host),('p1_uid',j1);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
  -- una propiedad comprable cualquiera (no marrón) para la prueba de compra
  insert into _ctx select 'buyprop', property_ref from public.property_catalog
    where active and is_buyable and kind='street' and property_ref not in ('cl-ronda-valencia','cl-plaza-lavapies')
    order by property_ref limit 1;
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- U1) deshacer dinero puro: el banco da 500 a p1 → host_undo_last lo restaura y enlaza la compensación.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1');
            v_ver bigint; b0 bigint; b1 bigint; v_link int; lref text; begin
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,p1); v_ver:=pg_temp._ver(gid);
  perform pg_temp._as_user(host); perform bank_transfer(gid, p1, 'to_player', 500, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select ledger_ref into lref from ledger where game_id=gid and kind='bank_to_player' and to_ref=p1 and amount=500 order by seq desc limit 1;
  perform pg_temp._as_user(host); perform host_undo_last(gid, 'deshacer', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,p1);
  select count(*) into v_link from ledger where game_id=gid and kind='host_revert' and reverts_ledger_id=(select id from ledger where game_id=gid and ledger_ref=lref);
  perform pg_temp._rec('U1) dinero puro: saldo restaurado + compensación enlazada', b1=b0 and v_link=1);
end $$;

-- U2) deshacer compra: p1 compra una propiedad (vía el mismo helper que resolve_property_purchase);
--     host_undo_last libera la posesión (acquired_by_ledger_ref) y le devuelve el dinero.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1');
            prop text:=pg_temp._ctx('buyprop'); price bigint; b0 bigint; b1 bigint; bbuy bigint; begin
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,p1);
  select coalesce(c.price,1) into price from public.property_catalog c where c.property_ref=prop;
  perform public._p3_assign_property(gid, prop, p1, price, 'property_purchase', gen_random_uuid());  -- compra real (último asiento = property_purchase)
  bbuy:=pg_temp._bal(gid,p1);
  perform pg_temp._as_user(host); perform host_undo_last(gid, 'compra por error', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,p1);
  perform pg_temp._rec('U2) compra: posesión liberada + dinero devuelto',
    pg_temp._active_owner(gid,prop) is null and bbuy=b0-price and b1=b0);
end $$;

-- U3) deshacer construcción de casa: el host (monopolio marrón) construye 1 casa; host_undo_last la quita y repone stock+dinero.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref');
            b0 bigint; b1 bigint; st0 int; begin
  perform pg_temp._as_admin();
  perform pg_temp._own(gid,'cl-ronda-valencia',href); perform pg_temp._own(gid,'cl-plaza-lavapies',href); -- monopolio marrón
  b0:=pg_temp._bal(gid,href); st0:=pg_temp._stock(gid);
  perform pg_temp._bld(gid, host, host, 'cl-ronda-valencia', 'build_house');  -- casas=1, stock-1, paga 50
  perform pg_temp._as_user(host); perform host_undo_last(gid, 'construccion por error', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,href);
  perform pg_temp._rec('U3) casa: casas=0, stock repuesto, dinero devuelto',
    pg_temp._houses(gid,'cl-ronda-valencia')=0 and pg_temp._stock(gid)=st0 and b1=b0);
end $$;

-- U4) deshacer hipoteca: el host hipoteca una calle; host_undo_last revierte el flag y recupera el dinero recibido.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref');
            b0 bigint; b1 bigint; begin
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,href);  -- host ya posee ronda+lavapies (sin construcciones tras U3)
  perform pg_temp._as_user(host); perform mortgage_property(gid, 'cl-ronda-valencia', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._as_user(host); perform host_undo_last(gid, 'hipoteca por error', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,href);
  perform pg_temp._rec('U4) hipoteca: mortgaged=false + dinero recuperado',
    pg_temp._mort(gid,'cl-ronda-valencia')=false and b1=b0);
end $$;

-- U5) guardas: un no-anfitrión no puede (NOT_HOST); motivo vacío -> REASON_REQUIRED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1u text:=pg_temp._ctx('p1_uid');
            okh boolean:=false; okr boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform host_undo_last(gid, 'intento', gen_random_uuid(), pg_temp._ver(gid)); exception when others then okh:=(sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_user(host);
  begin perform host_undo_last(gid, ' ', gen_random_uuid(), pg_temp._ver(gid)); exception when others then okr:=(sqlerrm='REASON_REQUIRED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('U5) guardas: NOT_HOST + REASON_REQUIRED', okh and okr);
end $$;

-- U6) deshacer secuencial: dos pagos del banco; dos undos restauran ambos en orden inverso.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1');
            b0 bigint; bmid bigint; bend bigint; begin
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,p1);
  perform pg_temp._as_user(host); perform bank_transfer(gid, p1, 'to_player', 100, gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform bank_transfer(gid, p1, 'to_player', 200, gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin(); bmid:=pg_temp._bal(gid,p1);   -- b0 + 300
  perform pg_temp._as_user(host); perform host_undo_last(gid, 'undo 200', gen_random_uuid(), pg_temp._ver(gid)); -- quita el de 200
  perform pg_temp._as_user(host); perform host_undo_last(gid, 'undo 100', gen_random_uuid(), pg_temp._ver(gid)); -- quita el de 100
  perform pg_temp._as_admin(); bend:=pg_temp._bal(gid,p1);
  perform pg_temp._rec('U6) secuencial: dos undos vuelven al saldo inicial', bmid=b0+300 and bend=b0);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
