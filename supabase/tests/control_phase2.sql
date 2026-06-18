-- ============================================================================
-- Control de partida (Fase 2): pausa, reanudar, finalizar. Tras `supabase db reset`.
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
create or replace function pg_temp._uid_of(p_gid uuid, p_ref text) returns text language sql security definer as $f$
  select auth_uid::text from public.players where game_id=p_gid and public_ref=p_ref $f$;

do $s$
declare host text:='b0000000-0000-0000-0000-000000000a01'; r jsonb; gid uuid; code text; ref text;
        uids text[]:=array['b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000002',
                           'b0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000004',
                           'b0000000-0000-0000-0000-000000000005'];
        toks text[]:=array['cat','boot','thimble','top_hat','iron']; i int; v_ver int;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Control IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- P1) solo el anfitrion puede pausar; no-host -> NOT_HOST.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000001');
  begin perform pause_game_runtime(gid,'no', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('P1) no-host pausa -> NOT_HOST', ok);
end $$;

-- P2) host pausa (running->paused) y el snapshot lo refleja.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; st text; snap jsonb; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform pause_game_runtime(gid,'cafe', gen_random_uuid(), v_ver);
  snap := get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin(); select runtime_status into st from game_runtime where game_id=gid;
  perform pg_temp._rec('P2) pausa running->paused y snapshot legible', st='paused' and snap->>'runtime_status'='paused');
end $$;

-- P3) pausada: TODAS las mutaciones -> GAME_PAUSED ; snapshot sigue accesible.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p2 text:=pg_temp._ctx('p2');
            v_ver bigint; cnt int:=0; ok boolean; cur text; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  select turn_order_refs[turn_index] into cur from game_runtime where game_id=gid;
  -- end_turn por el jugador actual
  perform pg_temp._as_user(pg_temp._uid_of(gid,cur));
  begin perform end_turn(gid, v_ver, gen_random_uuid()); exception when others then if sqlerrm='GAME_PAUSED' then cnt:=cnt+1; end if; end;
  perform pg_temp._as_user(host);
  begin perform bank_transfer(gid,p1,'to_player',10,gen_random_uuid(),v_ver); exception when others then if sqlerrm='GAME_PAUSED' then cnt:=cnt+1; end if; end;
  begin perform host_adjust_balance(gid,p1,100,'xxx',gen_random_uuid(),v_ver); exception when others then if sqlerrm='GAME_PAUSED' then cnt:=cnt+1; end if; end;
  begin perform host_player_transfer(gid,p1,p2,10,'xxx',gen_random_uuid(),v_ver); exception when others then if sqlerrm='GAME_PAUSED' then cnt:=cnt+1; end if; end;
  begin perform host_set_turn(gid,p2,'xxx',gen_random_uuid(),v_ver); exception when others then if sqlerrm='GAME_PAUSED' then cnt:=cnt+1; end if; end;
  begin perform host_revert_movement(gid,'L-XXXXXXXXXX','xxx',gen_random_uuid(),v_ver); exception when others then if sqlerrm='GAME_PAUSED' then cnt:=cnt+1; end if; end;
  perform pg_temp._as_user(pg_temp._uid_of(gid,p1));
  begin perform player_transfer(gid,p2,10,gen_random_uuid(),v_ver); exception when others then if sqlerrm='GAME_PAUSED' then cnt:=cnt+1; end if; end;
  perform pg_temp._as_admin();
  ok := (get_active_snapshot_by_code(pg_temp._ctx('code')) is not null);
  perform pg_temp._rec('P3) pausada: 7 mutaciones -> GAME_PAUSED y snapshot legible', cnt=7 and ok);
end $$;

-- P4) pausa idempotente (mismo request_id) y no-op si ya pausada.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; rid uuid:=gen_random_uuid(); r1 jsonb; r2 jsonb; noop jsonb; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  r1 := pause_game_runtime(gid,'y',rid,v_ver); r2 := pause_game_runtime(gid,'y',rid,0);  -- reintento
  noop := pause_game_runtime(gid,'z',gen_random_uuid(), (r1->>'runtime_version')::bigint); -- ya pausada -> no-op
  perform pg_temp._as_admin();
  perform pg_temp._rec('P4) pausa idempotente y no-op si ya pausada', r1=r2 and (noop->>'changed')='false');
end $$;

-- P5) reanudar (paused->running) restaura las acciones.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; st text; cur text; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform resume_game_runtime(gid, gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_status into st from game_runtime where game_id=gid;
  select turn_order_refs[turn_index] into cur from game_runtime where game_id=gid;
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._uid_of(gid,cur));
  begin perform end_turn(gid, v_ver, gen_random_uuid()); ok:=true; exception when others then ok:=false; end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P5) reanudar running y end_turn funciona', st='running' and ok);
end $$;

-- P6) conflicto de version al pausar con version vieja.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host);
  begin perform pause_game_runtime(gid,'v', gen_random_uuid(), 0); exception when others then ok:=(sqlerrm='VERSION_CONFLICT'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('P6) pausa version vieja -> VERSION_CONFLICT', ok);
end $$;

-- F1) solo host finaliza; no-host -> NOT_HOST.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user('b0000000-0000-0000-0000-000000000002');
  begin perform finish_game_runtime(gid,'no', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('F1) no-host finaliza -> NOT_HOST', ok);
end $$;

-- F2) finalizar (terminal): mutaciones -> GAME_FINISHED, reanudar -> GAME_FINISHED, ledger/saldos intactos.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1');
            v_ver bigint; st text; led0 int; led1 int; okf boolean:=false; okr boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  select count(*) into led0 from ledger where game_id=gid;
  perform pg_temp._as_user(host); perform finish_game_runtime(gid,'fin', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_status into st from game_runtime where game_id=gid;
  select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform bank_transfer(gid,p1,'to_player',10,gen_random_uuid(),v_ver); exception when others then okf:=(sqlerrm='GAME_FINISHED'); end;
  begin perform resume_game_runtime(gid, gen_random_uuid(), v_ver); exception when others then okr:=(sqlerrm='GAME_FINISHED'); end;
  perform pg_temp._as_admin(); select count(*) into led1 from ledger where game_id=gid;
  perform pg_temp._rec('F2) finished terminal: mutacion+resume -> GAME_FINISHED, ledger intacto', st='finished' and okf and okr and led1=led0);
end $$;

-- F3) finalizar idempotente (mismo request_id) y no-op si ya finalizada.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; noop jsonb; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); noop := finish_game_runtime(gid,'otra', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); perform pg_temp._rec('F3) finalizar ya finalizada -> no-op idempotente', (noop->>'changed')='false');
end $$;

do $g$ declare n int; begin
  select count(*) into n from _t where ok is false;
  if n>0 then raise exception 'FALLOS: %', n; end if;
  raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
end $g$;
