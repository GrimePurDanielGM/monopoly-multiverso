-- ============================================================================
-- Reconciliación tras movimiento (Fase 4): el bonus por salida cuadra con el ledger y la masa
-- monetaria total se conserva (banca paga el bonus). Tras `supabase db reset`.
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
-- Saldo neto esperado de cada jugador según el ledger: Σ(to=ref) − Σ(from=ref).
create or replace function pg_temp._ledger_net(gid uuid, ref text) returns bigint language sql security definer as $f$
  select coalesce(sum(case when to_ref=ref then amount else 0 end),0)
       - coalesce(sum(case when from_ref=ref then amount else 0 end),0)
  from public.ledger where game_id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='ec000000-0000-0000-0000-0000000000e1'; j1 text:='ec000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Recon IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- Provoca varias vueltas por salida en el jugador actual.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); cur text; uid text; ring int; i int; begin
  cur:=pg_temp._cur(gid); uid:=pg_temp._uid(gid,cur); ring:=public._p4_ring_size('classic');
  for i in 1..3 loop
    perform pg_temp._as_user(host); perform host_set_player_position(gid,cur,'classic',ring-2,'preparar vuelta',gen_random_uuid(),pg_temp._ver(gid));
    perform pg_temp._as_user(uid); perform move_player(gid,4,gen_random_uuid(),pg_temp._ver(gid));  -- da la vuelta cada vez
    perform pg_temp._as_admin();
  end loop;
end $$;

-- C1) cada saldo coincide con su neto en el ledger (incluye 3 bonus de salida).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; bad int; begin
  select count(*) into bad from public.player_balances b
    where b.game_id=gid and b.balance <> pg_temp._ledger_net(gid, b.player_ref);
  perform pg_temp._rec('C1) saldo = neto del ledger para todos los jugadores', bad=0);
end $$;

-- C2) hay exactamente 3 ledgers pass_start_bonus de 200 para el jugador que dio las vueltas.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; cur text:=pg_temp._cur(gid); n int; begin
  select count(*) into n from public.ledger where game_id=gid and kind='pass_start_bonus' and to_ref=cur and amount=200;
  perform pg_temp._rec('C2) tres bonus de salida de 200 registrados', n=3);
end $$;

-- C3) la masa total = siembra inicial + bonus pagados por la banca (la banca crea ese dinero).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; total bigint; seed bigint; bonus bigint; begin
  select coalesce(sum(balance),0) into total from public.player_balances where game_id=gid;
  select coalesce(sum(amount),0) into seed  from public.ledger where game_id=gid and kind='seed';
  select coalesce(sum(amount),0) into bonus from public.ledger where game_id=gid and kind='pass_start_bonus';
  perform pg_temp._rec('C3) masa total = siembra + bonus de salida (sin fugas)', total = seed + bonus);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── reconcile_movement_phase4: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
