-- ============================================================================
-- Fase 2 — Banco digital: siembra, transferencias, fondos, versión, idempotencia,
-- no-op de ajuste y RECONCILIACIÓN. Tras `supabase db reset`.
--   psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/economy_phase2.sql
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
drop table if exists _ctx; create temp table _ctx(k text primary key, v text);
grant select, insert, update, delete on _t, _ctx to authenticated;  -- escribibles bajo SET ROLE
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if;
end $$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $$
begin perform set_config('role', session_user, true); end $$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function pg_temp._ctx(k text) returns text language sql as $$ select v from _ctx where k=$1 $$;

-- ── Setup: partida con 6 jugadores -> active (start_game crea runtime + siembra) ──
do $$
declare host text:='b0000000-0000-0000-0000-000000000a01'; r jsonb; gid uuid; code text; ref text;
        uids text[]:=array['b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000002',
                           'b0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000004',
                           'b0000000-0000-0000-0000-000000000005'];
        toks text[]:=array['cat','boot','thimble','top_hat','iron']; i int; v_ver int;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Economia IT','Anfitrion','penguin','{}','c1110000-0000-0000-0000-000000000001','H','S','A',1);
  gid := (r->>'game_id')::uuid; code := r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host_ref',r->>'host_public_ref');
  for i in 1..5 loop
    perform pg_temp._as_user(uids[i]);
    perform join_game(code, 'P'||i, gen_random_uuid());
    perform pg_temp._as_admin();
    select public_ref into ref from players where game_id=gid and auth_uid=uids[i]::uuid and kicked_at is null;
    insert into _ctx values ('p'||i, ref);
    perform pg_temp._as_user(uids[i]);
    perform choose_token(gid, toks[i]);
    perform set_ready(gid, true);
  end loop;
  perform pg_temp._as_user(host);
  perform set_ready(gid, true);
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host);
  perform start_game(gid, v_ver);
  perform pg_temp._as_admin();
end $$;

-- 1) Siembra: todos a initial_money (3000) y runtime inicial coherente.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_all int; v_seed int; v_idx int; v_num int; begin
  select count(*) into v_all from player_balances where game_id=gid and balance=3000;
  select count(*) into v_seed from ledger where game_id=gid and kind='seed' and amount=3000 and from_ref is null and to_ref is not null;
  select turn_index, turn_number into v_idx, v_num from game_runtime where game_id=gid;
  perform pg_temp._rec('1) siembra 6 saldos a 3000', v_all=6);
  perform pg_temp._rec('1b) 6 movimientos seed banco->jugador', v_seed=6);
  perform pg_temp._rec('1c) runtime turn_index=1 turn_number=1', v_idx=1 and v_num=1);
end $$;

-- 2) bank_transfer to_player y from_player (solo anfitrión).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:='b0000000-0000-0000-0000-000000000a01';
            p1 text:=pg_temp._ctx('p1'); v_bal bigint; v_ver bigint; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  perform bank_transfer(gid, p1, 'to_player', 500, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select balance into v_bal from player_balances where game_id=gid and player_ref=p1;
  perform pg_temp._rec('2) bank to_player +500 -> 3500', v_bal=3500);
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  perform bank_transfer(gid, p1, 'from_player', 200, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select balance into v_bal from player_balances where game_id=gid and player_ref=p1;
  perform pg_temp._rec('2b) bank from_player -200 -> 3300', v_bal=3300);
end $$;

-- 3) bank_transfer NO permitido a un jugador (NOT_HOST).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p2 text:=pg_temp._ctx('p2');
            ok boolean:=false; v_ver bigint; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000001');
  begin perform bank_transfer(gid, p2, 'to_player', 100, gen_random_uuid(), v_ver);
  exception when others then ok := (sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('3) jugador no puede usar bank_transfer (NOT_HOST)', ok);
end $$;

-- 4) player_transfer entre jugadores (fuera de turno permitido) y SELF_TRANSFER.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p2 text:=pg_temp._ctx('p2');
            v_b1 bigint; v_b2 bigint; v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000001');     -- p1 paga a p2
  perform player_transfer(gid, p2, 300, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select balance into v_b1 from player_balances where game_id=gid and player_ref=p1;
  select balance into v_b2 from player_balances where game_id=gid and player_ref=p2;
  perform pg_temp._rec('4) p1->p2 300 (p1=3000, p2=3300)', v_b1=3000 and v_b2=3300);
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000001');
  begin perform player_transfer(gid, p1, 10, gen_random_uuid(), v_ver);
  exception when others then ok := (sqlerrm='SELF_TRANSFER'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('4b) auto-transferencia rechazada (SELF_TRANSFER)', ok);
end $$;

-- 5) Fondos insuficientes y nunca negativo.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p3 text:=pg_temp._ctx('p3'); p4 text:=pg_temp._ctx('p4');
            v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000003');
  begin perform player_transfer(gid, p4, 999999, gen_random_uuid(), v_ver);
  exception when others then ok := (sqlerrm='INSUFFICIENT_FUNDS'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('5) fondos insuficientes (INSUFFICIENT_FUNDS)', ok
    and (select balance from player_balances where game_id=gid and player_ref=p3) >= 0);
end $$;

-- 6) VERSION_CONFLICT con versión antigua (operación nueva, no reintento).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p2 text:=pg_temp._ctx('p2'); ok boolean:=false; begin
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000001');
  begin perform player_transfer(gid, p2, 10, gen_random_uuid(), 0);   -- versión 0 ya obsoleta
  exception when others then ok := (sqlerrm='VERSION_CONFLICT'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('6) version antigua -> VERSION_CONFLICT', ok);
end $$;

-- 7) Idempotencia: mismo request_id no aplica dos veces (ni con versión antigua).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p2 text:=pg_temp._ctx('p2');
            rid uuid:=gen_random_uuid(); v_ver bigint; r1 jsonb; r2 jsonb; v_b2a bigint; v_b2b bigint; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  select balance into v_b2a from player_balances where game_id=gid and player_ref=p2;
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000001');
  r1 := player_transfer(gid, p2, 100, rid, v_ver);
  r2 := player_transfer(gid, p2, 100, rid, 0);          -- reintento con versión vieja: devuelve original
  perform pg_temp._as_admin();
  select balance into v_b2b from player_balances where game_id=gid and player_ref=p2;
  perform pg_temp._rec('7) idempotente: aplica una sola vez (+100)', v_b2b = v_b2a + 100);
  perform pg_temp._rec('7b) reintento devuelve el resultado original', r1 = r2);
end $$;

-- 8) host_adjust_balance no-op si coincide el saldo (changed=false, sin tocar versión).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:='b0000000-0000-0000-0000-000000000a01';
            p5 text:=pg_temp._ctx('p5'); v_cur bigint; v_ver0 bigint; v_ver1 bigint; r jsonb; begin
  perform pg_temp._as_admin();
  select balance into v_cur from player_balances where game_id=gid and player_ref=p5;
  select runtime_version into v_ver0 from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  r := host_adjust_balance(gid, p5, v_cur, 'sin cambio', gen_random_uuid(), v_ver0);
  perform pg_temp._as_admin(); select runtime_version into v_ver1 from game_runtime where game_id=gid;
  perform pg_temp._rec('8) ajuste no-op: changed=false y version intacta',
    (r->>'changed')='false' and v_ver1=v_ver0);
end $$;

-- 9) RECONCILIACIÓN: saldo materializado == Σ(entradas) − Σ(salidas) del ledger, por jugador.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_div int; begin
  perform pg_temp._as_admin();
  with reconciled as (
    select b.player_ref,
           b.balance as materializado,
           coalesce((select sum(amount) from ledger l where l.game_id=gid and l.to_ref=b.player_ref),0)
         - coalesce((select sum(amount) from ledger l where l.game_id=gid and l.from_ref=b.player_ref),0) as desde_ledger
    from player_balances b where b.game_id=gid)
  select count(*) into v_div from reconciled where materializado <> desde_ledger;
  perform pg_temp._rec('9) reconciliacion ledger==player_balances (0 divergencias)', v_div=0);
end $$;

-- ── Gate final ──
do $$ declare n int; begin
  select count(*) into n from _t where ok is false;
  if n>0 then raise exception 'FALLOS: %', n; end if;
  raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
end $$;
