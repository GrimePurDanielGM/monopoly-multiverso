-- ============================================================================
-- Abandono con aprobación + bancarrota a banca + pausa/finalización (Fase 3 corrección).
-- Tras `supabase db reset`.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
drop table if exists _ctx; create temp table _ctx(k text primary key, v text);
grant select, insert, update, delete on _t, _ctx to authenticated;
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $f$
begin perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true); if auth.uid() <> uid::uuid then raise exception 'bad uid'; end if; end $f$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $f$ begin perform set_config('role', session_user, true); end $f$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;
create or replace function pg_temp._ctx(k text) returns text language sql as $f$ select v from _ctx where k=$1 $f$;
create or replace function pg_temp._ver(gid uuid) returns bigint language sql security definer as $f$ select runtime_version from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._owner(gid uuid, ref text) returns text language sql security definer as $f$
  select owner_ref from public.property_ownership where game_id=gid and property_ref=ref and released_at is null $f$;

create or replace function pg_temp._build3() returns void language plpgsql as $f$
declare host text:='ab000000-0000-0000-0000-0000000000a1';
        u text[]:=array['ab000000-0000-0000-0000-000000000001','ab000000-0000-0000-0000-000000000002'];
        toks text[]:=array['cat','boot']; r jsonb; gid uuid; code text; v int; ref text; i int;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('LB IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  for i in 1..2 loop
    perform pg_temp._as_user(u[i]); perform join_game(code,'P'||i,gen_random_uuid());
    perform pg_temp._as_admin(); select public_ref into ref from players where game_id=gid and auth_uid=u[i]::uuid;
    insert into _ctx values ('p'||i,ref),('p'||i||'_uid',u[i]);
    perform pg_temp._as_user(u[i]); perform choose_token(gid,toks[i]); perform set_ready(gid,true);
  end loop;
  perform pg_temp._as_user(host); perform choose_token(gid,'thimble'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid, v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build3(); end $$;

-- p1 compra (vía aprobación) cl-bailen para tener propiedad.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1u text:=pg_temp._ctx('p1_uid'); rref text; begin
  perform pg_temp._as_user(p1u); perform request_property_purchase(gid,'cl-bailen',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into rref from property_purchase_requests where game_id=gid and property_ref='cl-bailen' and status='pending';
  perform pg_temp._as_user(host); perform resolve_property_purchase(rref,true,pg_temp._ver(gid)); perform pg_temp._as_admin();
end $$;

-- L1) abandono directo no disponible (revocado); solicitar abandono con propiedad NO saca al jugador.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; p1 text:=pg_temp._ctx('p1'); p1u text:=pg_temp._ctx('p1_uid'); revoked boolean; in_order boolean; rref text; begin
  perform pg_temp._as_admin(); revoked := not has_function_privilege('authenticated','public.leave_active_game(uuid,text,uuid,bigint)','execute');
  perform pg_temp._as_user(p1u); perform request_leave_active(gid, gen_random_uuid());
  perform pg_temp._as_admin();
  select p1 = any(turn_order_refs) into in_order from game_runtime where game_id=gid;
  select public_ref into rref from player_leave_requests where game_id=gid and requester_ref=p1 and status='pending';
  insert into _ctx values ('leave_req', rref);
  perform pg_temp._rec('L1) abandono directo revocado; solicitud con propiedad NO saca al jugador', revoked and in_order and rref is not null);
end $$;

-- L2) el anfitrión aprueba el abandono (a banca): jugador fuera, propiedad a banca.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); rref text:=pg_temp._ctx('leave_req');
            in_order boolean; own text; begin
  perform pg_temp._as_user(host); perform resolve_leave_active(rref, true, 'to_bank', pg_temp._ver(gid));
  perform pg_temp._as_admin();
  select p1 = any(turn_order_refs) into in_order from game_runtime where game_id=gid;
  own := pg_temp._owner(gid,'cl-bailen');
  perform pg_temp._rec('L2) abandono aprobado (a banca): fuera del orden y propiedad a banca', not in_order and own is null);
end $$;

-- BB1) bancarrota a banca: dinero y propiedades a banca; deudor espectador. (p2 compra y se arruina)
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p2 text:=pg_temp._ctx('p2'); p2u text:=pg_temp._ctx('p2_uid');
            rref text; own text; bal bigint; spectator boolean; in_order boolean; nled int; begin
  perform pg_temp._as_user(p2u); perform request_property_purchase(gid,'cl-serrano',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into rref from property_purchase_requests where game_id=gid and property_ref='cl-serrano' and status='pending';
  perform pg_temp._as_user(host); perform resolve_property_purchase(rref,true,pg_temp._ver(gid));
  perform pg_temp._as_user(p2u); perform request_bankruptcy(gid,'to_bank',null,'me rindo',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into rref from bankruptcy_requests where game_id=gid and requester_ref=p2 and status='pending';
  perform pg_temp._as_user(host); perform resolve_bankruptcy(rref, true, pg_temp._ver(gid));
  perform pg_temp._as_admin();
  own := pg_temp._owner(gid,'cl-serrano'); select balance into bal from player_balances where game_id=gid and player_ref=p2;
  select bankrupt_at is not null into spectator from players where game_id=gid and public_ref=p2;
  select p2 = any(turn_order_refs) into in_order from game_runtime where game_id=gid;
  select count(*) into nled from ledger where game_id=gid and kind='bankruptcy_cash_to_bank' and from_ref=p2;
  perform pg_temp._rec('BB1) bancarrota a banca: dinero a banca (ledger), propiedad a banca, espectador, fuera del orden',
    own is null and bal=0 and spectator and not in_order and nled=1);
end $$;

-- G1) en pausa: compra bloqueada; en finalizada: abandono/bancarrota bloqueados (GAME_FINISHED).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref');
            ok_pause boolean:=false; ok_fin1 boolean:=false; begin
  perform pg_temp._as_user(host); perform pause_game_runtime(gid,'x',gen_random_uuid(),pg_temp._ver(gid));
  -- el anfitrión es jugador; intenta solicitar compra en pausa
  begin perform request_property_purchase(gid,'cl-prado',gen_random_uuid()); exception when others then ok_pause:=(sqlerrm='GAME_PAUSED'); end;
  perform resume_game_runtime(gid,gen_random_uuid(),pg_temp._ver(gid));
  perform finish_game_runtime(gid,'fin',gen_random_uuid(),pg_temp._ver(gid));
  begin perform request_bankruptcy(gid,'to_bank',null,'x',gen_random_uuid()); exception when others then ok_fin1:=(sqlerrm='GAME_FINISHED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('G1) pausa bloquea compra (GAME_PAUSED); finalizada bloquea bancarrota (GAME_FINISHED)', ok_pause and ok_fin1);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── leave_bankrupt_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
