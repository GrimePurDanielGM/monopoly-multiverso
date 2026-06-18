-- ============================================================================
-- Reconciliacion  (Fase 2). Tras `supabase db reset`.
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
  r := create_game_tx('Reconciliacion IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- Secuencia mixta de operaciones y reconstruccion total desde el ledger.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host');
            p1 text:=pg_temp._ctx('p1'); p2 text:=pg_temp._ctx('p2'); p3 text:=pg_temp._ctx('p3');
            v_ver bigint; lref text; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform bank_transfer(gid, p1, 'to_player', 500, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._uid_of(gid,p1)); perform player_transfer(gid, p2, 200, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_adjust_balance(gid, p3, 4444, 'ajuste', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform bank_transfer(gid, p2, 'from_player', 100, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select ledger_ref into lref from ledger where game_id=gid and kind='bank_to_player' and to_ref=p1 and amount=500 order by seq desc limit 1;
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_revert_movement(gid, lref, 'deshacer', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
end $$;

-- REC1) reconstruccion total: balance == Sigma(entradas) - Sigma(salidas) por jugador.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_div int; begin
  perform pg_temp._as_admin();
  with rebuilt as (
    select b.player_ref, b.balance as materializado,
      coalesce((select sum(amount) from ledger l where l.game_id=gid and l.to_ref=b.player_ref),0)
    - coalesce((select sum(amount) from ledger l where l.game_id=gid and l.from_ref=b.player_ref),0) as reconstruido
    from player_balances b where b.game_id=gid)
  select count(*) into v_div from rebuilt where materializado <> reconstruido;
  perform pg_temp._rec('REC1) reconstruccion total ledger==player_balances', v_div=0);
end $$;

-- REC2) saldos nunca negativos.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_neg int; begin
  perform pg_temp._as_admin(); select count(*) into v_neg from player_balances where game_id=gid and balance<0;
  perform pg_temp._rec('REC2) ningun saldo negativo', v_neg=0);
end $$;

-- REC3) ledger inmutable: UPDATE y DELETE fallan.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; ok_u boolean:=false; ok_d boolean:=false; begin
  perform pg_temp._as_admin();
  begin update ledger set amount=1 where game_id=gid; exception when others then ok_u:=true; end;
  begin delete from ledger where game_id=gid; exception when others then ok_d:=true; end;
  perform pg_temp._rec('REC3) ledger inmutable (UPDATE/DELETE fallan)', ok_u and ok_d);
end $$;

do $g$ declare n int; begin
  select count(*) into n from _t where ok is false;
  if n>0 then raise exception 'FALLOS: %', n; end if;
  raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
end $g$;
