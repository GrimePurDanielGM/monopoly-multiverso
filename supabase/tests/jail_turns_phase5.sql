-- ============================================================================
-- Cárcel completa (Fase 5 corrección): intento de dobles, máximo 3 turnos, salida forzada al 3er fallo
-- (pago 50 o pendiente), salida por pago/carta, eventos de entrada/salida y evento global del bote.
-- Los dados son aleatorios: cada caso REPITE el intento hasta provocar la rama buscada. Tras `db reset`.
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
create or replace function pg_temp._uid(gid uuid, ref text) returns text language sql security definer as $f$ select auth_uid::text from public.players where game_id=gid and public_ref=ref $f$;
create or replace function pg_temp._bal(gid uuid, ref text) returns bigint language sql security definer as $f$ select balance from public.player_balances where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._pos(gid uuid, ref text) returns int language sql security definer as $f$ select space_index from public.player_positions where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._injail(gid uuid, ref text) returns boolean language sql security definer as $f$ select exists(select 1 from public.game_jail where game_id=gid and player_ref=ref) $f$;
create or replace function pg_temp._jturns(gid uuid, ref text) returns int language sql security definer as $f$ select jail_turns from public.game_jail where game_id=gid and player_ref=ref $f$;
-- Coloca al jugador en la cárcel del classic con N intentos previos y un saldo dado.
create or replace function pg_temp._prep_jail(gid uuid, ref text, turns int, bal bigint) returns void language plpgsql security definer as $f$
begin
  insert into public.game_jail(game_id,player_ref,board_key,jail_turns,action_turn) values (gid,ref,'classic',turns,0)
    on conflict (game_id,player_ref) do update set board_key='classic', jail_turns=turns, action_turn=0;
  update public.player_positions set board_key='classic', space_index=10 where game_id=gid and player_ref=ref;
  update public.player_balances set balance=bal where game_id=gid and player_ref=ref;
  update public.game_runtime set pending_payment=null where game_id=gid;
end $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='bd000000-0000-0000-0000-0000000000a1'; j1 text:='bd000000-0000-0000-0000-000000000001';
        j2 text:='bd000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('JailTurns IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j2); perform join_game(code,'P2',gen_random_uuid());
  perform pg_temp._as_admin();
  insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx select 'p2', public_ref from players where game_id=gid and auth_uid=j2::uuid;
  insert into _ctx values ('p1_uid',j1),('p2_uid',j2);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(j2); perform choose_token(gid,'roadster'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
  -- P1 será siempre el jugador de la cárcel; fijamos su turno.
  perform pg_temp._as_user(host); perform host_set_turn(gid,(select c.v from _ctx c where c.k='p1'),'turno P1',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- J1) en la cárcel SÍ se puede tirar (no IN_JAIL); el resultado es un intento.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,0,3000);
  perform pg_temp._as_user(p1u); res := roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J1) en la cárcel se puede intentar dobles (no IN_JAIL)', res ? 'jail_result');
end $$;

-- J2) dobles: libera (sin pagar) y mueve. (Repite hasta sacar dobles.)
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); res jsonb; ok boolean:=false; i int; begin
  for i in 1..80 loop
    perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,0,3000);
    perform pg_temp._as_user(p1u); res := roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid));
    if res->>'jail_result' = 'doubles' then
      perform pg_temp._as_admin();
      ok := not pg_temp._injail(gid,p1) and pg_temp._pos(gid,p1) <> 10; exit;
    end if;
  end loop;
  perform pg_temp._as_admin(); perform pg_temp._rec('J2) dobles libera (sin pagar) y mueve', ok);
end $$;

-- J3/J4) fallo (no dobles): suma intento y NO mueve. (Repite hasta un fallo.)
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); res jsonb; ok boolean:=false; i int; begin
  for i in 1..80 loop
    perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,0,3000);
    perform pg_temp._as_user(p1u); res := roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid));
    if res->>'jail_result' = 'failed' then
      perform pg_temp._as_admin();
      ok := pg_temp._injail(gid,p1) and pg_temp._jturns(gid,p1)=1 and pg_temp._pos(gid,p1)=10; exit;
    end if;
  end loop;
  perform pg_temp._as_admin(); perform pg_temp._rec('J3/J4) fallo suma intento (jail_turns=1) y no mueve', ok);
end $$;

-- J5) tercer fallo con saldo: paga 50 forzado (ledger), libera y mueve.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); res jsonb; ok boolean:=false; nlg int; i int; begin
  for i in 1..80 loop
    perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,2,3000);
    perform pg_temp._as_user(p1u); res := roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid));
    if res->>'jail_result' = 'forced_paid' then
      perform pg_temp._as_admin();
      select count(*) into nlg from public.ledger where game_id=gid and kind='jail_release_payment' and from_ref=p1 and amount=50;
      ok := not pg_temp._injail(gid,p1) and pg_temp._pos(gid,p1) <> 10 and nlg>=1; exit;
    elsif res->>'jail_result' = 'doubles' then null; -- reintenta
    end if;
  end loop;
  perform pg_temp._as_admin(); perform pg_temp._rec('J5) 3er fallo paga 50 forzado (ledger), libera y mueve', ok);
end $$;

-- J6) tercer fallo SIN saldo (30 < 50): queda pago pendiente jail_forced y sigue en la cárcel.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); res jsonb; snap jsonb; ok boolean:=false; i int; begin
  for i in 1..80 loop
    perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,2,30);
    perform pg_temp._as_user(p1u); res := roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid));
    if res->>'jail_result' = 'forced_pending' then
      perform pg_temp._as_user(p1u); snap := get_active_snapshot_by_code(pg_temp._ctx('code'));
      perform pg_temp._as_admin();
      ok := pg_temp._injail(gid,p1) and pg_temp._pos(gid,p1)=10
        and (snap->'pending_payment'->>'kind')='jail_forced' and (snap->'pending_payment'->>'amount')='50'; exit;
    end if;
  end loop;
  perform pg_temp._as_admin(); perform pg_temp._rec('J6) 3er fallo sin saldo: pago pendiente jail_forced, sigue preso', ok);
end $$;

-- J7) pagar pendiente jail_forced libera de la cárcel.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); ok boolean; begin
  -- desde el estado de J6: damos saldo y pagamos el pendiente.
  perform pg_temp._as_admin(); update public.player_balances set balance=200 where game_id=gid and player_ref=p1;
  perform pg_temp._as_user(p1u); perform pay_pending(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J7) pagar pendiente jail_forced libera de la cárcel', not pg_temp._injail(gid,p1));
end $$;

-- J8) pago manual de 50 (pay_jail_release) sigue liberando.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); b0 bigint; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,0,3000); b0:=pg_temp._bal(gid,p1);
  perform pg_temp._as_user(p1u); perform pay_jail_release(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J8) pago manual 50 libera (saldo -50)', not pg_temp._injail(gid,p1) and pg_temp._bal(gid,p1)=b0-50);
end $$;

-- J9) carta «Sal de la cárcel gratis» libera sin coste.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); b0 bigint; begin
  perform pg_temp._as_admin(); perform pg_temp._prep_jail(gid,p1,1,3000);
  insert into public.game_held_cards(game_id,player_ref,card_ref) values (gid,p1,'chance-jail-free');
  b0:=pg_temp._bal(gid,p1);
  perform pg_temp._as_user(p1u); perform use_jail_card(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J9) carta libera sin coste', not pg_temp._injail(gid,p1) and pg_temp._bal(gid,p1)=b0);
end $$;

-- J10) entrar en la cárcel deja evento auditado (sent_to_jail).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); host text:=pg_temp._ctx('host'); n int; begin
  perform pg_temp._as_admin(); delete from public.game_jail where game_id=gid and player_ref=p1;
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p1,'classic',29,'antes de ir a la cárcel',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform host_set_turn(gid,p1,'turno P1',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));  -- 29→30 ve a la cárcel
  perform pg_temp._as_admin();
  select count(*) into n from public.audit_events where game_id=gid and type='sent_to_jail';
  perform pg_temp._rec('J10) entrar en la cárcel audita sent_to_jail', pg_temp._injail(gid,p1) and n>=1);
end $$;

-- J11) cobrar el bote del Parking publica last_global_event (jugador + cantidad) en el snapshot de TODOS.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); p2u text:=pg_temp._ctx('p2_uid'); snap2 jsonb; begin
  perform pg_temp._as_admin();
  delete from public.game_jail where game_id=gid and player_ref=p1;
  update public.game_runtime set parking_pot=350, last_global_event=null where game_id=gid;
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p1,'classic',19,'antes de parking',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform host_set_turn(gid,p1,'turno P1',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));  -- 19→20 Parking
  -- el OTRO jugador (P2) también ve el evento global.
  perform pg_temp._as_user(p2u); snap2 := get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J11) cobro del bote publica last_global_event (visible para todos)',
    (snap2->'last_global_event'->>'kind')='parking_pot_payout' and (snap2->'last_global_event'->>'player_ref')=p1
    and (snap2->'last_global_event'->>'amount')='350');
end $$;

-- J12) el evento global NO filtra saldos ajenos (P2 sigue sin ver el saldo de P1).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p2u text:=pg_temp._ctx('p2_uid'); snap2 jsonb; other text; begin
  perform pg_temp._as_user(p2u); snap2 := get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  select (e->>'balance') into other from jsonb_array_elements(snap2->'players') e where e->>'public_ref'=p1;
  perform pg_temp._rec('J12) el banner global no expone saldos ajenos', other is null);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── jail_turns_phase5: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
