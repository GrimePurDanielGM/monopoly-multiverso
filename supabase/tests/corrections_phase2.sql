-- ============================================================================
-- Correcciones  (Fase 2). Tras `supabase db reset`.
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
  r := create_game_tx('Correcciones IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- C1) host_adjust sube saldo: ledger host_adjust con before/after/delta y audit.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1');
            v_ver bigint; v_bal bigint; v_led int; v_aud int; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_adjust_balance(gid, p1, 5000, 'premio', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select balance into v_bal from player_balances where game_id=gid and player_ref=p1;
  select count(*) into v_led from ledger where game_id=gid and kind='host_adjust' and to_ref=p1 and before_balance=3000 and after_balance=5000 and amount=2000 and reason='premio';
  select count(*) into v_aud from audit_events where game_id=gid and type='host_adjust';
  perform pg_temp._rec('C1) host_adjust sube saldo con before/after/delta + audit', v_bal=5000 and v_led=1 and v_aud>=1);
end $$;

-- C2) host_adjust no-op (mismo saldo): no inserta ledger nuevo.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1');
            v_ver bigint; v_before int; v_after int; r jsonb; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  select count(*) into v_before from ledger where game_id=gid;
  perform pg_temp._as_user(host); r := host_adjust_balance(gid, p1, 5000, 'igual', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select count(*) into v_after from ledger where game_id=gid;
  perform pg_temp._rec('C2) host_adjust no-op no inserta ledger', (r->>'changed')='false' and v_after=v_before);
end $$;

-- C3) host_adjust sin motivo -> REASON_REQUIRED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2 text:=pg_temp._ctx('p2'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform host_adjust_balance(gid, p2, 100, '', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='REASON_REQUIRED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('C3) host_adjust sin motivo -> REASON_REQUIRED', ok);
end $$;

-- C4) host_adjust negativo -> NEGATIVE_NOT_ALLOWED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2 text:=pg_temp._ctx('p2'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform host_adjust_balance(gid, p2, -1, 'malo', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='NEGATIVE_NOT_ALLOWED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('C4) host_adjust negativo -> NEGATIVE_NOT_ALLOWED', ok);
end $$;

-- C5) host_player_transfer con motivo mueve dinero y audita.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2 text:=pg_temp._ctx('p2'); p3 text:=pg_temp._ctx('p3');
            v_ver bigint; v2 bigint; v3 bigint; v_led int; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_player_transfer(gid, p2, p3, 400, 'reparto manual', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select balance into v2 from player_balances where game_id=gid and player_ref=p2;
  select balance into v3 from player_balances where game_id=gid and player_ref=p3;
  select count(*) into v_led from ledger where game_id=gid and kind='host_player_transfer' and from_ref=p2 and to_ref=p3 and amount=400 and reason='reparto manual';
  perform pg_temp._rec('C5) host_player_transfer mueve dinero + audita', v2=2600 and v3=3400 and v_led=1);
end $$;

-- C6) host_player_transfer sin motivo -> REASON_REQUIRED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2 text:=pg_temp._ctx('p2'); p3 text:=pg_temp._ctx('p3'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform host_player_transfer(gid, p2, p3, 10, '  ', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='REASON_REQUIRED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('C6) host_player_transfer sin motivo -> REASON_REQUIRED', ok);
end $$;

-- C7) jugador no anfitrion no puede host_adjust -> NOT_HOST.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000001');
  begin perform host_adjust_balance(gid, p1, 1, 'intruso', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('C7) no-host host_adjust -> NOT_HOST', ok);
end $$;

do $g$ declare n int; begin
  select count(*) into n from _t where ok is false;
  if n>0 then raise exception 'FALLOS: %', n; end if;
  raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
end $g$;
