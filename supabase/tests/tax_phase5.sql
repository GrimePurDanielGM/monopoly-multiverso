-- ============================================================================
-- Impuestos (Fase 5): caer en una casilla de impuesto cobra a la banca y alimenta el bote de Parking;
-- el bote respeta el tope 2.500; si no hay saldo, queda pago pendiente (no bloquea el movimiento). Tras `db reset`.
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
create or replace function pg_temp._pot(gid uuid) returns bigint language sql security definer as $f$ select parking_pot from public.game_runtime where game_id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='ad000000-0000-0000-0000-0000000000a1'; j1 text:='ad000000-0000-0000-0000-000000000001';
        j2 text:='ad000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Tax IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- T1) caer en Impuesto sobre el capital (classic idx 4 = 200): cobra 200 y el saldo baja.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; b1 bigint; snap jsonb; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',3,'antes de impuesto',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,cur);
  perform pg_temp._rec('T1) impuesto capital cobra 200 (saldo -200) y last_move.effect=tax',
    b1 = b0 - 200 and (snap->'last_move'->'effect'->>'type')='tax' and (snap->'last_move'->'effect'->>'amount')='200');
end $$;

-- T2) el asiento ledger tax_payment existe (jugador -> banca, importe 200).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; n int; begin
  perform pg_temp._as_admin(); cur:=pg_temp._cur(gid);
  select count(*) into n from public.ledger where game_id=gid and kind='tax_payment' and from_ref=cur and to_ref is null and amount=200;
  perform pg_temp._rec('T2) ledger tax_payment (jugador→banca, 200)', n>=1);
end $$;

-- T3) el impuesto alimenta el bote de Parking (pot = 200 tras el primer impuesto).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; begin
  perform pg_temp._as_admin();
  perform pg_temp._rec('T3) el impuesto alimenta el bote (parking_pot = 200)', pg_temp._pot(gid) = 200);
end $$;

-- T4) un segundo impuesto (lujo, idx 38 = 100) suma al bote (200+100 = 300).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',37,'antes de lujo',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('T4) impuesto de lujo (100) suma al bote (pot = 300)', pg_temp._pot(gid) = 300);
end $$;

-- T5) el bote respeta el tope 2.500 (el excedente no se acumula).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; begin
  perform pg_temp._as_admin();
  -- fuerza el bote cerca del tope y añade un impuesto grande vía el helper interno.
  update public.game_runtime set parking_pot = 2450 where game_id=gid;
  perform public._p5_pot_add(gid, 200);   -- 2450+200=2650 → capado a 2500
  perform pg_temp._rec('T5) el bote respeta el tope 2.500 (excedente a banca)', pg_temp._pot(gid) = 2500);
end $$;

-- T6) impuesto sin saldo suficiente: no bloquea el movimiento; queda pago pendiente.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2 text:=pg_temp._ctx('p2'); p2u text:=pg_temp._ctx('p2_uid');
            cur text; snap jsonb; okmove boolean; okpend boolean; begin
  -- pone a P2 en turno, le deja poco saldo y lo coloca antes del impuesto de lujo (100).
  perform pg_temp._as_user(host); perform host_set_turn(gid,p2,'prueba impuesto sin saldo',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform host_adjust_balance(gid,p2,50,'dejar poco saldo',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p2,'classic',37,'antes de lujo',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p2u); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));   -- no debe lanzar
  perform pg_temp._as_user(p2u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  okmove := (snap->'my_position'->>'space_index')='38';                 -- sí se movió a la casilla
  okpend := (snap->'pending_payment'->>'kind')='tax' and (snap->'pending_payment'->>'amount')='100';
  perform pg_temp._rec('T6) impuesto sin saldo: se mueve pero deja pago pendiente (no bloquea)', okmove and okpend);
end $$;

-- T7) pay_pending no se puede si no llega; tras darle saldo, paga y limpia el pendiente.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2 text:=pg_temp._ctx('p2'); p2u text:=pg_temp._ctx('p2_uid');
            snap jsonb; okfail boolean:=false; okpaid boolean; begin
  perform pg_temp._as_user(p2u);
  begin perform pay_pending(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okfail:=(sqlerrm='INSUFFICIENT_FUNDS'); end;
  perform pg_temp._as_user(host); perform host_adjust_balance(gid,p2,500,'dar saldo',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p2u); perform pay_pending(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p2u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  okpaid := snap->'pending_payment' = 'null'::jsonb or snap->'pending_payment' is null;
  perform pg_temp._rec('T7) pay_pending: falla sin saldo (INSUFFICIENT_FUNDS) y paga al tenerlo', okfail and okpaid);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── tax_phase5: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
