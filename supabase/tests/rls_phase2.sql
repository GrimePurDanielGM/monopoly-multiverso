-- ============================================================================
-- RLS  (Fase 2). Tras `supabase db reset`.
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
  r := create_game_tx('RLS IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- RLS1) acceso directo denegado a las 4 tablas internas para authenticated.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; denied int:=0; begin
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000001');
  begin perform 1 from public.game_runtime where game_id=gid; exception when insufficient_privilege then denied:=denied+1; end;
  begin perform 1 from public.player_balances where game_id=gid; exception when insufficient_privilege then denied:=denied+1; end;
  begin perform 1 from public.ledger where game_id=gid; exception when insufficient_privilege then denied:=denied+1; end;
  begin perform 1 from public.active_requests where game_id=gid; exception when insufficient_privilege then denied:=denied+1; end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('RLS1) acceso directo denegado a 4 tablas internas', denied=4);
end $$;

-- RLS2) snapshot sin ids internos / auth_uid / turn_order(uuid); solo public_ref.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); snap jsonb; txt text; ok boolean; begin
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000001');
  snap := get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  txt := snap::text;
  ok := (txt !~* 'auth_uid') and (txt !~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')  -- sin UUIDs
        and (snap->'turn'->'order'->>0) ~ '^P-' and (snap#>>'{me,public_ref}') ~ '^P-';
  perform pg_temp._rec('RLS2) snapshot saneado (sin uuid/auth_uid; solo public_ref)', ok);
end $$;

-- RLS3) ledger_recent expone ledger_ref opaco 'L-...' y nada interno.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); v_ver bigint; snap jsonb; lref text; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform bank_transfer(gid, p1, 'to_player', 123, gen_random_uuid(), v_ver);
  snap := get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  lref := snap->'ledger_recent'->0->>'ledger_ref';
  perform pg_temp._rec('RLS3) ledger_recent con ledger_ref opaco L-', lref ~ '^L-[0-9A-F]{10}$');
end $$;

do $g$ declare n int; begin
  select count(*) into n from _t where ok is false;
  if n>0 then raise exception 'FALLOS: %', n; end if;
  raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
end $g$;
