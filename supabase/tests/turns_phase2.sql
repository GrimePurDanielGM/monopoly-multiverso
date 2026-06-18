-- ============================================================================
-- Turnos  (Fase 2). Tras `supabase db reset`.
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
  r := create_game_tx('Turnos IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- T1) turn_order_refs SOLO public_ref ('P-XXXXXXXXXX'); nunca ids internos.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_ok boolean; begin
  select bool_and(ref ~ '^P-[0-9A-F]{10}$') into v_ok from game_runtime, unnest(turn_order_refs) as ref where game_id=gid;
  perform pg_temp._rec('T1) turn_order_refs solo public_ref', v_ok);
end $$;

-- T2) end_turn solo el jugador actual; otro -> NOT_CURRENT_PLAYER.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; other text; uid text; ok boolean:=false; v_ver bigint; begin
  select turn_order_refs[turn_index], runtime_version into cur, v_ver from game_runtime where game_id=gid;
  select ref into other from game_runtime, unnest(turn_order_refs) as ref where game_id=gid and ref<>cur limit 1;
  uid := pg_temp._uid_of(gid, other);
  perform pg_temp._as_user(uid);
  begin perform end_turn(gid, v_ver, gen_random_uuid()); exception when others then ok:=(sqlerrm='NOT_CURRENT_PLAYER'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('T2) end_turn por no-actual -> NOT_CURRENT_PLAYER', ok);
end $$;

-- T3) end_turn del actual avanza turn_index (+1 mod n) y turn_number (+1).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text; uid text; v_ver bigint; i0 int; n0 int; i1 int; n1 int; begin
  select turn_order_refs[turn_index], runtime_version, turn_index, turn_number into cur, v_ver, i0, n0 from game_runtime where game_id=gid;
  uid := pg_temp._uid_of(gid, cur);
  perform pg_temp._as_user(uid); perform end_turn(gid, v_ver, gen_random_uuid());
  perform pg_temp._as_admin(); select turn_index, turn_number into i1, n1 from game_runtime where game_id=gid;
  perform pg_temp._rec('T3) end_turn avanza index y turn_number', i1=(i0 % 6)+1 and n1=n0+1);
end $$;

-- T4) host_set_turn fija a otro jugador (motivo); current cambia; turn_number NO sube.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); tgt text; v_ver bigint; n0 int; cur1 text; n1 int; begin
  perform pg_temp._as_admin();
  select turn_order_refs[4], runtime_version, turn_number into tgt, v_ver, n0 from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_set_turn(gid, tgt, 'mover por error', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select turn_order_refs[turn_index], turn_number into cur1, n1 from game_runtime where game_id=gid;
  perform pg_temp._rec('T4) host_set_turn fija jugador y no sube turn_number', cur1=tgt and n1=n0);
end $$;

-- T5) host_set_turn no-op si ya es el actual (changed=false, version intacta).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; v0 bigint; v1 bigint; r jsonb; begin
  perform pg_temp._as_admin(); select turn_order_refs[turn_index], runtime_version into cur, v0 from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); r := host_set_turn(gid, cur, 'sin cambio', gen_random_uuid(), v0);
  perform pg_temp._as_admin(); select runtime_version into v1 from game_runtime where game_id=gid;
  perform pg_temp._rec('T5) host_set_turn no-op (changed=false, version intacta)', (r->>'changed')='false' and v1=v0);
end $$;

-- T6) host_set_turn sin motivo -> REASON_REQUIRED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); tgt text; v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select turn_order_refs[2], runtime_version into tgt, v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform host_set_turn(gid, tgt, '  ', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='REASON_REQUIRED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('T6) host_set_turn sin motivo -> REASON_REQUIRED', ok);
end $$;

do $g$ declare n int; begin
  select count(*) into n from _t where ok is false;
  if n>0 then raise exception 'FALLOS: %', n; end if;
  raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
end $g$;
