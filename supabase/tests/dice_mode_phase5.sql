-- ============================================================================
-- Configuración de dados (Fase 5 corrección ampliada): dice_mode por el anfitrión.
-- Default virtual_only; el host lo cambia en lobby y en activa; no-host no puede; finalizada bloquea;
-- el snapshot (lobby y activo) expone dice_mode. Tras `db reset`.
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
create or replace function pg_temp._gv(gid uuid) returns bigint language sql security definer as $f$ select version from public.games where id=gid $f$;
create or replace function pg_temp._mode(gid uuid) returns text language sql security definer as $f$ select coalesce(config->>'dice_mode','virtual_only') from public.games where id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='d1000000-0000-0000-0000-0000000000a1'; j1 text:='d1000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Dice IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref'),('host_uid',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- D1) default en lobby = virtual_only, y el snapshot de lobby lo expone.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); snap jsonb; begin
  perform pg_temp._as_user(host); snap := get_lobby_snapshot_by_code(code); perform pg_temp._as_admin();
  perform pg_temp._rec('D1) default virtual_only + lobby snapshot lo expone',
    pg_temp._mode(gid)='virtual_only' and (snap#>>'{game,config,dice_mode}')='virtual_only');
end $$;

-- D2) el host cambia el modo en LOBBY (physical_allowed); auditado dice_mode_changed.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); snap jsonb; naud int; begin
  perform pg_temp._as_user(host); perform set_dice_mode(gid,'physical_allowed',gen_random_uuid(),pg_temp._gv(gid));
  snap := get_lobby_snapshot_by_code(code); perform pg_temp._as_admin();
  select count(*) into naud from public.audit_events where game_id=gid and type='dice_mode_changed';
  perform pg_temp._rec('D2) host cambia modo en lobby (physical_allowed) + auditado',
    pg_temp._mode(gid)='physical_allowed' and (snap#>>'{game,config,dice_mode}')='physical_allowed' and naud>=1);
end $$;

-- D3) un NO-host no puede cambiar el modo (NOT_HOST).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform set_dice_mode(gid,'physical_only',gen_random_uuid(),pg_temp._gv(gid)); exception when others then ok:=(sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('D3) no-host no puede cambiar el modo (NOT_HOST)', ok);
end $$;

-- D4) modo inválido → INVALID_DICE_MODE.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host);
  begin perform set_dice_mode(gid,'nope',gen_random_uuid(),pg_temp._gv(gid)); exception when others then ok:=(sqlerrm='INVALID_DICE_MODE'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('D4) modo inválido → INVALID_DICE_MODE', ok);
end $$;

-- D5) el host cambia el modo en partida ACTIVA (physical_only); el snapshot activo lo expone.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); v int; snap jsonb; begin
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v);
  perform set_dice_mode(gid,'physical_only',gen_random_uuid(),pg_temp._ver(gid));
  snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  perform pg_temp._rec('D5) host cambia modo en activa (physical_only) + snapshot activo lo expone',
    pg_temp._mode(gid)='physical_only' and (snap#>>'{game,config,dice_mode}')='physical_only');
end $$;

-- D6) partida FINALIZADA: bloquea cambios (GAME_FINISHED).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_admin(); update public.game_runtime set runtime_status='finished', finished_at=now() where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform set_dice_mode(gid,'virtual_only',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='GAME_FINISHED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('D6) finalizada bloquea cambios (GAME_FINISHED)', ok);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
