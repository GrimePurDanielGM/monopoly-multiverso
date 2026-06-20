-- ============================================================================
-- Una sola acción de cárcel por turno (Fase 5 corrección): tras intentar dobles y fallar, el jugador no
-- puede volver a intentar/pagar/usar carta ese turno (JAIL_ACTION_ALREADY_TAKEN); al volver a tocarle sí.
-- Pagar/usar carta liberan (los demás métodos quedan bloqueados). Snapshot expone action_taken_this_turn.
-- Dados aleatorios: se REPITE hasta forzar un fallo. Tras `db reset`.
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
create or replace function pg_temp._cur(gid uuid) returns text language sql security definer as $f$ select turn_order_refs[turn_index] from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._uid(gid uuid, ref text) returns text language sql security definer as $f$ select auth_uid::text from public.players where game_id=gid and public_ref=ref $f$;
create or replace function pg_temp._injail(gid uuid, ref text) returns boolean language sql security definer as $f$ select exists(select 1 from public.game_jail where game_id=gid and player_ref=ref) $f$;
-- Coloca a un jugador en la cárcel (classic, idx 10) con N intentos y la acción del turno SIN tomar.
create or replace function pg_temp._prep_jail(gid uuid, ref text, turns int) returns void language plpgsql security definer as $f$
begin
  insert into public.game_jail(game_id,player_ref,board_key,jail_turns,action_turn) values (gid,ref,'classic',turns,0)
    on conflict (game_id,player_ref) do update set board_key='classic', jail_turns=turns, action_turn=0;
  update public.player_positions set board_key='classic', space_index=10 where game_id=gid and player_ref=ref;
  update public.game_runtime set pending_payment=null where game_id=gid;
end $f$;
create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='be000000-0000-0000-0000-0000000000a1'; j1 text:='be000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('JailOnce IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref'),('host_uid',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin();
  insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v);
  perform pg_temp._as_user(host); perform host_set_turn(gid,(select c.v from _ctx c where c.k='p1'),'turno P1',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- A1) tras FALLAR el intento de dobles: no puede volver a intentar / pagar / usar carta este turno.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid');
            okfail boolean:=false; okroll boolean:=false; okpay boolean:=false; okcard boolean:=false; res jsonb; i int; begin
  -- repite intentos (re-preparando) hasta que uno falle; deja al jugador preso con la acción tomada.
  for i in 1..80 loop
    perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid, p1, 0);
    perform pg_temp._as_user(p1u); res := roll_and_move(gid, gen_random_uuid(), pg_temp._ver(gid));
    if res->>'jail_result' = 'failed' then okfail := true; exit; end if;
  end loop;
  perform pg_temp._as_admin(); insert into public.game_held_cards(game_id,player_ref,card_ref) values (gid,p1,'chance-jail-free') on conflict do nothing;
  perform pg_temp._as_user(p1u);
  begin perform roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okroll:=(sqlerrm='JAIL_ACTION_ALREADY_TAKEN'); end;
  begin perform pay_jail_release(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okpay:=(sqlerrm='JAIL_ACTION_ALREADY_TAKEN'); end;
  begin perform use_jail_card(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okcard:=(sqlerrm='JAIL_ACTION_ALREADY_TAKEN'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('A1) tras fallar dobles: intentar/pagar/usar carta → JAIL_ACTION_ALREADY_TAKEN', okfail and okroll and okpay and okcard);
end $$;

-- A2) el snapshot refleja la acción tomada (action_taken_this_turn = true) y sigue preso.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; begin
  perform pg_temp._as_user(p1u); snap := get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  perform pg_temp._rec('A2) snapshot: my_jail.action_taken_this_turn=true y sigue preso',
    (snap->'my_jail'->>'action_taken_this_turn')='true' and pg_temp._injail(gid,p1));
end $$;

-- A3) al volver a tocarle (nuevo turno por end_turn), vuelve a poder intentar.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); cur text; uid text; res jsonb; ok boolean:=false; i int; begin
  -- avanza turnos hasta que vuelva a ser de P1 (P1 termina, el otro termina).
  for i in 1..4 loop
    cur := pg_temp._cur(gid);
    if cur = p1 and i > 1 then exit; end if;
    uid := pg_temp._uid(gid,cur);
    perform pg_temp._as_user(uid); perform end_turn(gid, pg_temp._ver(gid), gen_random_uuid());
    perform pg_temp._as_admin();
  end loop;
  -- ahora es de P1 otra vez, sigue preso, action_turn del turno anterior → puede intentar.
  perform pg_temp._as_user(p1u);
  begin res := roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid)); ok := res ? 'jail_result'; exception when others then ok:=false; end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('A3) al volver a tocarle puede intentar de nuevo', pg_temp._cur(gid)=p1 and ok);
end $$;

-- A4) pagar 50 libera y deja sin otros métodos ese turno (usar carta → NOT_IN_JAIL tras pagar).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); okrel boolean; okblk boolean:=false; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,0); update public.player_balances set balance=3000 where game_id=gid and player_ref=p1;
  perform pg_temp._as_user(p1u); perform pay_jail_release(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); okrel := not pg_temp._injail(gid,p1);
  perform pg_temp._as_user(p1u);
  begin perform use_jail_card(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okblk:=(sqlerrm='NOT_IN_JAIL'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('A4) pagar 50 libera; usar carta tras pagar → NOT_IN_JAIL', okrel and okblk);
end $$;

-- A5) usar carta libera y bloquea pagar ese turno (pagar tras carta → NOT_IN_JAIL).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); okrel boolean; okblk boolean:=false; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,0);
  insert into public.game_held_cards(game_id,player_ref,card_ref) values (gid,p1,'chance-jail-free') on conflict do nothing;
  perform pg_temp._as_user(p1u); perform use_jail_card(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); okrel := not pg_temp._injail(gid,p1);
  perform pg_temp._as_user(p1u);
  begin perform pay_jail_release(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okblk:=(sqlerrm='NOT_IN_JAIL'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('A5) usar carta libera; pagar tras carta → NOT_IN_JAIL', okrel and okblk);
end $$;

-- A6) pausa/finalización y no-current bloquean las acciones de cárcel.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid');
            okpause boolean:=false; okfin boolean:=false; oknc boolean:=false; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,0);
  perform pg_temp._as_user(host); perform host_set_turn(gid,p1,'turno P1',gen_random_uuid(),pg_temp._ver(gid));
  -- no-current: el anfitrión (no en turno) no puede pagar la salida de P1.
  perform pg_temp._as_user(host);
  begin perform pay_jail_release(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then oknc:=(sqlerrm='NOT_CURRENT_PLAYER'); end;
  -- pausa.
  perform pg_temp._as_user(host); perform pause_game_runtime(gid,'',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u);
  begin perform pay_jail_release(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okpause:=(sqlerrm='GAME_PAUSED'); end;
  perform pg_temp._as_user(host); perform resume_game_runtime(gid,gen_random_uuid(),pg_temp._ver(gid));
  -- finalización.
  perform pg_temp._as_user(host); perform finish_game_runtime(gid,'',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u);
  begin perform pay_jail_release(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okfin:=(sqlerrm='GAME_FINISHED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('A6) no-current (NOT_CURRENT_PLAYER), pausa (GAME_PAUSED) y fin (GAME_FINISHED) bloquean', oknc and okpause and okfin);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── jail_action_once_phase5: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
