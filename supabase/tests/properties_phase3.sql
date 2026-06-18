-- ============================================================================
-- Propiedades (Fase 3): catálogo, snapshot, compra, pausa/finalización,
-- idempotencia y conflicto de versión. Tras `supabase db reset`.
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
create or replace function pg_temp._uid_of(p_gid uuid, p_ref text) returns text language sql security definer as $f$
  select auth_uid::text from public.players where game_id=p_gid and public_ref=p_ref $f$;

-- Partida iniciada con anfitrión + 1 jugador (min_players=2).
create or replace function pg_temp._build2() returns void language plpgsql as $f$
declare host text:='d0000000-0000-0000-0000-0000000000a1'; j1 text:='d0000000-0000-0000-0000-000000000001';
        r jsonb; gid uuid; code text; v_ver int; ref text;
begin
  perform pg_temp._as_user(host);
  r := create_game_tx('Props IT','Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid; code := r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v_ver);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); select public_ref into ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1',ref),('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid, v_ver);
  perform pg_temp._as_admin();
end $f$;

do $$ begin perform pg_temp._build2(); end $$;

-- P1) catálogo cargado (comprables en ambos tableros).
do $$ declare nb int; begin
  perform pg_temp._as_admin();
  select count(*) into nb from property_catalog where active and is_buyable;
  perform pg_temp._rec('P1) catálogo cargado con propiedades comprables', nb >= 8);
end $$;

-- P2) snapshot saneado: incluye properties (owner_ref null al inicio) y sin claves internas.
do $$ declare code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host'); snap jsonb; n int; nulls int; bad boolean; begin
  perform pg_temp._as_user(host);
  snap := get_active_snapshot_by_code(code);
  perform pg_temp._as_admin();
  select jsonb_array_length(snap->'properties') into n;
  select count(*) into nulls from jsonb_array_elements(snap->'properties') e where e->>'owner_ref' is null;
  bad := snap::text ilike '%auth_uid%' or snap::text ilike '%"id"%';
  perform pg_temp._rec('P2) snapshot incluye properties saneadas (todas disponibles al inicio)', n>=14 and nulls=n and not bad);
end $$;

-- P3..P5) comprar propiedad disponible: saldo baja y ledger property_purchase.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); p1 text:=pg_temp._ctx('p1');
            p1_uid text:=pg_temp._ctx('p1_uid'); v_ver bigint; bal bigint; nled int; owner text; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(p1_uid);
  perform buy_property(gid, 'cl-marron-1', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select balance into bal from player_balances where game_id=gid and player_ref=p1;
  select count(*) into nled from ledger where game_id=gid and kind='property_purchase' and from_ref=p1 and to_ref is null and amount=60;
  select owner_ref into owner from property_ownership where game_id=gid and property_ref='cl-marron-1' and released_at is null;
  perform pg_temp._rec('P3) comprar propiedad disponible asigna propietario', owner=p1);
  perform pg_temp._rec('P4) el saldo baja por el precio (3000-60=2940)', bal=2940);
  perform pg_temp._rec('P5) ledger property_purchase registrado (jugador->banca, 60)', nled=1);
end $$;

-- P6) no comprar sin saldo suficiente -> INSUFFICIENT_FUNDS.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref');
            v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform host_adjust_balance(gid, host_ref, 10, 'bajar saldo para test', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform buy_property(gid, 'cl-celeste-1', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='INSUFFICIENT_FUNDS'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P6) no comprar sin saldo -> INSUFFICIENT_FUNDS', ok);
end $$;

-- P7) no comprar propiedad ya poseída -> PROPERTY_ALREADY_OWNED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref');
            v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  -- restaurar saldo del host para aislar el error
  perform pg_temp._as_user(host); perform host_adjust_balance(gid, host_ref, 3000, 'restaurar saldo', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform buy_property(gid, 'cl-marron-1', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='PROPERTY_ALREADY_OWNED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P7) no comprar propiedad ocupada -> PROPERTY_ALREADY_OWNED', ok);
end $$;

-- P8) no comprar propiedad no comprable -> PROPERTY_NOT_BUYABLE.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform buy_property(gid, 'cl-salida', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='PROPERTY_NOT_BUYABLE'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P8) no comprar propiedad no comprable -> PROPERTY_NOT_BUYABLE', ok);
end $$;

-- P9) inexistente -> PROPERTY_NOT_FOUND.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform buy_property(gid, 'no-existe', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='PROPERTY_NOT_FOUND'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P9) propiedad inexistente -> PROPERTY_NOT_FOUND', ok);
end $$;

-- P10) idempotencia de compra: misma request_id no compra dos veces ni cobra dos veces.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); host_ref text:=pg_temp._ctx('host_ref');
            v_ver bigint; rid uuid:=gen_random_uuid(); b1 bigint; b2 bigint; ncnt int; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  perform buy_property(gid, 'cl-celeste-1', rid, v_ver);
  perform pg_temp._as_admin(); select balance into b1 from player_balances where game_id=gid and player_ref=host_ref;
  perform pg_temp._as_user(host);
  perform buy_property(gid, 'cl-celeste-1', rid, v_ver);   -- repetición exacta
  perform pg_temp._as_admin(); select balance into b2 from player_balances where game_id=gid and player_ref=host_ref;
  select count(*) into ncnt from property_ownership where game_id=gid and property_ref='cl-celeste-1' and released_at is null;
  perform pg_temp._rec('P10) idempotencia de compra (sin doble cobro ni doble posesión)', b1=b2 and ncnt=1);
end $$;

-- P11) conflicto de versión -> VERSION_CONFLICT.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform buy_property(gid, 'cl-servicio-1', gen_random_uuid(), v_ver - 1); exception when others then ok:=(sqlerrm='VERSION_CONFLICT'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P11) conflicto de versión -> VERSION_CONFLICT', ok);
end $$;

-- P12) en pausa NO se puede comprar -> GAME_PAUSED (snapshot sigue legible).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host');
            v_ver bigint; ok boolean:=false; readable boolean; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform pause_game_runtime(gid,'pausa',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform buy_property(gid, 'bf-1955-1', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='GAME_PAUSED'); end;
  readable := (get_active_snapshot_by_code(code)->>'runtime_status')='paused';
  -- reanudar para los siguientes
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform resume_game_runtime(gid,gen_random_uuid(),v_ver);
  perform pg_temp._as_admin();
  perform pg_temp._rec('P12) en pausa no se compra -> GAME_PAUSED (snapshot legible)', ok and readable);
end $$;

-- P13) en finalizada NO se puede comprar -> GAME_FINISHED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform finish_game_runtime(gid,'fin',gen_random_uuid(),v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform buy_property(gid, 'bf-2015-1', gen_random_uuid(), v_ver); exception when others then ok:=(sqlerrm='GAME_FINISHED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('P13) en finalizada no se compra -> GAME_FINISHED', ok);
end $$;

-- ── Resumen ──
do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── properties_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
