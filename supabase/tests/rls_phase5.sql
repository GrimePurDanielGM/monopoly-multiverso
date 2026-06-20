-- ============================================================================
-- RLS Fase 5: las tablas internas nuevas (game_jail, card_catalog, game_card_decks, game_held_cards)
-- son deny-all para authenticated (sin SELECT directo); el estado solo se expone vía snapshot saneado.
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

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='bc000000-0000-0000-0000-0000000000a1'; j1 text:='bc000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Rls5 IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- R1) game_jail: deny-all (SELECT directo prohibido).
do $$ declare host text:=pg_temp._ctx('host'); ok boolean:=false; n int; begin
  perform pg_temp._as_user(host);
  begin select count(*) into n from public.game_jail; exception when insufficient_privilege then ok:=true; when others then ok:=false; end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R1) game_jail deny-all (sin SELECT directo)', ok);
end $$;

-- R2) card_catalog: deny-all.
do $$ declare host text:=pg_temp._ctx('host'); ok boolean:=false; n int; begin
  perform pg_temp._as_user(host);
  begin select count(*) into n from public.card_catalog; exception when insufficient_privilege then ok:=true; when others then ok:=false; end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R2) card_catalog deny-all', ok);
end $$;

-- R3) game_card_decks: deny-all (no se filtra el orden de las cartas).
do $$ declare host text:=pg_temp._ctx('host'); ok boolean:=false; n int; begin
  perform pg_temp._as_user(host);
  begin select count(*) into n from public.game_card_decks; exception when insufficient_privilege then ok:=true; when others then ok:=false; end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R3) game_card_decks deny-all', ok);
end $$;

-- R4) game_held_cards: deny-all (el inventario ajeno no es accesible directamente).
do $$ declare host text:=pg_temp._ctx('host'); ok boolean:=false; n int; begin
  perform pg_temp._as_user(host);
  begin select count(*) into n from public.game_held_cards; exception when insufficient_privilege then ok:=true; when others then ok:=false; end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R4) game_held_cards deny-all', ok);
end $$;

-- R5) las RPC de Fase 5 son SECURITY DEFINER, ejecutables por authenticated, y exigen sesión (auth.uid()).
do $$ declare okdef boolean; okauth boolean; n int; okguard boolean:=false; begin
  perform pg_temp._as_admin();
  select bool_and(p.prosecdef), bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')), count(*)
    into okdef, okauth, n
    from pg_proc p join pg_namespace nn on nn.oid=p.pronamespace
    where nn.nspname='public' and p.proname in ('pay_jail_release','use_jail_card','resolve_card','pay_pending');
  -- sin sesión: la RPC rechaza (NOT_AUTHENTICATED), nunca opera anónima.
  perform set_config('request.jwt.claims', NULL, true); perform set_config('role','authenticated',true);
  begin perform pay_jail_release(pg_temp._ctx('gid')::uuid, gen_random_uuid(), 0); exception when others then okguard:=true; end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('R5) RPC Fase 5: SECURITY DEFINER, authenticated, exigen sesión (rechaza sin auth)',
    okdef and okauth and n=4 and okguard);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── rls_phase5: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
