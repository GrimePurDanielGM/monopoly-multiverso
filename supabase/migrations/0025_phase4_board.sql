-- Fase 4 — Sistema base de movimiento: catálogo de casillas + posición de cada jugador.
-- ALCANCE: posiciones, paso por salida (cobro), caer en propiedad (detección). FUERA: cartas,
-- cárcel, parking, guardianes, ruleta, casas, hoteles, hipotecas, intersecciones de dos tableros.
--
-- DISEÑO DEL RING (decisión documentada): el tablero de Fase 4 se DERIVA del catálogo real ya
-- cargado (0021), sin inventar propiedades ni topología. Cada tablero es un anillo de:
--   índice 0  -> casilla 'start' (Salida)            (única casilla no-propiedad)
--   índices 1..N -> una casilla 'property' por propiedad del catálogo, en orden de sort_order
-- Las casillas no-propiedad de impuestos/suerte/comunidad/cárcel/parking se DEJAN PARA UNA FASE
-- POSTERIOR (requieren la topología exacta del tablero físico; inventar sus posiciones violaría
-- "no inventar"). El enum space_type ya admite esos tipos para cuando se confirmen.

-- ── 1) Catálogo de casillas (referencia global, controlado por migración; deny-all) ──
create table public.board_spaces (
  id uuid primary key default gen_random_uuid(),                 -- interno, NUNCA expuesto
  space_ref  text not null unique,                               -- opaco público
  board_key  text not null check (board_key in ('classic','back_to_the_future')),
  space_index int not null check (space_index >= 0),             -- 0 = salida; ring 0..N
  name       text not null,
  space_type text not null check (space_type in
    ('start','property','tax','card','jail','go_to_jail','parking','special')),
  property_ref text null references public.property_catalog(property_ref),
  is_start   boolean not null default false,
  sort_order int not null default 0,
  active     boolean not null default true,
  -- Una casilla es 'property' si y solo si apunta a una propiedad real del catálogo.
  constraint board_space_property_link check ((space_type = 'property') = (property_ref is not null)),
  -- is_start verdadero exactamente para las casillas 'start'.
  constraint board_space_is_start check (is_start = (space_type = 'start')),
  unique (board_key, space_index)
);
create index board_spaces_board_idx on public.board_spaces (board_key, space_index) where active;
alter table public.board_spaces enable row level security;        -- deny-all: solo SECURITY DEFINER
revoke all on public.board_spaces from anon, authenticated;

-- Casilla de salida por tablero (índice 0).
insert into public.board_spaces (space_ref, board_key, space_index, name, space_type, property_ref, is_start, sort_order)
select b.board_key || '-space-00', b.board_key, 0, 'Salida', 'start', null, true, 0
from (values ('classic'), ('back_to_the_future')) as b(board_key);

-- Una casilla 'property' por propiedad del catálogo, en orden de sort_order (índices 1..N).
insert into public.board_spaces (space_ref, board_key, space_index, name, space_type, property_ref, is_start, sort_order)
select c.board_key || '-space-' || lpad(c.rn::text, 2, '0'),
       c.board_key, c.rn, c.name, 'property', c.property_ref, false, c.sort_order
from (
  select property_ref, board_key, name, sort_order,
         row_number() over (partition by board_key order by sort_order, property_ref) as rn
  from public.property_catalog where active
) c;

-- ── 2) Helpers de tablero ─────────────────────────────────────────────────────────
-- Tablero inicial por defecto (todos empiezan aquí en Fase 4; el modelo admite varios).
create or replace function public._p4_initial_board()
returns text language sql immutable as $$ select 'classic'::text $$;

-- Tamaño del anillo (número de casillas) de un tablero.
create or replace function public._p4_ring_size(p_board text)
returns int language sql stable security definer set search_path = public, pg_temp as $$
  select count(*)::int from public.board_spaces where board_key = p_board and active
$$;
revoke all on function public._p4_ring_size(text) from public, anon, authenticated;

-- ── 3) Posición de cada jugador (per-game; conserva historial, no se borra) ─────────
create table public.player_positions (
  id uuid primary key default gen_random_uuid(),                 -- interno, NUNCA expuesto
  game_id uuid not null references public.games(id) on delete cascade,
  player_ref text not null,                                      -- public_ref
  board_key  text not null check (board_key in ('classic','back_to_the_future')),
  space_index int not null check (space_index >= 0),
  updated_at timestamptz not null default now(),
  unique (game_id, player_ref)
);
create index player_positions_game_idx on public.player_positions (game_id);
alter table public.player_positions enable row level security;    -- deny-all: solo SECURITY DEFINER
revoke all on public.player_positions from anon, authenticated;

-- Siembra idempotente: inserta en la salida la posición de cada jugador no saliente/expulsado
-- que aún no la tenga (autorreparación para partidas ya iniciadas). No mueve a quien ya tiene fila.
create or replace function public._p4_ensure_positions(p_game uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_board text := public._p4_initial_board();
begin
  insert into public.player_positions(game_id, player_ref, board_key, space_index)
  select p_game, p.public_ref, v_board, 0
  from public.players p
  join public.game_runtime rt on rt.game_id = p_game
  where p.game_id = p_game and p.kicked_at is null and p.left_at is null
    and (p.public_ref = any(rt.turn_order_refs) or p.bankrupt_at is not null)
  on conflict (game_id, player_ref) do nothing;
end $$;
revoke all on function public._p4_ensure_positions(uuid) from public, anon, authenticated;

-- ── 4) Estado de movimiento por partida (última tirada / último movimiento, saneado) ─
alter table public.game_runtime
  add column if not exists last_roll jsonb null,
  add column if not exists last_move jsonb null;

-- ── 5) Ledger: bonus por pasar/caer en salida (banco -> jugador, reconciliable) ─────
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check check (kind in
  ('seed','bank_to_player','player_to_bank','player_to_player','host_player_transfer','host_adjust','host_revert','late_join_seed',
   'player_exit_to_bank','player_exit_distribution','player_exit_remainder_to_bank',
   'property_purchase','rent_payment','property_auction_purchase',
   'bankruptcy_cash_to_bank','bankruptcy_cash_to_player',
   'pass_start_bonus'));
alter table public.ledger drop constraint ledger_shape;
alter table public.ledger add constraint ledger_shape check (
  case kind
    when 'seed' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is null and before_balance is null and after_balance is null
    when 'late_join_seed' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'bank_to_player' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_bank' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_player' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'host_player_transfer' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reason is not null and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'host_adjust' then
      before_balance is not null and after_balance is not null
      and before_balance <> after_balance
      and amount = abs(after_balance - before_balance)
      and ((after_balance > before_balance and from_ref is null     and to_ref is not null)
        or (after_balance < before_balance and from_ref is not null and to_ref is null))
      and reason is not null and reverts_ledger_id is null and request_id is not null
    when 'host_revert' then
      reverts_ledger_id is not null and reason is not null and request_id is not null
      and before_balance is null and after_balance is null
      and ( ((from_ref is null) <> (to_ref is null))
         or (from_ref is not null and to_ref is not null and from_ref <> to_ref) )
    when 'player_exit_to_bank' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'player_exit_distribution' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'player_exit_remainder_to_bank' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'property_purchase' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'rent_payment' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'property_auction_purchase' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'bankruptcy_cash_to_bank' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'bankruptcy_cash_to_player' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'pass_start_bonus' then         -- banca -> jugador (cobro automático al pasar por salida)
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    else false
  end
);

-- ── 6) start_game: idéntico a Fase 2 + siembra de posiciones en la salida (misma transacción) ──
create or replace function public.start_game(p_game uuid, p_expected_version int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; v_active int; v_min int; v_incomplete int; v_pending int; v_order uuid[]; v_init int;
begin
  g := public._require_host(p_game);
  if g.status = 'active' then return jsonb_build_object('status','active','turn_order',to_jsonb(g.turn_order),'idempotent',true); end if;
  if g.status <> 'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  if g.version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;

  v_min := coalesce((g.config->>'min_players')::int, 6);
  select count(*) into v_active from public.players where game_id = g.id and kicked_at is null;
  if v_active < v_min then raise exception 'NOT_ENOUGH_PLAYERS'; end if;
  select count(*) into v_incomplete from public.players
    where game_id = g.id and kicked_at is null and (token_id is null or join_status <> 'ready' or char_length(btrim(display_name)) < 2);
  if v_incomplete > 0 then raise exception 'PLAYERS_INCOMPLETE'; end if;
  select count(*) into v_pending from public.player_recovery_requests r
    join public.players p on p.id = r.player_id and p.kicked_at is null
    where r.game_id = g.id and r.status = 'pending';
  if v_pending > 0 then raise exception 'PENDING_RECOVERIES'; end if;

  select array_agg(id order by gen_random_uuid()) into v_order
  from public.players where game_id = g.id and kicked_at is null;

  update public.games set status = 'active', started_at = now(), turn_order = v_order, version = version + 1
    where id = g.id returning * into g;

  insert into public.game_runtime(game_id, turn_order_refs, turn_index, turn_number, ledger_seq, runtime_version)
  select g.id, array_agg(p.public_ref order by o.ord), 1, 1, 0, 0
  from unnest(v_order) with ordinality as o(pid, ord)
  join public.players p on p.id = o.pid;

  v_init := coalesce((g.config->>'initial_money')::int, 3000);
  insert into public.player_balances(game_id, player_ref, balance)
    select g.id, p.public_ref, v_init from public.players p where p.game_id = g.id and p.kicked_at is null;

  if v_init > 0 then
    with seeded as (
      select p.public_ref, row_number() over (order by array_position(v_order, p.id)) as rn
      from public.players p where p.game_id = g.id and p.kicked_at is null)
    insert into public.ledger(ledger_ref, game_id, seq, kind, from_ref, to_ref, amount, request_id)
      select public.gen_ledger_ref(g.id), g.id, rn, 'seed', null, public_ref, v_init, null from seeded;
    update public.game_runtime set ledger_seq = v_active where game_id = g.id;
  end if;

  -- Fase 4: todos empiezan en la casilla 'start' del tablero inicial (misma transacción).
  insert into public.player_positions(game_id, player_ref, board_key, space_index)
    select g.id, p.public_ref, public._p4_initial_board(), 0
    from public.players p where p.game_id = g.id and p.kicked_at is null;

  perform public._audit(g.id, 'game_started', auth.uid(), null, v_order, null,
            jsonb_build_object('turn_order', to_jsonb(v_order)), null, false);
  return jsonb_build_object('status','active','turn_order',to_jsonb(g.turn_order),'idempotent',false);
end $$;

-- ── 7) resolve_late_join: idéntico + posición inicial en la salida para el nuevo jugador ──
create or replace function public.resolve_late_join(p_request_ref text, p_accept boolean, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.late_join_requests; g public.games; rt public.game_runtime; v_uid uuid;
        v_active int; v_max int; v_init int; np public.players; v_ver bigint;
begin
  select * into r from public.late_join_requests where public_ref=p_request_ref for update;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(r.game_id);
  if g.status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'idempotent', true); end if;
  select * into rt from public.game_runtime where game_id=g.id for update;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  if not p_accept then
    update public.late_join_requests set status='rejected', resolved_at=now() where id=r.id;
    perform public._audit(g.id,'late_join_rejected',auth.uid(),null,null,null,jsonb_build_object('request',r.public_ref),null,false);
    perform public._emit_active_signal(g.id);
    return jsonb_build_object('status','rejected');
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if not coalesce((g.config->>'allow_late_join')::boolean,false) then raise exception 'LATE_JOIN_DISABLED'; end if;
  v_max := coalesce((g.config->>'max_players')::int,16);
  select count(*) into v_active from public.players where game_id=g.id and kicked_at is null;
  if v_active >= v_max then raise exception 'GAME_FULL'; end if;
  perform 1 from public.players where game_id=g.id and kicked_at is null and display_name_norm=public.normalize_name(r.desired_name);
  if found then raise exception 'NAME_TAKEN'; end if;
  perform 1 from public.token_catalog where id=r.desired_token and active and catalog_version=coalesce((g.config->>'token_catalog_version')::int,0);
  if not found then raise exception 'TOKEN_INVALID'; end if;
  perform 1 from public.players where game_id=g.id and kicked_at is null and token_id=r.desired_token;
  if found then raise exception 'TOKEN_TAKEN'; end if;
  select requester_auth_uid into v_uid from public.request_secrets where request_id=r.id;
  perform 1 from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is null;
  if found then raise exception 'SESSION_HAS_ACTIVE_PLAYER'; end if;
  begin
    insert into public.players(game_id, auth_uid, display_name, token_id, join_status)
      values (g.id, v_uid, r.desired_name, r.desired_token, 'ready') returning * into np;
  exception when unique_violation then raise exception 'NAME_TAKEN'; end;
  v_init := coalesce((g.config->>'initial_money')::int, 3000);
  insert into public.player_balances(game_id, player_ref, balance) values (g.id, np.public_ref, v_init);
  if v_init > 0 then
    perform public._p2_post(g.id, 'late_join_seed', null, np.public_ref, v_init, null, null, null, null, null, r.id);
  end if;
  -- Fase 4: entrada tardía también empieza en la salida del tablero inicial.
  insert into public.player_positions(game_id, player_ref, board_key, space_index)
    values (g.id, np.public_ref, public._p4_initial_board(), 0) on conflict (game_id, player_ref) do nothing;
  update public.game_runtime set turn_order_refs = turn_order_refs || np.public_ref where game_id=g.id;
  v_ver := public._p2_bump(g.id);
  perform public._audit(g.id,'late_join_approved',auth.uid(),np.id,array[np.id],null,
    jsonb_build_object('request',r.public_ref,'player',np.public_ref,'balance',v_init,'appended_at_end',true),null,false);
  perform public._emit_active_signal(g.id);
  update public.late_join_requests set status='approved', resolved_at=now(), new_player_id=np.id where id=r.id;
  return jsonb_build_object('status','approved','new_public_ref',np.public_ref,'runtime_version',v_ver);
end $$;

-- ── 8) Backfill: partidas ya activas reciben posición inicial (autorreparación) ─────
do $$
declare r record;
begin
  for r in select id from public.games where status = 'active' loop
    perform public._p4_ensure_positions(r.id);
  end loop;
end $$;
