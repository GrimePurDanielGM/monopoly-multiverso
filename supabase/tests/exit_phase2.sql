-- ============================================================================
-- Salida/expulsión de jugador en partida activa (Fase 2). Tras `supabase db reset`.
-- Cubre: abandono->banca, expulsión->banca, reparto (con/sin resto), orden de turnos,
-- permisos, no-actuar-tras-salir, snapshot, reconciliación, idempotencia, paused, finished.
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
-- Abandono (Fase 3): el jugador solicita y el anfitrión aprueba con el destino del dinero.
create or replace function pg_temp._leave_via(p_gid uuid, p_victim_uid text, p_mode text) returns void language plpgsql as $f$
declare rref text; v_ver bigint; v_ref text; v_host_uid text;
begin
  perform pg_temp._as_user(p_victim_uid); perform request_leave_active(p_gid, gen_random_uuid());
  perform pg_temp._as_admin();
  select public_ref into v_ref from public.players where game_id=p_gid and auth_uid=p_victim_uid::uuid;
  select public_ref into rref from public.player_leave_requests where game_id=p_gid and requester_ref=v_ref and status='pending';
  select runtime_version into v_ver from public.game_runtime where game_id=p_gid;
  select p.auth_uid::text into v_host_uid from public.players p join public.games g on g.host_player_id=p.id where g.id=p_gid;
  perform pg_temp._as_user(v_host_uid); perform resolve_leave_active(rref, true, p_mode, v_ver);
  perform pg_temp._as_admin();
end $f$;
-- ¿reconcilia TODO el ledger? saldo = sum(to=ref) - sum(from=ref), para cada jugador (incl. salientes=0).
create or replace function pg_temp._reconciles(p_gid uuid) returns boolean language sql security definer as $f$
  select not exists (
    select 1 from public.player_balances b
    where b.game_id = p_gid and b.balance <> (
      coalesce((select sum(amount) from public.ledger where game_id=p_gid and to_ref=b.player_ref),0)
      - coalesce((select sum(amount) from public.ledger where game_id=p_gid and from_ref=b.player_ref),0)));
$f$;

-- ── Setup: dos partidas iniciadas (host + 5 jugadores = 6 en el orden) ───────────
create or replace function pg_temp._build(p_tag text, p_host text, p_uids text[]) returns void language plpgsql as $f$
declare r jsonb; gid uuid; code text; ref text; i int; v_ver int;
        toks text[]:=array['cat','boot','thimble','top_hat','iron'];
begin
  perform pg_temp._as_user(p_host);
  r := create_game_tx('Exit '||p_tag,'Anfitrion','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid := (r->>'game_id')::uuid; code := r->>'code';
  insert into _ctx values (p_tag||'_gid',gid::text),(p_tag||'_code',code),(p_tag||'_host',p_host),(p_tag||'_host_ref',r->>'host_public_ref');
  for i in 1..5 loop
    perform pg_temp._as_user(p_uids[i]);
    perform join_game(code, 'P'||i, gen_random_uuid());
    perform pg_temp._as_admin();
    select public_ref into ref from players where game_id=gid and auth_uid=p_uids[i]::uuid and kicked_at is null;
    insert into _ctx values (p_tag||'_p'||i, ref);
    perform pg_temp._as_user(p_uids[i]); perform choose_token(gid, toks[i]); perform set_ready(gid, true);
  end loop;
  perform pg_temp._as_user(p_host); perform set_ready(gid, true);
  perform pg_temp._as_admin(); select version into v_ver from games where id=gid;
  perform pg_temp._as_user(p_host); perform start_game(gid, v_ver);
  perform pg_temp._as_admin();
end $f$;

do $s$ begin
  perform pg_temp._build('A','a0000000-0000-0000-0000-0000000000a1',
    array['a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002',
          'a0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000004',
          'a0000000-0000-0000-0000-000000000005']);
  perform pg_temp._build('B','b0000000-0000-0000-0000-0000000000b1',
    array['b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000002',
          'b0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000004',
          'b0000000-0000-0000-0000-000000000005']);
end $s$;

-- ── Partida A: abandono voluntario ───────────────────────────────────────────────

-- E1) jugador NO actual abandona: saldo a la banca (player_exit_to_bank), balance 0,
--     fuera del orden, y el turno actual NO cambia (tests 1,2,4).
do $$ declare gid uuid:=pg_temp._ctx('A_gid')::uuid; v_ver bigint; cur text; victim text; victim_uid text;
            n_exit int; bal bigint; in_order boolean; cur_after text; tn_before int; tn_after int; ok boolean; begin
  perform pg_temp._as_admin();
  select runtime_version, turn_order_refs[turn_index], turn_number into v_ver, cur, tn_before from game_runtime where game_id=gid;
  -- víctima: un jugador que NO es el actual y NO es el host
  select public_ref into victim from players p where p.game_id=gid and p.public_ref<>cur
     and p.id<>(select host_player_id from games where id=gid) and p.kicked_at is null and p.left_at is null limit 1;
  victim_uid := pg_temp._uid_of(gid, victim);
  perform pg_temp._leave_via(gid, victim_uid, 'to_bank');
  perform pg_temp._as_admin();
  select count(*) into n_exit from ledger where game_id=gid and kind='player_exit_to_bank' and from_ref=victim;
  select balance into bal from player_balances where game_id=gid and player_ref=victim;
  select victim = any(turn_order_refs), turn_order_refs[turn_index], turn_number into in_order, cur_after, tn_after from game_runtime where game_id=gid;
  ok := n_exit=1 and bal=0 and not in_order and cur_after=cur and tn_after=tn_before;
  insert into _ctx values ('A_left1', victim), ('A_left1_uid', victim_uid);
  perform pg_temp._rec('E1) abandono no-actual: saldo->banca, balance 0, fuera de orden, turno intacto', ok);
end $$;

-- E2) tras abandonar no se puede actuar (NOT_ACTIVE_MEMBER) y el snapshot lo excluye (tests 10,11).
do $$ declare gid uuid:=pg_temp._ctx('A_gid')::uuid; code text:=pg_temp._ctx('A_code'); victim text:=pg_temp._ctx('A_left1');
            victim_uid text:=pg_temp._ctx('A_left1_uid'); host text:=pg_temp._ctx('A_host'); v_ver bigint;
            ok_act boolean:=false; ok_snap_self boolean:=false; in_list boolean; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(victim_uid);
  begin perform end_turn(gid, v_ver, gen_random_uuid()); exception when others then ok_act:=(sqlerrm='NOT_ACTIVE_MEMBER'); end;
  begin perform get_active_snapshot_by_code(code); exception when others then ok_snap_self:=(sqlerrm='NOT_ACTIVE_MEMBER'); end;
  perform pg_temp._as_user(host);
  select exists(select 1 from jsonb_array_elements(get_active_snapshot_by_code(code)->'players') e where e->>'public_ref'=victim) into in_list;
  perform pg_temp._as_admin();
  perform pg_temp._rec('E2) tras salir: no actúa (NOT_ACTIVE_MEMBER), snapshot propio rechaza y deja de listarlo', ok_act and ok_snap_self and not in_list);
end $$;

-- E3) si el saliente ERA el actual, el turno pasa al siguiente válido (test 3).
do $$ declare gid uuid:=pg_temp._ctx('A_gid')::uuid; host text:=pg_temp._ctx('A_host'); v_ver bigint;
            cur text; nxt text; order_refs text[]; idx int; len int; victim_uid text; cur_after text; ok boolean; begin
  perform pg_temp._as_admin();
  select runtime_version, turn_order_refs, turn_index, array_length(turn_order_refs,1)
    into v_ver, order_refs, idx, len from game_runtime where game_id=gid;
  cur := order_refs[idx];
  -- si el actual fuese el host, fijamos el turno a un no-host para poder probar el abandono del actual
  if cur = pg_temp._ctx('A_host_ref') then
    select public_ref into cur from players where game_id=gid and id<>(select host_player_id from games where id=gid)
       and kicked_at is null and left_at is null limit 1;
    perform pg_temp._as_user(host); perform host_set_turn(gid, cur, 'fijar para test', gen_random_uuid(), v_ver);
    perform pg_temp._as_admin();
    select runtime_version, turn_order_refs, turn_index, array_length(turn_order_refs,1)
      into v_ver, order_refs, idx, len from game_runtime where game_id=gid;
    cur := order_refs[idx];
  end if;
  nxt := order_refs[(idx % len) + 1];                 -- siguiente esperado
  victim_uid := pg_temp._uid_of(gid, cur);
  perform pg_temp._leave_via(gid, victim_uid, 'to_bank');
  perform pg_temp._as_admin();
  select turn_order_refs[turn_index] into cur_after from game_runtime where game_id=gid;
  perform pg_temp._rec('E3) abandono del jugador actual: el turno pasa al siguiente válido', cur_after = nxt);
end $$;

-- ── Partida B: expulsión por el anfitrión, reparto, permisos, paused, finished ───

-- E4) un jugador normal NO puede expulsar (tests 8,9 -> NOT_HOST).
do $$ declare gid uuid:=pg_temp._ctx('B_gid')::uuid; p1 text:=pg_temp._ctx('B_p1'); p2 text:=pg_temp._ctx('B_p2');
            v_ver bigint; ok boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(pg_temp._uid_of(gid,p1));
  begin perform remove_active_player(gid, p2, 'to_bank', 'x', gen_random_uuid(), v_ver);
  exception when others then ok:=(sqlerrm='NOT_HOST'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('E4) jugador no-host no puede expulsar -> NOT_HOST', ok);
end $$;

-- E5) el anfitrión NO puede expulsarse a sí mismo (CANNOT_REMOVE_HOST) ni abandonar (HOST_CANNOT_LEAVE).
do $$ declare gid uuid:=pg_temp._ctx('B_gid')::uuid; host text:=pg_temp._ctx('B_host'); host_ref text:=pg_temp._ctx('B_host_ref');
            v_ver bigint; ok1 boolean:=false; ok2 boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host);
  begin perform remove_active_player(gid, host_ref, 'to_bank', 'x', gen_random_uuid(), v_ver);
  exception when others then ok1:=(sqlerrm='CANNOT_REMOVE_HOST'); end;
  begin perform request_leave_active(gid, gen_random_uuid());
  exception when others then ok2:=(sqlerrm='HOST_CANNOT_LEAVE'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('E5) anfitrión no se autoexpulsa ni abandona (mantiene el control)', ok1 and ok2);
end $$;

-- E6) el anfitrión expulsa a un jugador con saldo -> a la banca (test 5).
do $$ declare gid uuid:=pg_temp._ctx('B_gid')::uuid; host text:=pg_temp._ctx('B_host'); v_ver bigint;
            victim text; n_exit int; bal bigint; in_order boolean; ok boolean; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  select public_ref into victim from players where game_id=gid and public_ref=pg_temp._ctx('B_p5');
  perform pg_temp._as_user(host);
  perform remove_active_player(gid, victim, 'to_bank', 'abandona la mesa', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select count(*) into n_exit from ledger where game_id=gid and kind='player_exit_to_bank' and from_ref=victim;
  select balance into bal from player_balances where game_id=gid and player_ref=victim;
  select victim = any(turn_order_refs) into in_order from game_runtime where game_id=gid;
  perform pg_temp._rec('E6) expulsión -> saldo a la banca, balance 0, fuera del orden', n_exit=1 and bal=0 and not in_order);
end $$;

-- E7) reparto entre restantes con RESTO a la banca (tests 6,7): saldo 1001, n restantes, q=floor, resto->banca.
do $$ declare gid uuid:=pg_temp._ctx('B_gid')::uuid; host text:=pg_temp._ctx('B_host'); v_ver bigint;
            victim text; rem text[]; n int; q bigint; r0 bigint; tgt bigint; sample text; before_s bigint; after_s bigint;
            n_dist int; n_rem int; rem_amt bigint; ok boolean; begin
  perform pg_temp._as_admin();
  select runtime_version, turn_order_refs into v_ver, rem from game_runtime where game_id=gid;
  -- víctima = el jugador actual NO host si procede; cogemos uno no-host cualquiera del orden
  select public_ref into victim from players where game_id=gid and public_ref=any(rem)
     and id<>(select host_player_id from games where id=gid) and kicked_at is null and left_at is null limit 1;
  -- restantes tras quitar a la víctima
  select array_agg(x) into rem from unnest(rem) x where x<>victim;
  n := array_length(rem,1);
  q := 333; r0 := 2; tgt := n*q + r0;             -- saldo objetivo que produce resto 2 (ej. del enunciado)
  -- fijar saldo de la víctima a tgt
  perform pg_temp._as_user(host); perform host_adjust_balance(gid, victim, tgt, 'preparar reparto', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  sample := rem[1];
  select balance into before_s from player_balances where game_id=gid and player_ref=sample;
  perform pg_temp._as_user(host);
  perform remove_active_player(gid, victim, 'distribute', 'reparto', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin();
  select balance into after_s from player_balances where game_id=gid and player_ref=sample;
  select count(*) into n_dist from ledger where game_id=gid and kind='player_exit_distribution' and from_ref=victim;
  select count(*), coalesce(sum(amount),0) into n_rem, rem_amt from ledger
    where game_id=gid and kind='player_exit_remainder_to_bank' and from_ref=victim;
  ok := after_s - before_s = q and n_dist = n and n_rem = 1 and rem_amt = r0
        and (select balance from player_balances where game_id=gid and player_ref=victim) = 0;
  perform pg_temp._rec('E7) reparto entero entre restantes (+333 c/u) y resto 2 a la banca', ok);
end $$;

-- E8) reconciliación global tras todas las salidas (test 12).
do $$ declare gid uuid:=pg_temp._ctx('B_gid')::uuid; begin
  perform pg_temp._as_admin();
  perform pg_temp._rec('E8) ledger reconcilia (saldo = entradas - salidas) en toda la partida', pg_temp._reconciles(gid));
end $$;

-- E9) idempotencia: misma request_id no reparte/expulsa dos veces (test 13).
do $$ declare gid uuid:=pg_temp._ctx('B_gid')::uuid; host text:=pg_temp._ctx('B_host'); v_ver bigint;
            victim text; rid uuid:=gen_random_uuid(); sample text; b1 bigint; b2 bigint; n_exit int; ok boolean; ord text[]; begin
  perform pg_temp._as_admin(); select runtime_version, turn_order_refs into v_ver, ord from game_runtime where game_id=gid;
  select public_ref into victim from players where game_id=gid and public_ref = any(ord)
    and id<>(select host_player_id from games where id=gid) and kicked_at is null and left_at is null limit 1;
  select x into sample from unnest(ord) x where x<>victim limit 1;  -- un restante distinto de la víctima
  perform pg_temp._as_admin(); select balance into b1 from player_balances where game_id=gid and player_ref=sample;
  perform pg_temp._as_user(host);
  perform remove_active_player(gid, victim, 'distribute', 'una vez', rid, v_ver);
  perform remove_active_player(gid, victim, 'distribute', 'una vez', rid, v_ver);  -- repetición exacta
  perform pg_temp._as_admin(); select balance into b2 from player_balances where game_id=gid and player_ref=sample;
  select count(*) into n_exit from ledger where game_id=gid and from_ref=victim
     and kind in ('player_exit_distribution','player_exit_remainder_to_bank','player_exit_to_bank') and amount>0;
  -- el restante recibe el reparto UNA sola vez; el ledger de salida de esa víctima no se duplica.
  perform pg_temp._rec('E9) idempotencia: reparto aplicado una vez (sin doble abono), sin asientos duplicados',
    b2 > b1 and n_exit <= (select array_length(ord,1) - 1));
end $$;

-- E10) pausada: la gestión administrativa (expulsar) SÍ se permite (test 14).
do $$ declare gid uuid:=pg_temp._ctx('B_gid')::uuid; host text:=pg_temp._ctx('B_host'); v_ver bigint;
            victim text; left_ok boolean:=false; st text; ord text[]; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform pause_game_runtime(gid, 'pausa admin', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version, turn_order_refs into v_ver, ord from game_runtime where game_id=gid;
  select public_ref into victim from players where game_id=gid and public_ref = any(ord)
    and id<>(select host_player_id from games where id=gid) and kicked_at is null and left_at is null limit 1;
  perform pg_temp._as_user(host);
  begin perform remove_active_player(gid, victim, 'to_bank', 'expulsa en pausa', gen_random_uuid(), v_ver);
    left_ok := true; exception when others then left_ok := false; end;
  perform pg_temp._as_admin(); select runtime_status into st from game_runtime where game_id=gid;
  perform pg_temp._rec('E10) en pausa se permite expulsar (gestión administrativa); sigue paused', left_ok and st='paused');
end $$;

-- E11) finalizada: abandonar/expulsar -> GAME_FINISHED (test 15).
do $$ declare gid uuid:=pg_temp._ctx('B_gid')::uuid; host text:=pg_temp._ctx('B_host'); v_ver bigint;
            victim text; victim_uid text; ok1 boolean:=false; ok2 boolean:=false; begin
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  perform pg_temp._as_user(host); perform finish_game_runtime(gid, 'fin', gen_random_uuid(), v_ver);
  perform pg_temp._as_admin(); select runtime_version into v_ver from game_runtime where game_id=gid;
  select public_ref into victim from players where game_id=gid and id<>(select host_player_id from games where id=gid)
     and kicked_at is null and left_at is null limit 1;
  victim_uid := pg_temp._uid_of(gid, victim);
  perform pg_temp._as_user(host);
  begin perform remove_active_player(gid, victim, 'to_bank', 'x', gen_random_uuid(), v_ver);
  exception when others then ok1:=(sqlerrm='GAME_FINISHED'); end;
  perform pg_temp._as_user(victim_uid);
  begin perform request_leave_active(gid, gen_random_uuid());
  exception when others then ok2:=(sqlerrm='GAME_FINISHED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('E11) finished bloquea abandono y expulsión -> GAME_FINISHED', ok1 and ok2);
end $$;

-- ── Resumen ──────────────────────────────────────────────────────────────────────
do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── exit_phase2: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then
    raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok);
  end if;
end $$;
