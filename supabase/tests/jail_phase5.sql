-- ============================================================================
-- Cárcel (Fase 5): solo-visitas no encarcela; ve-a-la-cárcel encarcela (a idx 10, sin cobrar salida);
-- en la cárcel no se puede mover; salir pagando 50 (al bote) o con carta "Sal de la cárcel gratis". Tras `db reset`.
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
create or replace function pg_temp._pot(gid uuid) returns bigint language sql security definer as $f$ select parking_pot from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._injail(gid uuid, ref text) returns boolean language sql security definer as $f$ select exists(select 1 from public.game_jail where game_id=gid and player_ref=ref) $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='af000000-0000-0000-0000-0000000000a1'; j1 text:='af000000-0000-0000-0000-000000000001';
        j2 text:='af000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Jail IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- J1) caer EXACTAMENTE en Solo visitas/Cárcel (idx 10) NO encarcela.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; snap jsonb; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur);
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',9,'antes de cárcel',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(uid); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  perform pg_temp._rec('J1) solo visitas (idx 10) NO encarcela',
    not pg_temp._injail(gid,cur) and pg_temp._pos(gid,cur)=10 and (snap->'current_space'->>'space_type')='jail');
end $$;

-- J2/J3) caer en Ve a la cárcel (idx 30) encarcela (a idx 10) y NO cobra salida (saldo igual).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid');
            b0 bigint; b1 bigint; snap jsonb; begin
  perform pg_temp._as_user(host); perform host_set_turn(gid,p1,'turno P1 para cárcel',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform host_set_player_position(gid,p1,'classic',29,'antes de ve-a-la-cárcel',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,p1);
  perform pg_temp._as_user(p1u); perform move_player(gid,1,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,p1);
  perform pg_temp._rec('J2/J3) ve-a-la-cárcel encarcela (pos 10, in_jail) y no cobra salida (saldo igual)',
    pg_temp._injail(gid,p1) and pg_temp._pos(gid,p1)=10 and b1=b0
    and (snap->'my_jail'->>'board_key')='classic' and (snap->'last_move'->'effect'->>'type')='go_to_jail');
end $$;

-- J4) en la cárcel NO se puede mover (IN_JAIL).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); ok boolean:=false; okr boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform move_player(gid,3,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='IN_JAIL'); end;
  begin perform roll_and_move(gid,gen_random_uuid(),pg_temp._ver(gid)); exception when others then okr:=(sqlerrm='IN_JAIL'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('J4) en la cárcel no se puede mover/tirar (IN_JAIL)', ok and okr);
end $$;

-- J5) pagar 50 libera; saldo -50; el bote sube 50.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); b0 bigint; b1 bigint; pot0 bigint; begin
  perform pg_temp._as_admin(); b0:=pg_temp._bal(gid,p1); pot0:=pg_temp._pot(gid);
  perform pg_temp._as_user(p1u); perform pay_jail_release(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,p1);
  perform pg_temp._rec('J5) pagar 50 libera (saldo -50, bote +50, ya no in_jail)',
    not pg_temp._injail(gid,p1) and b1=b0-50 and pg_temp._pot(gid)=pot0+50);
end $$;

-- J6) carta "Sal de la cárcel gratis" libera sin coste y se descarta.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid');
            b0 bigint; b1 bigint; dn0 int; dn1 int; begin
  -- encarcela a P1 a mano y le da una carta jail_free.
  perform pg_temp._as_admin();
  insert into public.game_jail(game_id, player_ref, board_key) values (gid, p1, 'classic') on conflict do nothing;
  update public.player_positions set space_index=10, board_key='classic' where game_id=gid and player_ref=p1;
  insert into public.game_held_cards(game_id, player_ref, card_ref) values (gid, p1, 'chance-jail-free');
  b0:=pg_temp._bal(gid,p1);
  select coalesce(array_length(discard_pile,1),0) into dn0 from public.game_card_decks where game_id=gid and deck_key='chance';
  perform pg_temp._as_user(host); perform host_set_turn(gid,p1,'turno P1 carta cárcel',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); perform use_jail_card(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); b1:=pg_temp._bal(gid,p1);
  select coalesce(array_length(discard_pile,1),0) into dn1 from public.game_card_decks where game_id=gid and deck_key='chance';
  perform pg_temp._rec('J6) carta de cárcel libera sin coste y se descarta',
    not pg_temp._injail(gid,p1) and b1=b0
    and not exists(select 1 from public.game_held_cards where game_id=gid and player_ref=p1 and card_ref='chance-jail-free')
    and dn1=dn0+1);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── jail_phase5: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
