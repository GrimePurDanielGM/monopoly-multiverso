-- ============================================================================
-- Dados físicos en movimiento normal (Fase 5 corrección ampliada): move_with_physical_roll.
-- Bloqueado si virtual_only; permitido si physical_allowed/physical_only; valida 1–6; total correcto;
-- y roll_and_move (virtual) bloqueado si physical_only. Tras `db reset`.
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
create or replace function pg_temp._roll(gid uuid) returns jsonb language sql security definer as $f$ select last_roll from public.game_runtime where game_id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='d2000000-0000-0000-0000-0000000000a1'; j1 text:='d2000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Phys IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code'; href:=r->>'host_public_ref';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',href),('host_uid',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v);
  perform host_set_turn(gid, href, 'turno host (test)', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- P1) físico BLOQUEADO en virtual_only (por defecto) → PHYSICAL_DICE_DISABLED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host);
  begin perform move_with_physical_roll(gid,3,4,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='PHYSICAL_DICE_DISABLED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P1) físico bloqueado en virtual_only (PHYSICAL_DICE_DISABLED)', ok);
end $$;

-- P2) physical_allowed: 3+4 avanza 7 (total correcto en last_roll y resultado).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); res jsonb; begin
  perform pg_temp._as_user(host); perform set_dice_mode(gid,'physical_allowed',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform host_set_player_position(gid, href, 'classic', 0, 'reset (test)', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(host); res := move_with_physical_roll(gid,3,4,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('P2) physical_allowed: 3+4 → total 7 (last_roll y resultado)',
    (res->>'total')='7' and ((pg_temp._roll(gid))->>'total')='7' and (res->>'d1')='3' and (res->>'d2')='4');
end $$;

-- P3) dobles físicos en movimiento normal: 2+2 → total 4 (se detecta total correcto).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); res jsonb; begin
  perform pg_temp._as_user(host); perform host_set_player_position(gid, href, 'classic', 0, 'reset (test)', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(host); res := move_with_physical_roll(gid,2,2,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('P3) dobles físicos 2+2 → total 4 en movimiento normal', (res->>'total')='4');
end $$;

-- P4) valor de dado inválido (0 / 7) → INVALID_DIE_VALUE.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok1 boolean:=false; ok2 boolean:=false; begin
  perform pg_temp._as_user(host);
  begin perform move_with_physical_roll(gid,0,4,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok1:=(sqlerrm='INVALID_DIE_VALUE'); end;
  begin perform move_with_physical_roll(gid,3,7,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok2:=(sqlerrm='INVALID_DIE_VALUE'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P4) dado inválido (0/7) → INVALID_DIE_VALUE', ok1 and ok2);
end $$;

-- P5) physical_only: virtual (roll_and_move) BLOQUEADO → VIRTUAL_DICE_DISABLED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); ok boolean:=false; begin
  perform pg_temp._as_user(host); perform set_dice_mode(gid,'physical_only',gen_random_uuid(),pg_temp._ver(gid));
  begin perform roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='VIRTUAL_DICE_DISABLED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P5) physical_only: virtual bloqueado (VIRTUAL_DICE_DISABLED)', ok);
end $$;

-- P6) physical_only: el físico SÍ funciona (5+6 → total 11).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); res jsonb; begin
  perform pg_temp._as_user(host); perform host_set_player_position(gid, href, 'classic', 0, 'reset (test)', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(host); res := move_with_physical_roll(gid,5,6,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('P6) physical_only: 5+6 → total 11 (físico funciona)', (res->>'total')='11');
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
