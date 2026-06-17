-- ============================================================================
-- Fase 1 — Endurecimiento (0008/0009): snapshot saneado, canales privados y
-- broadcast de señal mínima. Ejecutar tras `supabase db reset` (datos propios).
--   psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/hardening_phase1.sql
-- Cubre: sin auth_uid en snapshot, requests host-only, autorización de canal por
-- código, no-suplantación de eventos, los 4 tipos de señal y payloads mínimos.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t;
create temp table _t(name text primary key, ok boolean);

create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  perform set_config('role', 'authenticated', true);
  if auth.uid() <> uid::uuid then raise exception 'auth.uid()=% esperado %', auth.uid(), uid; end if;
end $$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $$
begin perform set_config('role', session_user, true); end $$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $$;

-- ===================== FIXTURES =====================
-- Game SA: host + 5 jugadores, todos ready (6) -> se inicia. Luego un extraño pide recovery.
do $$ declare uids text[]:=array['e2000000-0000-0000-0000-0000000000a2','e3000000-0000-0000-0000-0000000000a3','e4000000-0000-0000-0000-0000000000a4','e5000000-0000-0000-0000-0000000000a5','e6000000-0000-0000-0000-0000000000a6'];
  names text[]:=array['SJ2','SJ3','SJ4','SJ5','SJ6']; toks text[]:=array['hoverboard','flux_capacitor','plutonium_case','clock_tower','sports_almanac'];
  gid uuid; v_code text; i int; v int; begin
  perform pg_temp._as_user('e1000000-0000-0000-0000-0000000000a1');
  perform create_game_tx('Senal SA','SHost','delorean','{}','eeeeeeee-0000-0000-0000-0000000000a1','H','S','A',1);
  -- version capturada como admin (0008: el cliente no lee games directo; joins/tokens/ready no la alteran)
  perform pg_temp._as_admin(); select id,code,version into gid,v_code,v from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a1';
  for i in 1..5 loop
    perform pg_temp._as_user(uids[i]);
    perform join_game(v_code,names[i],gen_random_uuid()); perform choose_token(gid,toks[i]); perform set_ready(gid,true);
  end loop;
  perform pg_temp._as_user('e1000000-0000-0000-0000-0000000000a1'); perform set_ready(gid,true);
  perform start_game(gid, v);                         -- emite game_started
  perform pg_temp._as_admin();
end $$;

-- Extraño pide recovery de un jugador activo de SA -> emite recovery_requested + deja pendiente.
do $$ declare gid uuid; v_code text; pref text; begin
  select id,code into gid,v_code from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a1';
  select public_ref into pref from players where game_id=gid and display_name='SJ2' and kicked_at is null;
  perform pg_temp._as_user('e8000000-0000-0000-0000-0000000000a8');
  perform request_recovery(v_code, pref, 'dev-test');  -- emite recovery_requested
  perform pg_temp._as_admin();
end $$;

-- Game SC: host solo (lobby) -> se cancela. Emite game_cancelled.
do $$ declare gid uuid; begin
  perform pg_temp._as_user('e7000000-0000-0000-0000-0000000000a7');
  perform create_game_tx('Senal SC','CHost','delorean','{}','eeeeeeee-0000-0000-0000-0000000000a2','H','S','A',1);
  perform pg_temp._as_admin(); select id into gid from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a2';
  perform pg_temp._as_user('e7000000-0000-0000-0000-0000000000a7'); perform cancel_game(gid);
  perform pg_temp._as_admin();
end $$;

-- ===================== TESTS =====================
-- (5) snapshot completo NO contiene la clave auth_uid (escaneo de texto del JSON entero).
do $$ declare gid uuid; snap jsonb; begin
  select id into gid from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a1';
  perform pg_temp._as_user('e1000000-0000-0000-0000-0000000000a1'); snap := get_lobby_snapshot(gid); perform pg_temp._as_admin();
  perform pg_temp._rec('5) snapshot completo sin clave auth_uid', snap::text not ilike '%auth_uid%');
end $$;

-- (6) el host recibe solicitudes pendientes; (7) un jugador normal NO.
do $$ declare gid uuid; sh jsonb; sp jsonb; begin
  select id into gid from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a1';
  perform pg_temp._as_user('e1000000-0000-0000-0000-0000000000a1'); sh := get_lobby_snapshot(gid); perform pg_temp._as_admin();
  perform pg_temp._as_user('e2000000-0000-0000-0000-0000000000a2'); sp := get_lobby_snapshot(gid); perform pg_temp._as_admin();
  perform pg_temp._rec('6) host ve solicitudes pendientes', jsonb_array_length(sh->'requests') >= 1);
  perform pg_temp._rec('7) jugador normal NO ve solicitudes', jsonb_array_length(sp->'requests') = 0);
end $$;

-- (8/9) autorización de canal por código: miembro=true, no-miembro=false.
do $$ declare v_code text; okm boolean; oknm boolean; begin
  select code into v_code from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a1';
  perform pg_temp._as_user('e2000000-0000-0000-0000-0000000000a2'); okm  := is_active_member_by_code(v_code); perform pg_temp._as_admin();
  perform pg_temp._as_user('f0000000-0000-0000-0000-0000000000ff'); oknm := is_active_member_by_code(v_code); perform pg_temp._as_admin();
  perform pg_temp._rec('8) miembro autorizado en su canal privado', okm = true);
  perform pg_temp._rec('9) no-miembro NO autorizado en ese canal', oknm = false);
end $$;

-- (10) el cliente puede Presence pero NO emitir broadcast (no suplanta eventos oficiales);
--      un no-miembro tampoco puede emitir nada en esa sala.
do $$ declare v_code text; ok_presence boolean:=false; spoof_blocked boolean:=false; nonmember_blocked boolean:=false; begin
  select code into v_code from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a1';
  -- miembro: Presence permitido
  perform pg_temp._as_user('e2000000-0000-0000-0000-0000000000a2');
  perform set_config('realtime.topic','room:'||v_code,true);
  begin insert into realtime.messages(topic,extension,event,payload,private)
        values('room:'||v_code,'presence','track', jsonb_build_object('public_ref','P-x'), true); ok_presence:=true;
  exception when insufficient_privilege then ok_presence:=false; end;
  -- miembro: broadcast (suplantar evento oficial) DENEGADO
  begin insert into realtime.messages(topic,extension,event,payload,private)
        values('room:'||v_code,'broadcast','lobby_changed', '{}'::jsonb, true); spoof_blocked:=false;
  exception when insufficient_privilege then spoof_blocked:=true; end;
  perform pg_temp._as_admin();
  -- no-miembro: Presence DENEGADO en sala ajena
  perform pg_temp._as_user('f0000000-0000-0000-0000-0000000000ff');
  perform set_config('realtime.topic','room:'||v_code,true);
  begin insert into realtime.messages(topic,extension,event,payload,private)
        values('room:'||v_code,'presence','track', jsonb_build_object('public_ref','P-y'), true); nonmember_blocked:=false;
  exception when insufficient_privilege then nonmember_blocked:=true; end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('10a) miembro PUEDE Presence', ok_presence = true);
  perform pg_temp._rec('10b) miembro NO puede emitir broadcast (no suplanta)', spoof_blocked = true);
  perform pg_temp._rec('10c) no-miembro NO puede emitir en sala ajena', nonmember_blocked = true);
end $$;

-- (11) los triggers emitieron los CUATRO tipos de señal.
do $$ declare sa text; sc text; n int; begin
  select code into sa from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a1';
  select code into sc from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a2';
  select count(distinct event) into n from realtime.messages
   where topic in ('room:'||sa,'room:'||sc)
     and event in ('lobby_changed','game_started','game_cancelled','recovery_requested');
  perform pg_temp._rec('11) triggers emiten los 4 tipos de señal', n = 4);
end $$;

-- (12) ningún payload Broadcast contiene filas/datos internos: claves ⊆ {id, game_id}.
do $$ declare sa text; sc text; bad int; begin
  select code into sa from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a1';
  select code into sc from games where create_request_id='eeeeeeee-0000-0000-0000-0000000000a2';
  select count(*) into bad
  from realtime.messages m, lateral jsonb_object_keys(m.payload) k
  where m.topic in ('room:'||sa,'room:'||sc) and m.extension='broadcast' and k not in ('id','game_id');
  perform pg_temp._rec('12) payloads Broadcast solo {id, game_id} (sin filas ni datos internos)', bad = 0);
end $$;

do $$ declare fails text; begin
  select string_agg(name,'; ') into fails from _t where not ok;
  raise notice '----------------------------------------';
  if fails is null then raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
  else raise exception 'RESULTADO: HAY FALLOS -> %', fails; end if;
end $$;
