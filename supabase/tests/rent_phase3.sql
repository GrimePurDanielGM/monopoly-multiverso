-- ============================================================================
-- Alquiler sobre el catálogo real (Fase 3 corrección). Compra vía aprobación + pay_rent.
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

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='ac000000-0000-0000-0000-0000000000a1'; j1 text:='ac000000-0000-0000-0000-000000000001';
        r jsonb; gid uuid; code text; v int; ref text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Rent IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1',ref),('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- p1 adquiere cl-bailen (260, alquiler 22) vía aprobación del anfitrión.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1u text:=pg_temp._ctx('p1_uid'); rref text; begin
  perform pg_temp._as_user(p1u); perform request_property_purchase(gid,'cl-bailen',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into rref from property_purchase_requests where game_id=gid and property_ref='cl-bailen' and status='pending';
  perform pg_temp._as_user(host); perform resolve_property_purchase(rref,true,pg_temp._ver(gid)); perform pg_temp._as_admin();
end $$;

-- R1) el anfitrión paga alquiler 22 a p1; ledger rent_payment.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref'); p1 text:=pg_temp._ctx('p1');
            hb bigint; pb bigint; nled int; begin
  perform pg_temp._as_user(host); perform pay_rent(gid,'cl-bailen',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  select balance into hb from player_balances where game_id=gid and player_ref=host_ref;
  select balance into pb from player_balances where game_id=gid and player_ref=p1;
  select count(*) into nled from ledger where game_id=gid and kind='rent_payment' and from_ref=host_ref and to_ref=p1 and amount=22;
  perform pg_temp._rec('R1) alquiler 22: host 2978, propietario (3000-260)+22=2762, ledger rent_payment', hb=2978 and pb=2762 and nled=1);
end $$;

-- R2) no pagar alquiler a uno mismo (SELF_RENT).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1u text:=pg_temp._ctx('p1_uid'); ok boolean:=false; begin
  perform pg_temp._as_user(p1u);
  begin perform pay_rent(gid,'cl-bailen',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='SELF_RENT'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R2) no pagar alquiler de la propia propiedad (SELF_RENT)', ok);
end $$;

-- R3) utility sin alquiler por dados en esta fase: pay_rent no aplica (NO_RENT_DUE) aunque tenga dueño.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1u text:=pg_temp._ctx('p1_uid'); rref text; ok boolean:=false; begin
  perform pg_temp._as_user(p1u); perform request_property_purchase(gid,'cl-cia-aguas',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into rref from property_purchase_requests where game_id=gid and property_ref='cl-cia-aguas' and status='pending';
  perform pg_temp._as_user(host); perform resolve_property_purchase(rref,true,pg_temp._ver(gid));
  begin perform pay_rent(gid,'cl-cia-aguas',gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='NO_RENT_DUE'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('R3) utility comprable pero sin alquiler por dados aún (NO_RENT_DUE)', ok);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── rent_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
