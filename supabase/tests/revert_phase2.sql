-- ============================================================================
-- Reversion  (Fase 2). Tras `supabase db reset`.
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
create or replace function pg_temp._uid_of(p_gid uuid, p_ref text) returns text language sql as $f$
  select auth_uid::text from public.players where game_id=p_gid and public_ref=p_ref $f$;

-- Setup: 6 jugadores -> active (start_game crea runtime + siembra a 3000).
do $s$
declare host text:='b0000000-0000-0000-0000-000000000a01'; r jsonb; gid uuid; code text; ref text;
        uids text[]:=array['b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000002',
                           'b0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000004',
                           'b0000000-0000-0000-0000-000000000005'];
        toks text[]:=array['cat','boot','thimble','top_hat','iron']; i int; v_ver int;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Reversion IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid; code := r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  for i in 1..5 loop
    perform pg_temp._as_user(uids[i]);
    perform join_game(code, 'P'||i, gen_random_uuid());
    perform pg_temp._as_admin();
    select public_ref into ref from players where game_id=gid and auth_uid=uids[i]::uuid and kicked_at is null;
    insert into _ctx values ('p'||i, ref);
    perform pg_temp._as_user(uids[i]); perform choose_token(gid, toks[i]); perform set_ready(gid, true);
  end loop;
  perform pg_temp._as_user(host); perform set_ready(gid, true);
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid, v_ver);
  perform pg_temp._as_admin();
end $s$;

-- R1) revertir un bank_to_player por ledger_ref: saldo restaurado + compensacion enlazada.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1');
            v_ver bigint; lref text; v_bal0 bigint; v_bal1 bigint; v_link int; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  select balance into v_bal0 from player_balances where game_id=gid and player_ref=p1;
  perform pg_temp._as_user(host); perform bank_transfer(gid, p1, 'to_player', 700, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select ledger_ref into lref from ledger where game_id=gid and kind='bank_to_player' and to_ref=p1 and amount=700 order by seq desc limit 1;
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_revert_movement(gid, lref, 'deshacer pago', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select balance into v_bal1 from player_balances where game_id=gid and player_ref=p1;
  select count(*) into v_link from ledger where game_id=gid and kind='host_revert' and reverts_ledger_id=(select id from ledger where game_id=gid and ledger_ref=lref);
  perform pg_temp._rec('R1) revertir bank_to_player restaura saldo y enlaza', v_bal1=v_bal0 and v_link=1);
end $$;

-- R2) revertir seed -> CANNOT_REVERT_SEED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); lref text; v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin();
  select ledger_ref into lref from ledger where game_id=gid and kind='seed' limit 1;
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform host_revert_movement(gid, lref, 'no deberia', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='CANNOT_REVERT_SEED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R2) revertir seed -> CANNOT_REVERT_SEED', ok);
end $$;

-- R3) doble reversion -> ALREADY_REVERTED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2 text:=pg_temp._ctx('p2');
            v_ver bigint; lref text; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform bank_transfer(gid, p2, 'to_player', 50, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select ledger_ref into lref from ledger where game_id=gid and kind='bank_to_player' and to_ref=p2 and amount=50 order by seq desc limit 1;
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_revert_movement(gid, lref, 'una', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform host_revert_movement(gid, lref, 'dos', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='ALREADY_REVERTED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R3) doble reversion -> ALREADY_REVERTED', ok);
end $$;

-- R4) reversion que dejaria negativo -> WOULD_GO_NEGATIVE.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p4 text:=pg_temp._ctx('p4'); p5 text:=pg_temp._ctx('p5');
            v_ver bigint; lref text; ok boolean:=false; begin
  -- banco da 100 a p4; p4 lo gasta a p5; revertir el pago del banco dejaria p4 negativo.
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform bank_transfer(gid, p4, 'to_player', 100, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select ledger_ref into lref from ledger where game_id=gid and kind='bank_to_player' and to_ref=p4 and amount=100 order by seq desc limit 1;
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._uid_of(gid,p4)); perform player_transfer(gid, p5, 3050, gen_random_uuid(), v_ver); -- p4 baja a 50
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform host_revert_movement(gid, lref, 'tarde', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='WOULD_GO_NEGATIVE'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R4) reversion negativa -> WOULD_GO_NEGATIVE', ok);
end $$;

-- R5) reversion sin motivo -> REASON_REQUIRED ; R6) ledger inexistente -> UNKNOWN_LEDGER.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; ok5 boolean:=false; ok6 boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform host_revert_movement(gid, 'L-FAKE000000', '  ', gen_random_uuid(), v_ver); exception when others then ok5:=(sqlerrm='REASON_REQUIRED'); end;
  begin perform host_revert_movement(gid, 'L-NOEXISTE0', 'motivo ok', gen_random_uuid(), v_ver); exception when others then ok6:=(sqlerrm='UNKNOWN_LEDGER'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('R5) reversion sin motivo -> REASON_REQUIRED', ok5);
  perform pg_temp._rec('R6) ledger inexistente -> UNKNOWN_LEDGER', ok6);
end $$;

do $g$ declare n int; begin
  select count(*) into n from _t where ok is false;
  if n>0 then raise exception 'FALLOS: %', n; end if;
  raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
end $g$;
