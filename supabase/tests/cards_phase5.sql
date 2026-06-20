-- ============================================================================
-- Cartas (Fase 5): caer en una casilla de carta roba del mazo y aplica el efecto soportado (cobrar/pagar
-- banca, ir a salida, ir a cárcel, conservable); las no soportadas quedan en resolución manual. Tras `db reset`.
-- El orden del mazo se fija a mano para ser determinista.
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
create or replace function pg_temp._bal(gid uuid, ref text) returns bigint language sql security definer as $f$ select balance from public.player_balances where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._pos(gid uuid, ref text) returns int language sql security definer as $f$ select space_index from public.player_positions where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._injail(gid uuid, ref text) returns boolean language sql security definer as $f$ select exists(select 1 from public.game_jail where game_id=gid and player_ref=ref) $f$;
-- Fija el mazo 'chance' con una sola carta concreta para que sea la próxima robada.
create or replace function pg_temp._stack(gid uuid, ref text) returns void language plpgsql security definer as $f$
begin perform public._p5_ensure_decks(gid);
  update public.game_card_decks set draw_pile = array[ref] where game_id=gid and deck_key='chance'; end $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='ba000000-0000-0000-0000-0000000000a1'; j1 text:='ba000000-0000-0000-0000-000000000001';
        j2 text:='ba000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Cards IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- helper: deja al jugador actual 1 antes de la casilla de Suerte (idx 7) y lo mueve para robar.
-- (Suerte = mazo 'chance' en classic, índices 7/22/36.)

-- C1/C2) caer en carta roba; carta de cobrar banca aplica (saldo +200).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; snap jsonb; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_admin(); perform pg_temp._stack(gid,'chance-credit-200'); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',6,'antes de suerte',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  perform pg_temp._rec('C1/C2) robar carta + cobrar banca (saldo +200, last_card_draw)',
    pg_temp._bal(gid,cur)=b0+200 and (snap->'last_card_draw'->>'card_ref')='chance-credit-200'
    and (snap->'last_card_draw'->>'player_ref')=cur);
end $$;

-- C3) carta de pagar banca aplica (saldo -50).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_admin(); perform pg_temp._stack(gid,'chance-debit-50'); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',6,'antes de suerte',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('C3) pagar banca (saldo -50)', pg_temp._bal(gid,cur)=b0-50);
end $$;

-- C4) carta de ir a Salida mueve a idx 0 y cobra el sueldo (+200).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; b0 bigint; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_admin(); perform pg_temp._stack(gid,'chance-to-start'); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',6,'antes de suerte',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('C4) ir a Salida: pos 0 y cobra 200', pg_temp._pos(gid,cur)=0 and pg_temp._bal(gid,cur)=b0+200);
end $$;

-- C5) carta de ir a la cárcel encarcela (pos 10, in_jail).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); begin
  perform pg_temp._as_user(host); perform host_set_turn(gid,p1,'turno P1 carta cárcel',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); perform pg_temp._stack(gid,'chance-to-jail');
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p1,'classic',6,'antes de suerte',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('C5) ir a la cárcel: in_jail y pos 10', pg_temp._injail(gid,p1) and pg_temp._pos(gid,p1)=10);
  -- libera a P1 para no dejar estado de cárcel colgando en tests siguientes.
  delete from public.game_jail where game_id=gid and player_ref=p1;
end $$;

-- C6) carta conservable (Sal de la cárcel gratis) queda en inventario y NO se descarta.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; n int; begin
  perform pg_temp._as_user(host); perform host_set_turn(gid,p1,'turno P1 conservable',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); perform pg_temp._stack(gid,'chance-jail-free');
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p1,'classic',6,'antes de suerte',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  select count(*) into n from public.game_held_cards where game_id=gid and player_ref=p1 and card_ref='chance-jail-free';
  perform pg_temp._rec('C6) carta conservable en inventario (my_held_cards) y no descartada',
    n=1 and jsonb_array_length(snap->'my_held_cards')>=1
    and not ('chance-jail-free' = any(select jsonb_array_elements_text(to_jsonb((select discard_pile from public.game_card_decks where game_id=gid and deck_key='chance'))))));
end $$;

-- C7) carta no soportada → resolución manual: pending_card de su dueño, bloquea end_turn, resolve_card limpia.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid');
            snap jsonb; okpend boolean; okblock boolean:=false; okresolved boolean; begin
  perform pg_temp._as_user(host); perform host_set_turn(gid,p1,'turno P1 manual',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); perform pg_temp._stack(gid,'chance-manual');
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p1,'classic',6,'antes de suerte',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  okpend := (snap->'pending_card'->>'card_ref')='chance-manual';
  begin perform end_turn(gid,pg_temp._ver(gid),gen_random_uuid()); exception when others then okblock:=(sqlerrm='CARD_PENDING'); end;
  perform pg_temp._as_user(p1u); perform resolve_card(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  okresolved := snap->'pending_card' is null or snap->'pending_card'='null'::jsonb;
  perform pg_temp._rec('C7) carta manual: pending_card, bloquea end_turn (CARD_PENDING) y resolve_card limpia',
    okpend and okblock and okresolved);
end $$;

-- C8) cobrar de cada jugador (each_player_credit): los demás me pagan lo que puedan.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); b0 bigint; begin
  perform pg_temp._as_user(host); perform host_set_turn(gid,p1,'turno P1 cada jugador',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); perform pg_temp._stack(gid,'chance-each-credit'); b0:=pg_temp._bal(gid,p1);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p1,'classic',6,'antes de suerte',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  -- 2 oponentes (host + P2) pagan 20 cada uno = +40.
  perform pg_temp._rec('C8) cobrar de cada jugador (+40 de 2 oponentes)', pg_temp._bal(gid,p1)=b0+40);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── cards_phase5: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
