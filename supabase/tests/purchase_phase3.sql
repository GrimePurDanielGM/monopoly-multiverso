-- ============================================================================
-- Compra con aprobación + subasta + bancarrota (Fase 3 corrección). Tras `supabase db reset`.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
drop table if exists _ctx; create temp table _ctx(k text primary key, v text);
grant select, insert, update, delete on _t, _ctx to authenticated;
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $f$
begin perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if; end $f$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $f$ begin perform set_config('role', session_user, true); end $f$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;
create or replace function pg_temp._ctx(k text) returns text language sql as $f$ select v from _ctx where k=$1 $f$;
create or replace function pg_temp._owner(gid uuid, ref text) returns text language sql security definer as $f$
  select owner_ref from public.property_ownership where game_id=gid and property_ref=ref and released_at is null $f$;
create or replace function pg_temp._ver(gid uuid) returns bigint language sql security definer as $f$
  select runtime_version from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._reconciles(p_gid uuid) returns boolean language sql security definer as $f$
  select not exists (select 1 from public.player_balances b where b.game_id=p_gid and b.balance <> (
    coalesce((select sum(amount) from public.ledger where game_id=p_gid and to_ref=b.player_ref),0)
    - coalesce((select sum(amount) from public.ledger where game_id=p_gid and from_ref=b.player_ref),0))); $f$;
-- Fase 4: solicitar compra exige ser el jugador actual Y estar en la casilla de esa propiedad.
-- Helper de test: el anfitrión pone el turno al solicitante y lo sitúa en la casilla de la propiedad.
create or replace function pg_temp._onprop(gid uuid, hostuid text, requ_uid text, prop text) returns void language plpgsql as $f$
declare bk text; ix int; ref text; begin
  perform pg_temp._as_admin();
  select board_key, space_index into bk, ix from public.board_spaces where property_ref=prop and active limit 1;
  select public_ref into ref from public.players where auth_uid=requ_uid::uuid and game_id=gid;
  perform pg_temp._as_user(hostuid);
  perform host_set_turn(gid, ref, 'turno para compra (test)', gen_random_uuid(), pg_temp._ver(gid));
  perform host_set_player_position(gid, ref, bk, ix, 'situar en la casilla (test)', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin();
end $f$;

create or replace function pg_temp._build3() returns void language plpgsql as $f$
declare host text:='aa000000-0000-0000-0000-0000000000a1';
        u text[]:=array['aa000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000002'];
        toks text[]:=array['cat','boot']; r jsonb; gid uuid; code text; v int; ref text; i int;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('PA IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  for i in 1..2 loop
    perform pg_temp._as_user(u[i]); perform join_game(code,'P'||i,gen_random_uuid());
    perform pg_temp._as_admin(); select public_ref into ref from players where game_id=gid and auth_uid=u[i]::uuid;
    insert into _ctx values ('p'||i,ref),('p'||i||'_uid',u[i]);
    perform pg_temp._as_user(u[i]); perform choose_token(gid,toks[i]); perform set_ready(gid,true);
  end loop;
  perform pg_temp._as_user(host); perform choose_token(gid,'thimble'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid, v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build3(); end $$;

-- A1) el cliente ya no puede comprar directamente (buy_property revocada).
do $$ declare ok boolean; begin
  perform pg_temp._as_admin();
  ok := not has_function_privilege('authenticated','public.buy_property(uuid,text,uuid,bigint)','execute');
  perform pg_temp._rec('A1) buy_property revocada a authenticated (no compra directa)', ok);
end $$;

-- A2) solicitar compra no cambia saldo ni propietario; el anfitrión la ve.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid');
            code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host'); bal bigint; own text; snap jsonb; seen boolean; begin
  perform pg_temp._onprop(gid, host, p1u, 'cl-ronda-valencia');
  perform pg_temp._as_user(p1u); perform request_property_purchase(gid,'cl-ronda-valencia',gen_random_uuid());
  perform pg_temp._as_admin(); select balance into bal from player_balances where game_id=gid and player_ref=p1;
  own := pg_temp._owner(gid,'cl-ronda-valencia');
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code);
  seen := exists(select 1 from jsonb_array_elements(snap->'purchase_requests') e where e->>'property_ref'='cl-ronda-valencia' and e->>'requester_ref'=p1);
  perform pg_temp._as_admin();
  perform pg_temp._rec('A2) solicitar compra: saldo intacto, sin propietario, host la ve', bal=3000 and own is null and seen);
end $$;

-- A3) el anfitrión aprueba -> compra efectiva (saldo baja, propietario, ledger).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); host text:=pg_temp._ctx('host');
            rref text; bal bigint; own text; nled int; begin
  perform pg_temp._as_admin(); select public_ref into rref from property_purchase_requests where game_id=gid and property_ref='cl-ronda-valencia' and status='pending';
  perform pg_temp._as_user(host); perform resolve_property_purchase(rref, true, pg_temp._ver(gid));
  perform pg_temp._as_admin();
  select balance into bal from player_balances where game_id=gid and player_ref=p1;
  own := pg_temp._owner(gid,'cl-ronda-valencia');
  select count(*) into nled from ledger where game_id=gid and kind='property_purchase' and from_ref=p1 and amount=60;
  perform pg_temp._rec('A3) aprobación: p1 propietario, saldo 2940, ledger property_purchase', own=p1 and bal=2940 and nled=1);
end $$;

-- A4) no-host no puede aprobar; propiedad ocupada no se puede volver a solicitar.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2u text:=pg_temp._ctx('p2_uid'); ok1 boolean:=false; ok2 boolean:=false; rref text; begin
  perform pg_temp._as_admin(); select public_ref into rref from property_purchase_requests where game_id=gid and property_ref='cl-ronda-valencia' limit 1;
  perform pg_temp._as_user(p2u);
  begin perform resolve_property_purchase(rref, true, pg_temp._ver(gid)); exception when others then ok1:=(sqlerrm='NOT_HOST'); end;
  perform pg_temp._onprop(gid, host, p2u, 'cl-ronda-valencia');  -- p2 actual y en la casilla, pero ya está ocupada
  perform pg_temp._as_user(p2u);
  begin perform request_property_purchase(gid,'cl-ronda-valencia',gen_random_uuid()); exception when others then ok2:=(sqlerrm='PROPERTY_ALREADY_OWNED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('A4) no-host no aprueba (NOT_HOST); ocupada no se solicita (ALREADY_OWNED)', ok1 and ok2);
end $$;

-- A5) idempotencia: misma request_id de solicitud no duplica.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2u text:=pg_temp._ctx('p2_uid'); rid uuid:=gen_random_uuid(); n int; begin
  perform pg_temp._onprop(gid, host, p2u, 'cl-alcala');
  perform pg_temp._as_user(p2u);
  perform request_property_purchase(gid,'cl-alcala',rid); perform request_property_purchase(gid,'cl-alcala',rid);
  perform pg_temp._as_admin(); select count(*) into n from property_purchase_requests where game_id=gid and property_ref='cl-alcala' and status='pending';
  perform pg_temp._rec('A5) idempotencia de solicitud de compra (sin duplicar)', n=1);
end $$;

-- ── Subasta ──
-- S1) host inicia subasta; pujas; puja baja bloqueada; cierre adjudica; saldo correcto.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref');
            p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); p2u text:=pg_temp._ctx('p2_uid'); p2 text:=pg_temp._ctx('p2');
            aref text; ok_low boolean:=false; own text; bal bigint; begin
  perform pg_temp._as_user(host); perform start_property_auction(gid,'cl-prado',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); select public_ref into aref from property_auctions where game_id=gid and property_ref='cl-prado' and status='active';
  insert into _ctx values ('auc',aref);
  perform pg_temp._as_user(p1u); perform place_property_bid(gid,aref,100,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p2u); perform place_property_bid(gid,aref,150,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u);
  begin perform place_property_bid(gid,aref,140,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok_low:=(sqlerrm='BID_TOO_LOW'); end;
  perform pg_temp._as_user(host); perform close_property_auction(gid,aref,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  own := pg_temp._owner(gid,'cl-prado'); select balance into bal from player_balances where game_id=gid and player_ref=p2;
  perform pg_temp._rec('S1) subasta: puja baja bloqueada, cierre adjudica al mayor (p2), cobra 150', ok_low and own=p2 and bal=3000-150);
end $$;

-- S2) no se puede solicitar compra de una propiedad en subasta activa.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1u text:=pg_temp._ctx('p1_uid'); aref text; ok boolean:=false; begin
  perform pg_temp._as_user(host); perform start_property_auction(gid,'cl-gran-via',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); select public_ref into aref from property_auctions where game_id=gid and property_ref='cl-gran-via' and status='active';
  perform pg_temp._onprop(gid, host, p1u, 'cl-gran-via');  -- p1 actual y en la casilla, pero está en subasta
  perform pg_temp._as_user(p1u);
  begin perform request_property_purchase(gid,'cl-gran-via',gen_random_uuid()); exception when others then ok:=(sqlerrm='PROPERTY_IN_AUCTION'); end;
  -- cancelar deja disponible
  perform pg_temp._as_user(host); perform cancel_property_auction(gid,aref,'test',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('S2) compra bloqueada con subasta activa (PROPERTY_IN_AUCTION); cancelar deja disponible', ok and exists(select 1 from property_auctions where public_ref=aref and status='cancelled'));
end $$;

-- ── Bancarrota ──
-- B1) bancarrota a jugador: dinero y propiedades pasan al acreedor; deudor espectador.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2');
            rref text; p1bal_before bigint; p2bal_before bigint; p2bal_after bigint; own text; spectator boolean; in_order boolean; begin
  perform pg_temp._as_admin();
  select balance into p1bal_before from player_balances where game_id=gid and player_ref=p1;
  select balance into p2bal_before from player_balances where game_id=gid and player_ref=p2;
  -- p1 posee cl-ronda-valencia (comprada en A3)
  perform pg_temp._as_user(p1u); perform request_bankruptcy(gid,'to_player',p2,'me arruino',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into rref from bankruptcy_requests where game_id=gid and requester_ref=p1 and status='pending';
  perform pg_temp._as_user(host); perform resolve_bankruptcy(rref, true, pg_temp._ver(gid));
  perform pg_temp._as_admin();
  select balance into p2bal_after from player_balances where game_id=gid and player_ref=p2;
  own := pg_temp._owner(gid,'cl-ronda-valencia');
  select bankrupt_at is not null into spectator from players where game_id=gid and public_ref=p1;
  select p1 = any(turn_order_refs) into in_order from game_runtime where game_id=gid;
  perform pg_temp._rec('B1) bancarrota a jugador: dinero+propiedad al acreedor, deudor espectador y fuera del orden',
    own=p2 and p2bal_after = p2bal_before + p1bal_before and spectator and not in_order);
end $$;

-- B2) el jugador en bancarrota no puede actuar, pero sí consultar el snapshot.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); p1u text:=pg_temp._ctx('p1_uid'); p1 text:=pg_temp._ctx('p1');
            ok_block boolean:=false; snap jsonb; my_status text; begin
  perform pg_temp._as_user(p1u);
  begin perform request_property_purchase(gid,'cl-bailen',gen_random_uuid()); exception when others then ok_block:=(sqlerrm='NOT_ACTIVE_MEMBER'); end;
  snap := get_active_snapshot_by_code(code);  -- el espectador SÍ puede leer
  my_status := snap->'me'->>'is_spectator';
  perform pg_temp._as_admin();
  perform pg_temp._rec('B2) espectador: no actúa (NOT_ACTIVE_MEMBER) pero consulta snapshot (is_spectator)', ok_block and my_status='true');
end $$;

-- B3) reconciliación monetaria intacta tras todo.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; begin
  perform pg_temp._as_admin();
  perform pg_temp._rec('B3) reconciliación monetaria intacta (compra+subasta+bancarrota)', pg_temp._reconciles(gid));
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── purchase_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
