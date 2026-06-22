-- ============================================================================
-- Feature E — Retorno de inversión al pasar por Salida. Tras `db reset`.
-- Con start_invest_pct>0, al pasar por Salida se cobra 200 € + pct% del valor de propiedades+casas+hoteles.
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
create or replace function pg_temp._own(gid uuid, prop text, ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,ref) on conflict do nothing $f$;
create or replace function pg_temp._setpct(gid uuid, n int) returns void language sql security definer as $f$ update public.games set config = config || jsonb_build_object('start_invest_pct', n) where id=gid $f$;
-- pasa por Salida: coloca en idx 38 y mueve 3 (38→1, cruza Salida en 0).
create or replace function pg_temp._passgo(gid uuid) returns void language plpgsql as $f$
declare host text:=pg_temp._ctx('host'); cur text:=pg_temp._cur(gid); uid text:=pg_temp._uid(gid,cur); begin
  perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',38,'pre',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); update public.games set config = config || jsonb_build_object('dice_mode','physical_allowed') where id=gid;
  perform pg_temp._as_user(uid); perform move_with_physical_roll(gid,1,2,gen_random_uuid(),pg_temp._ver(gid));  -- 3 pasos: 38→1
  perform pg_temp._as_admin(); end $f$;
create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='cd000000-0000-0000-0000-0000000000a1'; j1 text:='cd000000-0000-0000-0000-000000000001';
        j2 text:='cd000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Invest E','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j2); perform join_game(code,'P2',gen_random_uuid());
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(j2); perform choose_token(gid,'roadster'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
  update public.player_balances set balance=100000 where game_id=gid;
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- E0) pct=0 (por defecto): pasar por Salida cobra solo 200.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); b0 bigint; begin
  perform pg_temp._setpct(gid,0); perform pg_temp._own(gid,'cl-gran-via',cur); b0:=pg_temp._bal(gid,cur);
  perform pg_temp._passgo(gid);
  perform pg_temp._rec('E0) pct=0: pasar por Salida cobra solo 200', pg_temp._bal(gid,cur)=b0+200);
end $$;

-- E1) pct=10 con Gran Vía (320 €) en propiedad: cobra 200 + 32 = 232.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); b0 bigint; v_extra int; begin
  perform pg_temp._setpct(gid,10);
  -- valor = price Gran Vía (sin construcciones). extra = floor(320*10/100)=32.
  select floor(c.price*10/100.0)::int into v_extra from public.property_catalog c where c.property_ref='cl-gran-via';
  b0:=pg_temp._bal(gid,cur);
  perform pg_temp._passgo(gid);
  perform pg_temp._rec('E1) pct=10: pasar por Salida cobra 200 + 10% del valor (Gran Vía)', pg_temp._bal(gid,cur)=b0+200+v_extra and v_extra=32);
end $$;

-- E2) las construcciones cuentan: añade casas a una calle propia y el retorno sube.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); b0 bigint; v_extra int; begin
  perform pg_temp._own(gid,'cl-ronda-valencia',cur);
  insert into public.game_property_state(game_id,property_ref,houses) values (gid,'cl-ronda-valencia',3)
    on conflict (game_id,property_ref) do update set houses=3;
  perform pg_temp._setpct(gid,10);
  select floor((sum(c.price) + 3*(select house_cost from public.property_catalog where property_ref='cl-ronda-valencia'))*10/100.0)::int
    into v_extra from public.property_catalog c where c.property_ref in ('cl-gran-via','cl-ronda-valencia');
  b0:=pg_temp._bal(gid,cur);
  perform pg_temp._passgo(gid);
  perform pg_temp._rec('E2) el retorno incluye el valor de las casas', pg_temp._bal(gid,cur)=b0+200+v_extra);
end $$;

-- E3) la opción se persiste y se expone en el snapshot del lobby (partida nueva en lobby).
do $$ declare host text:='cd000000-0000-0000-0000-0000000000b9'; r jsonb; gid2 uuid; code2 text; v int; snap jsonb; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Invest lobby','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid2:=(r->>'game_id')::uuid; code2:=r->>'code';
  perform pg_temp._as_admin(); select version into v from games where id=gid2;
  perform pg_temp._as_user(host); perform update_config(gid2, jsonb_build_object('start_invest_pct',25), v);
  snap := get_lobby_snapshot_by_code(code2); perform pg_temp._as_admin();
  perform pg_temp._rec('E3) update_config guarda start_invest_pct y el snapshot del lobby lo expone',
    (snap->'game'->'config'->>'start_invest_pct')::int = 25);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
