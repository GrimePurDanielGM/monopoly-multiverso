-- ============================================================================
-- Propiedades + salida/expulsión (Fase 3): al salir o ser expulsado, las propiedades
-- vuelven a banca (auditado, sin ledger monetario) y pueden recomprarse. Conserva historial.
-- Tras `supabase db reset`.
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
create or replace function pg_temp._owner(p_gid uuid, p_ref text) returns text language sql security definer as $f$
  select owner_ref from public.property_ownership where game_id=p_gid and property_ref=p_ref and released_at is null $f$;

-- Partida con anfitrión + 2 jugadores (min=2).
create or replace function pg_temp._build3() returns void language plpgsql as $f$
declare host text:='f0000000-0000-0000-0000-0000000000a1';
        u text[]:=array['f0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000002'];
        toks text[]:=array['cat','boot']; r jsonb; gid uuid; code text; v_ver int; ref text; i int;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Exit3 IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- P1 compra cl-marron-1; P2 compra cl-celeste-1.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; v_ver bigint; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._ctx('p1_uid')); perform buy_property(gid,'cl-marron-1',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._ctx('p2_uid')); perform buy_property(gid,'cl-celeste-1',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin();
end $$;

-- X1) P1 ABANDONA -> su propiedad (cl-marron-1) vuelve a banca; queda registro de historial.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); v_ver bigint;
            owner_after text; hist int; ev int; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._ctx('p1_uid')); perform leave_active_game(gid,'to_bank',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin();
  owner_after := pg_temp._owner(gid,'cl-marron-1');
  select count(*) into hist from property_ownership where game_id=gid and property_ref='cl-marron-1'; -- fila histórica conservada
  select count(*) into ev from audit_events where game_id=gid and type='properties_returned_to_bank';
  perform pg_temp._rec('X1) abandono devuelve la propiedad a banca (disponible), conserva historial y audita',
    owner_after is null and hist=1 and ev>=1);
end $$;

-- X2) el anfitrión EXPULSA a P2 -> su propiedad (cl-celeste-1) vuelve a banca.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p2 text:=pg_temp._ctx('p2'); host text:=pg_temp._ctx('host');
            v_ver bigint; owner_after text; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform remove_active_player(gid, p2, 'to_bank', 'expulsado', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  owner_after := pg_temp._owner(gid,'cl-celeste-1');
  perform pg_temp._rec('X2) expulsión devuelve la propiedad a banca', owner_after is null);
end $$;

-- X3) una propiedad devuelta puede RECOMPRARSE (nuevo episodio de posesión).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref');
            v_ver bigint; owner_after text; episodes int; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform buy_property(gid,'cl-marron-1',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin();
  owner_after := pg_temp._owner(gid,'cl-marron-1');
  select count(*) into episodes from property_ownership where game_id=gid and property_ref='cl-marron-1';
  perform pg_temp._rec('X3) propiedad devuelta se recompra (nuevo propietario, 2 episodios en historial)',
    owner_after=host_ref and episodes=2);
end $$;

-- X4) ningún ledger monetario de "devolución" (la devolución es auditoría, no dinero).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; n int; begin
  perform pg_temp._as_admin();
  select count(*) into n from ledger where game_id=gid and kind ilike '%return%';
  perform pg_temp._rec('X4) la devolución no crea ledger monetario (solo auditoría)', n=0);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── property_exit_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
