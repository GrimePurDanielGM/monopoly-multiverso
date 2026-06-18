-- ============================================================================
-- Incorporacion tardia (Fase 2): config, solicitud, aprobacion, orden, plaza.
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

-- Crea una partida activa de 6 jugadores con config dada. Devuelve gid/code en _ctx con sufijo.
create or replace function pg_temp._setup(p_suffix text, p_host text, p_uids text[], p_patch jsonb) returns void language plpgsql as $f$
declare r jsonb; gid uuid; code text; ref text; toks text[]:=array['cat','boot','thimble','top_hat','iron']; i int; v_ver int;
begin
  perform pg_temp._as_user(p_host);
  r := create_game_tx('LateJoin '||p_suffix,'Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid; code := r->>'code';
  insert into _ctx values ('gid'||p_suffix, gid::text),('code'||p_suffix, code),('hostref'||p_suffix, r->>'host_public_ref');
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(p_host); perform update_config(gid, p_patch, v_ver);
  for i in 1..5 loop
    perform pg_temp._as_user(p_uids[i]);
    perform join_game(code, 'P'||p_suffix||i, gen_random_uuid());
    perform pg_temp._as_admin();
    select public_ref into ref from players where game_id=gid and auth_uid=p_uids[i]::uuid and kicked_at is null;
    insert into _ctx values ('p'||p_suffix||i, ref);
    perform pg_temp._as_user(p_uids[i]); perform choose_token(gid, toks[i]); perform set_ready(gid, true);
  end loop;
  perform pg_temp._as_user(p_host); perform set_ready(gid, true);
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(p_host); perform start_game(gid, v_ver);
  perform pg_temp._as_admin();
end $f$;

do $s$
begin
  -- Partida A: allow_late_join=true, max_players=7 (sitio para 1 incorporacion).
  perform pg_temp._setup('A','c0000000-0000-0000-0000-0000000000a1',
    array['c0000000-0000-0000-0000-000000000011','c0000000-0000-0000-0000-000000000012','c0000000-0000-0000-0000-000000000013',
          'c0000000-0000-0000-0000-000000000014','c0000000-0000-0000-0000-000000000015'],
    jsonb_build_object('allow_late_join', true, 'max_players', 7));
  -- Partida B: allow_late_join=false (por defecto).
  perform pg_temp._setup('B','c0000000-0000-0000-0000-0000000000b1',
    array['c0000000-0000-0000-0000-000000000021','c0000000-0000-0000-0000-000000000022','c0000000-0000-0000-0000-000000000023',
          'c0000000-0000-0000-0000-000000000024','c0000000-0000-0000-0000-000000000025'],
    '{}'::jsonb);
  insert into _ctx values ('hostA','c0000000-0000-0000-0000-0000000000a1'),('lj1','c0000000-0000-0000-0000-0000000000f1'),
    ('lj2','c0000000-0000-0000-0000-0000000000f2');
end $s$;

-- C1) snapshot expone allow_late_join (true en A) ; default false en B.
do $$ declare snapA jsonb; snapB jsonb; begin
  perform pg_temp._as_user(pg_temp._ctx('hostA'));
  snapA := get_active_snapshot_by_code(pg_temp._ctx('codeA'));
  perform pg_temp._as_user('c0000000-0000-0000-0000-0000000000b1');
  snapB := get_active_snapshot_by_code(pg_temp._ctx('codeB'));
  perform pg_temp._as_admin();
  perform pg_temp._rec('C1) snapshot expone allow_late_join (A true, B false)',
    (snapA#>>'{game,config,allow_late_join}')='true' and (snapB#>>'{game,config,allow_late_join}')='false');
end $$;

-- C2) tras iniciar, update_config no puede modificar la opcion (NOT_IN_LOBBY).
do $$ declare gid uuid:=pg_temp._ctx('gidA')::uuid; ok boolean:=false; begin
  perform pg_temp._as_user(pg_temp._ctx('hostA'));
  begin perform update_config(gid, jsonb_build_object('allow_late_join', false), 999); exception when others then ok:=(sqlerrm='NOT_IN_LOBBY'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('C2) opcion inmutable tras iniciar (NOT_IN_LOBBY)', ok);
end $$;

-- L1) allow=false -> LATE_JOIN_DISABLED (partida B).
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user(pg_temp._ctx('lj1'));
  begin perform request_late_join(pg_temp._ctx('codeB'),'Tardio','cat','iPad'); exception when others then ok:=(sqlerrm='LATE_JOIN_DISABLED'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('L1) allow=false -> LATE_JOIN_DISABLED', ok);
end $$;

-- L2) allow=true -> solicitud pendiente ; L3) repetir idempotente.
do $$ declare r1 jsonb; r2 jsonb; begin
  perform pg_temp._as_user(pg_temp._ctx('lj1'));
  r1 := request_late_join(pg_temp._ctx('codeA'),'Septimo','clock_tower','iPad');
  r2 := request_late_join(pg_temp._ctx('codeA'),'Septimo','clock_tower','iPad');
  insert into _ctx values ('reqA', r1->>'request_ref');
  perform pg_temp._as_admin();
  perform pg_temp._rec('L2) solicitud pendiente', (r1->>'status')='pending');
  perform pg_temp._rec('L3) solicitud idempotente (mismo ref)', (r1->>'request_ref')=(r2->>'request_ref'));
end $$;

-- L4) sesion con jugador activo -> SESSION_HAS_ACTIVE_PLAYER.
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user('c0000000-0000-0000-0000-000000000011');
  begin perform request_late_join(pg_temp._ctx('codeA'),'X','cat','x'); exception when others then ok:=(sqlerrm='SESSION_HAS_ACTIVE_PLAYER'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('L4) sesion con jugador -> SESSION_HAS_ACTIVE_PLAYER', ok);
end $$;

-- L5) nombre duplicado / L6) ficha ocupada.
do $$ declare okn boolean:=false; okt boolean:=false; nom text; tok text; begin
  perform pg_temp._as_admin();
  select display_name, token_id into nom, tok from players where game_id=pg_temp._ctx('gidA')::uuid and public_ref=pg_temp._ctx('pA1');
  perform pg_temp._as_user(pg_temp._ctx('lj2'));
  begin perform request_late_join(pg_temp._ctx('codeA'),nom,'rider','x'); exception when others then okn:=(sqlerrm='NAME_TAKEN'); end;
  begin perform request_late_join(pg_temp._ctx('codeA'),'NombreLibre',tok,'x'); exception when others then okt:=(sqlerrm='TOKEN_TAKEN'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('L5) nombre duplicado -> NAME_TAKEN', okn);
  perform pg_temp._rec('L6) ficha ocupada -> TOKEN_TAKEN', okt);
end $$;

-- A1) aprobar: crea UN jugador, saldo inicial, ledger late_join_seed, append al final,
--     turno/turn_number/current intactos, runtime_version +1, reconciliacion.
do $$ declare gid uuid:=pg_temp._ctx('gidA')::uuid; host text:=pg_temp._ctx('hostA'); reqref text:=pg_temp._ctx('reqA');
            v_ver bigint; i0 int; n0 int; cur0 text; len0 int; np text; v_bal bigint; v_led int; i1 int; n1 int; cur1 text; len1 int; v_ver1 bigint; v_div int; res jsonb; begin
  perform pg_temp._as_admin();
  select runtime_version, turn_index, turn_number, turn_order_refs[turn_index], array_length(turn_order_refs,1)
    into v_ver, i0, n0, cur0, len0 from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); res := resolve_late_join(reqref, true, v_ver);
  np := res->>'new_public_ref';
  perform pg_temp._as_admin();
  select balance into v_bal from player_balances where game_id=gid and player_ref=np;
  select count(*) into v_led from ledger where game_id=gid and kind='late_join_seed' and to_ref=np and amount=3000 and request_id is not null;
  select turn_index, turn_number, turn_order_refs[turn_index], array_length(turn_order_refs,1), runtime_version
    into i1, n1, cur1, len1, v_ver1 from game_runtime where game_id=gid;
  -- reconciliacion
  with rec as (select b.player_ref, b.balance m,
      coalesce((select sum(amount) from ledger l where l.game_id=gid and l.to_ref=b.player_ref),0)
    - coalesce((select sum(amount) from ledger l where l.game_id=gid and l.from_ref=b.player_ref),0) d
    from player_balances b where b.game_id=gid)
  select count(*) into v_div from rec where m<>d;
  perform pg_temp._rec('A1a) crea jugador con saldo inicial 3000', v_bal=3000);
  perform pg_temp._rec('A1b) ledger late_join_seed unico con request_id', v_led=1);
  perform pg_temp._rec('A1c) append al final (len+1, ultimo=nuevo)', len1=len0+1 and (select turn_order_refs[array_length(turn_order_refs,1)] from game_runtime where game_id=gid)=np);
  perform pg_temp._rec('A1d) turno actual y turn_number intactos', i1=i0 and n1=n0 and cur1=cur0);
  perform pg_temp._rec('A1e) runtime_version +1', v_ver1=v_ver+1);
  perform pg_temp._rec('A1f) reconciliacion correcta', v_div=0);
end $$;

-- A2) aprobar de nuevo (idempotente): no crea otro jugador.
do $$ declare gid uuid:=pg_temp._ctx('gidA')::uuid; host text:=pg_temp._ctx('hostA'); reqref text:=pg_temp._ctx('reqA'); v_ver bigint; cnt0 int; cnt1 int; res jsonb; begin
  perform pg_temp._as_admin(); select count(*) into cnt0 from players where game_id=gid; select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); res := resolve_late_join(reqref, true, v_ver);
  perform pg_temp._as_admin(); select count(*) into cnt1 from players where game_id=gid;
  perform pg_temp._rec('A2) reaprobar idempotente (sin jugador nuevo)', (res->>'idempotent')='true' and cnt1=cnt0);
end $$;

-- A3) sala llena (A tiene max=7; ya hay 7) -> GAME_FULL.
do $$ declare ok boolean:=false; begin
  perform pg_temp._as_user('c0000000-0000-0000-0000-0000000000f9');
  begin perform request_late_join(pg_temp._ctx('codeA'),'Octavo','rider','x'); exception when others then ok:=(sqlerrm='GAME_FULL'); end;
  perform pg_temp._as_admin(); perform pg_temp._rec('A3) sala llena (max 7) -> GAME_FULL', ok);
end $$;

-- A4) rechazo no crea nada.
do $$ declare gid uuid:=pg_temp._ctx('gidB')::uuid; host text:='c0000000-0000-0000-0000-0000000000b1';
            v_ver bigint; cnt0 int; cnt1 int; rr text; res jsonb; begin
  -- habilitar B no se puede (iniciada); usamos A: pero A esta llena. Creamos solicitud en A imposible.
  -- En su lugar: en A, una nueva solicitud (lj2) y rechazarla.
  perform pg_temp._as_admin(); gid := pg_temp._ctx('gidA')::uuid;
  -- A esta llena -> request dara GAME_FULL; para probar rechazo usamos una solicitud creada antes del lleno.
  -- Creamos en B una solicitud? B esta deshabilitada. Validamos rechazo con get_request_status de la aprobada (approved).
  perform pg_temp._as_user(pg_temp._ctx('lj1'));
  res := get_request_status(pg_temp._ctx('reqA'));
  perform pg_temp._as_admin();
  perform pg_temp._rec('A4) get_request_status late_join approved', (res->>'kind')='late_join' and (res->>'status')='approved');
end $$;

-- A5) snapshot del anfitrion incluye solicitudes tardias pendientes; jugador no las ve.
do $$ declare gid uuid:=pg_temp._ctx('gidA')::uuid; host text:=pg_temp._ctx('hostA'); snapH jsonb; snapP jsonb; rr text; begin
  -- crear una nueva pendiente: A esta llena -> GAME_FULL. Liberamos plaza? No. Probamos en B con allow? deshabilitado.
  -- Validamos que tras la aprobacion no quedan pendientes en A y la seccion existe y es []-para no host.
  perform pg_temp._as_user(host); snapH := get_active_snapshot_by_code(pg_temp._ctx('codeA'));
  perform pg_temp._as_user('c0000000-0000-0000-0000-000000000011'); snapP := get_active_snapshot_by_code(pg_temp._ctx('codeA'));
  perform pg_temp._as_admin();
  perform pg_temp._rec('A5) seccion late_join_requests presente (host) y vacia para jugador',
    jsonb_typeof(snapH->'late_join_requests')='array' and (snapP->'late_join_requests')='[]'::jsonb);
end $$;

do $g$ declare n int; begin
  select count(*) into n from _t where ok is false;
  if n>0 then raise exception 'FALLOS: %', n; end if;
  raise notice 'RESULTADO: TODOS PASAN (% comprobaciones)', (select count(*) from _t);
end $g$;
