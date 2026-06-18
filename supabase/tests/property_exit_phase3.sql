-- ============================================================================
-- Expulsión por anfitrión devuelve propiedades a banca (Fase 3 corrección, catálogo real).
-- Tras `supabase db reset`.
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
create or replace function pg_temp._owner(gid uuid, ref text) returns text language sql security definer as $f$
  select owner_ref from public.property_ownership where game_id=gid and property_ref=ref and released_at is null $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='ad000000-0000-0000-0000-0000000000a1';
        u text[]:=array['ad000000-0000-0000-0000-000000000001','ad000000-0000-0000-0000-000000000002'];
        toks text[]:=array['cat','boot']; r jsonb; gid uuid; code text; v int; ref text; i int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Exit IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  for i in 1..2 loop perform pg_temp._as_user(u[i]); perform join_game(code,'P'||i,gen_random_uuid());
    perform pg_temp._as_admin(); select public_ref into ref from players where game_id=gid and auth_uid=u[i]::uuid;
    insert into _ctx values ('p'||i,ref),('p'||i||'_uid',u[i]);
    perform pg_temp._as_user(u[i]); perform choose_token(gid,toks[i]); perform set_ready(gid,true); end loop;
  perform pg_temp._as_user(host); perform choose_token(gid,'thimble'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- p1 adquiere cl-fuencarral vía aprobación.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1u text:=pg_temp._ctx('p1_uid'); rref text; begin
  perform pg_temp._as_user(p1u); perform request_property_purchase(gid,'cl-fuencarral',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into rref from property_purchase_requests where game_id=gid and property_ref='cl-fuencarral' and status='pending';
  perform pg_temp._as_user(host); perform resolve_property_purchase(rref,true,pg_temp._ver(gid)); perform pg_temp._as_admin();
end $$;

-- E1) el anfitrión expulsa a p1 (a banca): propiedad vuelve a banca; p1 fuera del orden.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); own text; in_order boolean; begin
  perform pg_temp._as_user(host); perform remove_active_player(gid, p1, 'to_bank', 'expulsado', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin();
  own := pg_temp._owner(gid,'cl-fuencarral'); select p1 = any(turn_order_refs) into in_order from game_runtime where game_id=gid;
  perform pg_temp._rec('E1) expulsión devuelve la propiedad a banca y saca del orden', own is null and not in_order);
end $$;

-- E2) la propiedad devuelta puede recomprarse (vía aprobación) por otro.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref'); rref text; own text; begin
  perform pg_temp._as_user(host); perform request_property_purchase(gid,'cl-fuencarral',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into rref from property_purchase_requests where game_id=gid and property_ref='cl-fuencarral' and status='pending';
  perform pg_temp._as_user(host); perform resolve_property_purchase(rref,true,pg_temp._ver(gid));
  perform pg_temp._as_admin(); own := pg_temp._owner(gid,'cl-fuencarral');
  perform pg_temp._rec('E2) propiedad devuelta se recompra (vía aprobación)', own=host_ref);
end $$;

-- E3) la devolución por expulsión no crea ledger monetario de propiedad.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; n int; begin
  perform pg_temp._as_admin(); select count(*) into n from ledger where game_id=gid and kind ilike '%return%';
  perform pg_temp._rec('E3) devolución de propiedad sin ledger monetario (solo auditoría)', n=0);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── property_exit_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
