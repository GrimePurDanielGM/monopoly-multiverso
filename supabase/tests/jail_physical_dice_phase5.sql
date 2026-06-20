-- ============================================================================
-- Dados físicos en cárcel (Fase 5 corrección ampliada): move_with_physical_roll estando preso.
-- Dobles físicos liberan+mueven; no-dobles falla y bloquea más acciones ese turno (una acción/turno);
-- respeta 3 intentos máximos; y bloqueado si el modo no permite físicos. Tras `db reset`.
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
create or replace function pg_temp._injail(gid uuid, ref text) returns boolean language sql security definer as $f$ select exists(select 1 from public.game_jail where game_id=gid and player_ref=ref) $f$;
create or replace function pg_temp._prep_jail(gid uuid, ref text, turns int) returns void language plpgsql security definer as $f$
begin
  insert into public.game_jail(game_id,player_ref,board_key,jail_turns,action_turn) values (gid,ref,'classic',turns,0)
    on conflict (game_id,player_ref) do update set board_key='classic', jail_turns=turns, action_turn=0;
  update public.player_positions set board_key='classic', space_index=10 where game_id=gid and player_ref=ref;
  update public.game_runtime set pending_payment=null where game_id=gid;
end $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='d3000000-0000-0000-0000-0000000000a1'; j1 text:='d3000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('JailPhys IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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
  perform set_dice_mode(gid,'physical_allowed',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- J1) intento físico con DOBLES (3+3): libera y mueve.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid, href, 0);
  perform pg_temp._as_user(host); res := move_with_physical_roll(gid,3,3,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J1) intento físico dobles (3+3): libera y mueve', (res->>'jail_result')='doubles' and not pg_temp._injail(gid,href));
end $$;

-- J2) intento físico SIN dobles (2+5): falla y bloquea más acciones ese turno.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); res jsonb; okblock boolean:=false; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid, href, 0);
  perform pg_temp._as_user(host); res := move_with_physical_roll(gid,2,5,gen_random_uuid(),pg_temp._ver(gid));
  begin perform move_with_physical_roll(gid,1,1,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okblock:=(sqlerrm='JAIL_ACTION_ALREADY_TAKEN'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('J2) físico sin dobles (2+5): falla y bloquea más acciones',
    (res->>'jail_result')='failed' and pg_temp._injail(gid,href) and okblock);
end $$;

-- J3) físico respeta el máximo de 3 intentos: con 2 fallos previos, no-dobles → salida forzada (forced_paid).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid, href, 2);
  perform pg_temp._as_user(host); res := move_with_physical_roll(gid,2,5,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J3) físico respeta 3 intentos: 3er intento → forzado (forced_paid)',
    (res->>'jail_result')='forced_paid' and not pg_temp._injail(gid,href));
end $$;

-- J4) una acción de cárcel por turno también con físico: tras fallar físico, el VIRTUAL queda bloqueado.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); okblock boolean:=false; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid, href, 0);
  perform pg_temp._as_user(host); perform move_with_physical_roll(gid,2,5,gen_random_uuid(),pg_temp._ver(gid));
  begin perform roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okblock:=(sqlerrm='JAIL_ACTION_ALREADY_TAKEN'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('J4) tras fallar físico, virtual bloqueado (una acción/turno)', okblock);
end $$;

-- J5) físico bloqueado si el modo no lo permite (virtual_only), estando preso → PHYSICAL_DICE_DISABLED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); ok boolean:=false; begin
  perform pg_temp._as_user(host); perform set_dice_mode(gid,'virtual_only',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid, href, 0);
  perform pg_temp._as_user(host);
  begin perform move_with_physical_roll(gid,3,3,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='PHYSICAL_DICE_DISABLED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('J5) físico bloqueado en virtual_only estando preso (PHYSICAL_DICE_DISABLED)', ok);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
