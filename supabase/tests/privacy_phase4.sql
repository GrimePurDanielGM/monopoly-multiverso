-- ============================================================================
-- Privacidad de saldos (Fase 4 corrección): cada jugador solo ve su propio saldo (ni el anfitrión ve
-- los ajenos); los movimientos siguen visibles; la subasta rechaza pujas sin fondos sin revelar saldo.
-- Host + 1 jugador. Tras `supabase db reset`.
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
declare host text:='fa000000-0000-0000-0000-0000000000f1'; j1 text:='fa000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Priv IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- V1) yo (p1) veo mi saldo; no veo el del anfitrión.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); p1u text:=pg_temp._ctx('p1_uid'); p1 text:=pg_temp._ctx('p1'); host_ref text:=pg_temp._ctx('host_ref'); snap jsonb; mine jsonb; other jsonb; begin
  perform pg_temp._as_user(p1u); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  select p into mine  from jsonb_array_elements(snap->'players') p where p->>'public_ref'=p1;
  select p into other from jsonb_array_elements(snap->'players') p where p->>'public_ref'=host_ref;
  perform pg_temp._rec('V1) jugador ve su saldo (me) y NO el ajeno (null)',
    (snap->'me'->>'balance')::bigint = 3000 and (mine->>'balance')::bigint = 3000 and (other->'balance')='null'::jsonb);
end $$;

-- V2) el ANFITRIÓN tampoco ve los saldos ajenos (también juega).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); host_ref text:=pg_temp._ctx('host_ref'); snap jsonb; mine jsonb; other jsonb; begin
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  select p into mine  from jsonb_array_elements(snap->'players') p where p->>'public_ref'=host_ref;
  select p into other from jsonb_array_elements(snap->'players') p where p->>'public_ref'=p1;
  perform pg_temp._rec('V2) el anfitrión ve su saldo pero NO el de los demás',
    (mine->>'balance')::bigint = 3000 and (other->'balance')='null'::jsonb);
end $$;

-- V3) los movimientos (ledger) siguen mostrando importes (control del flujo).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; n int; begin
  perform pg_temp._as_user(p1u); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  select count(*) into n from jsonb_array_elements(snap->'ledger_recent') l where (l->>'amount')::bigint > 0;
  perform pg_temp._rec('V3) los movimientos recientes siguen mostrando importes', n >= 2);  -- siembras
end $$;

-- V4) la subasta rechaza una puja sin fondos con error saneado (sin revelar el saldo).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); aref text; msg text:=''; ok boolean:=false; begin
  perform pg_temp._as_user(host); perform host_adjust_balance(gid, p1, 50, 'dejar sin fondos (test)', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_user(host); perform start_property_auction(gid,'cl-prado',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); select public_ref into aref from property_auctions where game_id=gid and property_ref='cl-prado' and status='active';
  perform pg_temp._as_user(p1u);
  begin perform place_property_bid(gid,aref,100,gen_random_uuid(),pg_temp._ver(gid)); exception when others then msg:=sqlerrm; end;
  perform pg_temp._as_admin();
  -- error saneado: exactamente INSUFFICIENT_FUNDS, sin cifras del saldo.
  ok := (msg = 'INSUFFICIENT_FUNDS') and (msg !~ '[0-9]');
  perform pg_temp._rec('V4) puja sin fondos: INSUFFICIENT_FUNDS saneado (no revela saldo)', ok);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── privacy_phase4: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
