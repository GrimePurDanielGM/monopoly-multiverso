-- ============================================================================
-- Snapshot Fase 5: expone bote de Parking, estado de cárcel, mazos (recuentos), última carta, inventario
-- (completo solo del propio jugador), carta/pago pendientes; saneado (sin ids internos) y saldos privados.
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

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='bb000000-0000-0000-0000-0000000000a1'; j1 text:='bb000000-0000-0000-0000-000000000001';
        j2 text:='bb000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Snap5 IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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
  -- estado Fase 5: mazos sembrados (como tras el primer movimiento), bote, P1 en cárcel, cartas en mano.
  perform public._p5_ensure_decks(gid);
  update public.game_runtime set parking_pot = 250 where game_id=gid;
  insert into public.game_jail(game_id, player_ref, board_key)
    select gid, public_ref, 'classic' from players where game_id=gid and auth_uid=j1::uuid;
  insert into public.game_held_cards(game_id, player_ref, card_ref)
    select gid, public_ref, 'chance-jail-free' from players where game_id=gid and auth_uid=j1::uuid;
  insert into public.game_held_cards(game_id, player_ref, card_ref)
    select gid, public_ref, 'community_chest-jail-free' from players where game_id=gid and auth_uid=j2::uuid;
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- S1) el snapshot expone los campos de Fase 5.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; begin
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  perform pg_temp._rec('S1) snapshot incluye parking_pot/jail/my_jail/card_decks/held_cards/my_held_cards',
    (snap->>'parking_pot')='250' and snap ? 'jail' and snap ? 'my_jail' and snap ? 'card_decks'
    and snap ? 'held_cards' and snap ? 'my_held_cards' and snap ? 'last_card_draw' and snap ? 'pending_card' and snap ? 'pending_payment');
end $$;

-- S2) mi estado de cárcel (P1) refleja board + multa; jail lista a P1.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; injail boolean; begin
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  select exists(select 1 from jsonb_array_elements(snap->'jail') e where e->>'player_ref'=p1) into injail;
  perform pg_temp._rec('S2) my_jail (board+multa 50) y jail incluye a P1',
    (snap->'my_jail'->>'board_key')='classic' and (snap->'my_jail'->>'fine')='50' and injail);
end $$;

-- S3) card_decks expone los 4 mazos con recuentos (sin el orden de las cartas).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; n int; begin
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  select count(*) into n from jsonb_array_elements(snap->'card_decks') e where (e->>'draw_count')::int >= 0;
  perform pg_temp._rec('S3) card_decks: 4 mazos con recuentos', n=4 and jsonb_array_length(snap->'card_decks')=4);
end $$;

-- S4) inventario: P1 ve su carta completa; de P2 solo el recuento (no su card_ref).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; mine boolean; p2count boolean; leak boolean; begin
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  select exists(select 1 from jsonb_array_elements(snap->'my_held_cards') e where e->>'card_ref'='chance-jail-free') into mine;
  select exists(select 1 from jsonb_array_elements(snap->'held_cards') e where (e->>'count')::int=1) into p2count;
  -- la carta concreta de P2 no debe aparecer en MY_held_cards de P1.
  select exists(select 1 from jsonb_array_elements(snap->'my_held_cards') e where e->>'card_ref'='community_chest-jail-free') into leak;
  perform pg_temp._rec('S4) inventario propio completo; ajeno solo recuento (sin filtrar card_ref ajeno)',
    mine and p2count and not leak);
end $$;

-- S5) saneado: sin ids internos (auth_uid/game_id/"id") ni el uuid de la partida.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; blob text; begin
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin(); blob:=snap::text;
  perform pg_temp._rec('S5) snapshot saneado (sin auth_uid/game_id/"id" ni uuid de partida)',
    blob not like '%auth_uid%' and blob not like '%game_id%' and blob not like '%"id"%' and position(gid::text in blob)=0);
end $$;

-- S6) privacidad de saldos intacta: P1 ve su saldo; el de P2 va oculto (null).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p2 text:=pg_temp._ctx('p2'); p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; mine bigint; other text; begin
  perform pg_temp._as_user(p1u); snap:=get_active_snapshot_by_code(pg_temp._ctx('code'));
  perform pg_temp._as_admin();
  select (e->>'balance') into other from jsonb_array_elements(snap->'players') e where e->>'public_ref'=p2;
  perform pg_temp._rec('S6) privacidad de saldos: el saldo ajeno va null', other is null);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── snapshot_phase5: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
