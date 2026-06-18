-- ============================================================================
-- Idempotencia  (Fase 2). Tras `supabase db reset`.
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
  r := create_game_tx('Idempotencia IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- I1) end_turn con mismo request_id: aplica una sola vez.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; uid text; v_ver bigint; rid uuid:=gen_random_uuid(); n0 int; n1 int; r1 jsonb; r2 jsonb; begin
  perform pg_temp._as_admin(); select turn_order_refs[turn_index], runtime_version, turn_number into cur, v_ver, n0 from game_runtime where game_id=gid;
  uid := pg_temp._uid_of(gid, cur); perform pg_temp._as_user(uid);
  r1 := end_turn(gid, v_ver, rid); r2 := end_turn(gid, 0, rid);   -- reintento version vieja
  perform pg_temp._as_admin(); select turn_number into n1 from game_runtime where game_id=gid;
  perform pg_temp._rec('I1) end_turn idempotente: avanza una vez', n1=n0+1 and r1=r2);
end $$;

-- I2) bank_transfer con mismo request_id: aplica una sola vez.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1');
            v_ver bigint; rid uuid:=gen_random_uuid(); b0 bigint; b1 bigint; r1 jsonb; r2 jsonb; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  select balance into b0 from player_balances where game_id=gid and player_ref=p1;
  perform pg_temp._as_user(host);
  r1 := bank_transfer(gid, p1, 'to_player', 250, rid, v_ver); r2 := bank_transfer(gid, p1, 'to_player', 250, rid, 0);
  perform pg_temp._as_admin(); select balance into b1 from player_balances where game_id=gid and player_ref=p1;
  perform pg_temp._rec('I2) bank_transfer idempotente: +250 una vez', b1=b0+250 and r1=r2);
end $$;

-- I3) host_set_turn idempotente.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); tgt text; v_ver bigint; rid uuid:=gen_random_uuid(); r1 jsonb; r2 jsonb; cur1 text; begin
  perform pg_temp._as_admin(); select turn_order_refs[3], runtime_version into tgt, v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); r1 := host_set_turn(gid, tgt, 'mover', rid, v_ver); r2 := host_set_turn(gid, tgt, 'mover', rid, 0);
  perform pg_temp._as_admin(); select turn_order_refs[turn_index] into cur1 from game_runtime where game_id=gid;
  perform pg_temp._rec('I3) host_set_turn idempotente', r1=r2 and cur1=tgt);
end $$;

-- I4) host_adjust idempotente (mismo request_id no aplica dos veces).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p5 text:=pg_temp._ctx('p5');
            v_ver bigint; rid uuid:=gen_random_uuid(); b1 bigint; r1 jsonb; r2 jsonb; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); r1 := host_adjust_balance(gid, p5, 9000, 'fijar', rid, v_ver); r2 := host_adjust_balance(gid, p5, 9000, 'fijar', rid, 0);
  perform pg_temp._as_admin(); select balance into b1 from player_balances where game_id=gid and player_ref=p5;
  perform pg_temp._rec('I4) host_adjust idempotente', b1=9000 and r1=r2);
end $$;

do $g$ declare n int; begin
  select count(*) into n from _t where ok is false;
  if n>0 then raise exception 'FALLOS: %', n; end if;
  raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
end $g$;
