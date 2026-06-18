-- ============================================================================
-- Alquiler básico (Fase 3): pago al propietario, no a uno mismo, sin fondos,
-- ledger rent_payment, idempotencia, pausa/finalización. Tras `supabase db reset`.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
drop table if exists _ctx; create temp table _ctx(k text primary key, v text);
grant select, insert, update, delete on _t, _ctx to authenticated;
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if;
end $f$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $f$
begin perform set_config('role', session_user, true); end $f$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;
create or replace function pg_temp._ctx(k text) returns text language sql as $f$ select v from _ctx where k=$1 $f$;

create or replace function pg_temp._build2() returns void language plpgsql as $f$
declare host text:='e0000000-0000-0000-0000-0000000000a1'; j1 text:='e0000000-0000-0000-0000-000000000001';
        r jsonb; gid uuid; code text; v_ver int; ref text;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Rent IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid; code := r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v_ver);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1',ref),('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid, v_ver);
  perform pg_temp._as_admin();
end $f$;

do $$ begin perform pg_temp._build2(); end $$;

-- P1 compra cl-estacion-1 (200, alquiler 25).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1_uid text:=pg_temp._ctx('p1_uid'); v_ver bigint; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(p1_uid); perform buy_property(gid,'cl-estacion-1',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin();
end $$;

-- R1) el propietario no paga alquiler de su propia propiedad -> SELF_RENT.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1_uid text:=pg_temp._ctx('p1_uid'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(p1_uid);
  begin perform pay_rent(gid,'cl-estacion-1',gen_random_uuid(),v_ver); exception when others then ok:=(sqlerrm='SELF_RENT'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('R1) no pagar alquiler de la propia propiedad -> SELF_RENT', ok);
end $$;

-- R2..R3) el host paga alquiler a P1: P1 +25, host -25, ledger rent_payment.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref');
            p1 text:=pg_temp._ctx('p1'); v_ver bigint; hb bigint; pb bigint; nled int; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform pay_rent(gid,'cl-estacion-1',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin();
  select balance into hb from player_balances where game_id=gid and player_ref=host_ref;
  select balance into pb from player_balances where game_id=gid and player_ref=p1;
  select count(*) into nled from ledger where game_id=gid and kind='rent_payment' and from_ref=host_ref and to_ref=p1 and amount=25;
  perform pg_temp._rec('R2) pago de alquiler: host -25 (2975), propietario +25 (2825)', hb=2975 and pb=2825);
  perform pg_temp._rec('R3) ledger rent_payment registrado (host->P1, 25)', nled=1);
end $$;

-- R4) sin fondos no se paga alquiler -> INSUFFICIENT_FUNDS (no deja saldo negativo).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref');
            v_ver bigint; ok boolean:=false; bal bigint; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_adjust_balance(gid, host_ref, 10, 'bajar saldo', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform pay_rent(gid,'cl-estacion-1',gen_random_uuid(),v_ver); exception when others then ok:=(sqlerrm='INSUFFICIENT_FUNDS'); end;
  perform pg_temp._as_admin(); select balance into bal from player_balances where game_id=gid and player_ref=host_ref;
  perform pg_temp._rec('R4) sin fondos -> INSUFFICIENT_FUNDS (saldo intacto, no negativo)', ok and bal=10);
  -- restaurar
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_adjust_balance(gid, host_ref, 3000, 'restaurar', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
end $$;

-- R5) idempotencia de alquiler: misma request_id no cobra dos veces.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref');
            v_ver bigint; rid uuid:=gen_random_uuid(); b1 bigint; b2 bigint; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform pay_rent(gid,'cl-estacion-1',rid,v_ver);
  perform pg_temp._as_admin(); select balance into b1 from player_balances where game_id=gid and player_ref=host_ref;
  perform pg_temp._as_user(host); perform pay_rent(gid,'cl-estacion-1',rid,v_ver);   -- repetición
  perform pg_temp._as_admin(); select balance into b2 from player_balances where game_id=gid and player_ref=host_ref;
  perform pg_temp._rec('R5) idempotencia de alquiler (sin doble cobro)', b1=b2);
end $$;

-- R6) propiedad sin propietario -> PROPERTY_NOT_OWNED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform pay_rent(gid,'cl-marron-1',gen_random_uuid(),v_ver); exception when others then ok:=(sqlerrm='PROPERTY_NOT_OWNED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('R6) propiedad sin propietario -> PROPERTY_NOT_OWNED', ok);
end $$;

-- R7) en pausa no se paga alquiler -> GAME_PAUSED; en finalizada -> GAME_FINISHED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; ok1 boolean:=false; ok2 boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform pause_game_runtime(gid,'pausa',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform pay_rent(gid,'cl-estacion-1',gen_random_uuid(),v_ver); exception when others then ok1:=(sqlerrm='GAME_PAUSED'); end;
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform finish_game_runtime(gid,'fin',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform pay_rent(gid,'cl-estacion-1',gen_random_uuid(),v_ver); exception when others then ok2:=(sqlerrm='GAME_FINISHED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('R7) alquiler bloqueado en pausa (GAME_PAUSED) y finalizada (GAME_FINISHED)', ok1 and ok2);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── rent_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
