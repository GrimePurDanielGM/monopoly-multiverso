-- ============================================================================
-- Reconciliación monetaria con propiedades (Fase 3): tras compras, alquileres y una
-- salida, se mantiene saldo = entradas - salidas para cada jugador. La devolución de
-- propiedades NO mueve dinero. Tras `supabase db reset`.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
drop table if exists _ctx; create temp table _ctx(k text primary key, v text);
grant select, insert, update, delete on _t, _ctx to authenticated;
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if;
end $f$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $f$
begin perform set_config('role', session_user, true); end $f$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;
create or replace function pg_temp._ctx(k text) returns text language sql as $f$ select v from _ctx where k=$1 $f$;
create or replace function pg_temp._reconciles(p_gid uuid) returns boolean language sql security definer as $f$
  select not exists (
    select 1 from public.player_balances b
    where b.game_id = p_gid and b.balance <> (
      coalesce((select sum(amount) from public.ledger where game_id=p_gid and to_ref=b.player_ref),0)
      - coalesce((select sum(amount) from public.ledger where game_id=p_gid and from_ref=b.player_ref),0)));
$f$;

create or replace function pg_temp._build3() returns void language plpgsql as $f$
declare host text:='c1000000-0000-0000-0000-0000000000a1';
        u text[]:=array['c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002'];
        toks text[]:=array['cat','boot']; r jsonb; gid uuid; code text; v_ver int; ref text; i int;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Recon IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid; code := r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v_ver);
  for i in 1..2 loop
    perform pg_temp._as_user(u[i]); perform join_game(code,'P'||i,gen_random_uuid());
    perform pg_temp._as_admin(); select public_ref into ref from players where game_id=gid and auth_uid=u[i]::uuid;
    insert into _ctx values ('p'||i, ref),('p'||i||'_uid', u[i]);
    perform pg_temp._as_user(u[i]); perform choose_token(gid, toks[i]); perform set_ready(gid,true);
  end loop;
  perform pg_temp._as_user(host); perform choose_token(gid,'thimble'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid, v_ver);
  perform pg_temp._as_admin();
end $f$;

do $$ begin perform pg_temp._build3(); end $$;

-- Secuencia: P1 compra estación; P2 compra calle; host paga alquiler a P1; P2 abandona (con su propiedad a banca).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_ver bigint; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._ctx('p1_uid')); perform buy_property(gid,'cl-estacion-1',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._ctx('p2_uid')); perform buy_property(gid,'cl-celeste-1',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._ctx('host')); perform pay_rent(gid,'cl-estacion-1',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._ctx('p2_uid')); perform leave_active_game(gid,'to_bank',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin();
end $$;

-- C1) reconciliación monetaria intacta tras compras + alquiler + salida.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; begin
  perform pg_temp._as_admin();
  perform pg_temp._rec('C1) saldo = entradas - salidas para todos (con propiedades)', pg_temp._reconciles(gid));
end $$;

-- C2) la devolución de propiedad de P2 no movió dinero (no hay ledger de devolución).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; n int; owner text; begin
  perform pg_temp._as_admin();
  select count(*) into n from ledger where game_id=gid and kind ilike '%return%';
  select owner_ref into owner from property_ownership where game_id=gid and property_ref='cl-celeste-1' and released_at is null;
  perform pg_temp._rec('C2) propiedad de P2 a banca sin ledger monetario', n=0 and owner is null);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── reconcile_properties_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
