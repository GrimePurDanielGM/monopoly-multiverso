-- Fase 3 — Sistema base de propiedades: catálogo, posesión, compra y alquiler básico.
-- Sin casas/hoteles/hipotecas/subastas/cartas/cárcel/dado/movimiento por casillas (fases posteriores).
-- Refs públicas opacas; nada de ids internos en cliente. Mutaciones con el patrón Fase 2:
-- idempotencia -> lock game_runtime -> runtime_status -> versión -> permisos -> efecto -> auditoría -> 1 Broadcast.

-- ── 1) Catálogo de propiedades (referencia global, controlado por migración) ──────
create table public.property_catalog (
  id uuid primary key default gen_random_uuid(),                 -- interno, NUNCA expuesto
  property_ref text not null unique,                             -- opaco público
  board_key  text not null check (board_key in ('classic','back_to_the_future')),
  group_key  text not null,
  name       text not null,
  kind       text not null check (kind in ('street','station','utility','special')),
  price      int  not null check (price >= 0),
  base_rent  int  not null check (base_rent >= 0),
  is_buyable boolean not null default true,
  sort_order int  not null default 0,
  catalog_version int not null default 0,
  active boolean not null default true,
  -- Una propiedad comprable debe tener precio y alquiler > 0 (el ledger exige amount > 0).
  constraint property_buyable_positive check (not is_buyable or (price > 0 and base_rent > 0))
);
create index property_catalog_board_idx on public.property_catalog (board_key, sort_order) where active;
alter table public.property_catalog enable row level security;   -- deny-all: solo SECURITY DEFINER
revoke all on public.property_catalog from anon, authenticated;

-- Catálogo mínimo de prueba: varias propiedades por tablero (ampliable). Refs opacas y estables.
insert into public.property_catalog (property_ref, board_key, group_key, name, kind, price, base_rent, is_buyable, sort_order) values
  -- Clásico
  ('cl-marron-1',  'classic','marron',   'Avenida Mediterráneo','street', 60,  2, true, 10),
  ('cl-marron-2',  'classic','marron',   'Avenida Báltica',     'street', 60,  4, true, 11),
  ('cl-celeste-1', 'classic','celeste',  'Avenida Oriental',    'street', 100, 6, true, 20),
  ('cl-celeste-2', 'classic','celeste',  'Avenida Vermont',     'street', 100, 6, true, 21),
  ('cl-estacion-1','classic','estaciones','Estación Sur',       'station',200, 25,true, 30),
  ('cl-servicio-1','classic','servicios','Compañía de Aguas',   'utility',150, 10,true, 40),
  ('cl-salida',    'classic','especial', 'Salida',              'special',0,   0, false,1),
  -- Regreso al futuro
  ('bf-1955-1',    'back_to_the_future','hv1955','Plaza Hill Valley 1955','street', 80,  4, true, 10),
  ('bf-1955-2',    'back_to_the_future','hv1955','Cafetería de Lou',      'street', 80,  6, true, 11),
  ('bf-2015-1',    'back_to_the_future','hv2015','Hill Valley 2015',      'street', 120, 8, true, 20),
  ('bf-2015-2',    'back_to_the_future','hv2015','Café de los 80',        'street', 120, 8, true, 21),
  ('bf-estacion-1','back_to_the_future','estaciones','Estación DeLorean', 'station',200, 25,true, 30),
  ('bf-servicio-1','back_to_the_future','servicios','Reactor Mr. Fusion', 'utility',150, 10,true, 40),
  ('bf-flux',      'back_to_the_future','especial','Condensador de Flujo','special',0,   0, false,1);

-- ── 2) Posesión por jugador (per-game, episódica: conserva historial) ─────────────
create table public.property_ownership (
  id uuid primary key default gen_random_uuid(),                 -- interno, NUNCA expuesto
  game_id uuid not null references public.games(id) on delete cascade,
  property_ref text not null references public.property_catalog(property_ref),
  owner_ref text not null,                                       -- public_ref del propietario (histórico)
  acquired_at timestamptz not null default now(),
  acquired_by_ledger_ref text null,                             -- ledger_ref de la compra
  released_at timestamptz null,                                 -- null = posesión ACTIVA
  released_reason text null,
  created_at timestamptz not null default now()
);
-- Como máximo UN propietario activo por (partida, propiedad). Disponible = sin fila activa.
create unique index property_one_active_owner on public.property_ownership (game_id, property_ref) where released_at is null;
create index property_owner_idx on public.property_ownership (game_id, owner_ref) where released_at is null;
alter table public.property_ownership enable row level security;  -- deny-all: solo SECURITY DEFINER
revoke all on public.property_ownership from anon, authenticated;

-- ── 3) Tipos de ledger de propiedades (reconciliables). Devolución a banca = auditoría (sin dinero) ──
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check check (kind in
  ('seed','bank_to_player','player_to_bank','player_to_player','host_player_transfer','host_adjust','host_revert','late_join_seed',
   'player_exit_to_bank','player_exit_distribution','player_exit_remainder_to_bank',
   'property_purchase','rent_payment'));
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
    when 'property_purchase' then         -- jugador -> banca (precio)
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'rent_payment' then              -- pagador -> propietario (alquiler)
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    else false
  end
);

-- ── 4) buy_property: solo jugador activo; running; idempotente ─────────────────────
create or replace function public.buy_property(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog;
        v_idem jsonb; v_ver bigint; v_ledger text; v_bal bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);                                       -- 2) bloqueo
  v_idem := public._p2_idem(p_game, p_request_id);                     -- 1) idempotencia + 3) estado (pausa/finished)
  if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);                         -- 5) permisos
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if not c.is_buyable then raise exception 'PROPERTY_NOT_BUYABLE'; end if;
  if not (me.public_ref = any(rt.turn_order_refs)) then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  perform 1 from public.property_ownership where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if found then raise exception 'PROPERTY_ALREADY_OWNED'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;  -- 4) versión
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < c.price then raise exception 'INSUFFICIENT_FUNDS'; end if;
  -- 6) efecto: paga el precio a la banca y queda como propietario
  perform public._p2_move(p_game, me.public_ref, null, c.price);
  v_ledger := public._p2_post(p_game, 'property_purchase', me.public_ref, null, c.price,
                              null, null, null, me.public_ref, null, p_request_id);
  insert into public.property_ownership(game_id, property_ref, owner_ref, acquired_by_ledger_ref)
    values (p_game, p_property_ref, me.public_ref, v_ledger);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'property_purchased', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', c.property_ref, 'price', c.price), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', c.property_ref, 'owner_ref', me.public_ref,
                              'price', c.price, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'buy_property', v_res);
  return v_res;
end $$;

-- ── 5) pay_rent: solo el pagador activo; al propietario activo; running; idempotente ──
create or replace function public.pay_rent(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_owner text;
        v_idem jsonb; v_ver bigint; v_bal bigint; v_amount bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id);
  if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  select owner_ref into v_owner from public.property_ownership
    where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if v_owner is null then raise exception 'PROPERTY_NOT_OWNED'; end if;
  if not (v_owner = any(rt.turn_order_refs)) then raise exception 'PROPERTY_NOT_OWNED'; end if;  -- propietario fuera de partida
  if v_owner = me.public_ref then raise exception 'SELF_RENT'; end if;
  v_amount := c.base_rent;
  if v_amount <= 0 then raise exception 'NO_RENT_DUE'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < v_amount then raise exception 'INSUFFICIENT_FUNDS'; end if;
  -- efecto: transfiere el alquiler del pagador al propietario
  perform public._p2_move(p_game, me.public_ref, v_owner, v_amount);
  perform public._p2_post(p_game, 'rent_payment', me.public_ref, v_owner, v_amount,
                          null, null, null, me.public_ref, null, p_request_id);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'rent_paid', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', c.property_ref, 'payer', me.public_ref, 'owner', v_owner, 'amount', v_amount), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', c.property_ref, 'paid_to', v_owner, 'amount', v_amount,
                              'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'pay_rent', v_res);
  return v_res;
end $$;

grant execute on function public.buy_property(uuid, text, uuid, bigint) to authenticated;
grant execute on function public.pay_rent(uuid, text, uuid, bigint)     to authenticated;

-- ── 6) Salida/expulsión: además del dinero y el orden de turnos, las propiedades vuelven a banca ──
-- (Misma transacción; conserva historial; no se reparten ni subastan; auditoría sin ledger monetario.)
create or replace function public._p2_remove_player(
  p_game uuid, p_target public.players, p_mode text, p_reason text, p_removed_by text
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; v_bal bigint; v_remaining text[]; n int;
        v_quotient bigint; v_remainder bigint := 0; r text;
        v_cur text; v_left_is_cur boolean; v_new_cur text; v_new_idx int; v_ver bigint; v_returned jsonb;
begin
  select * into rt from public.game_runtime where game_id = p_game for update;     -- reafirma el bloqueo
  if not (p_target.public_ref = any(rt.turn_order_refs)) then raise exception 'TARGET_NOT_IN_GAME'; end if;
  v_cur := rt.turn_order_refs[rt.turn_index];
  v_left_is_cur := (p_target.public_ref = v_cur);

  -- Saldo del saliente (bloquea su fila).
  select balance into v_bal from public.player_balances
    where game_id = p_game and player_ref = p_target.public_ref for update;
  v_bal := coalesce(v_bal, 0);

  -- Restantes activos, en el mismo orden relativo (sin el saliente).
  select array_agg(x order by ord) into v_remaining
    from unnest(rt.turn_order_refs) with ordinality as t(x, ord)
    where x <> p_target.public_ref;
  n := coalesce(array_length(v_remaining, 1), 0);
  if n < 1 then raise exception 'NO_REMAINING_PLAYERS'; end if;   -- el anfitrión siempre permanece

  -- Resolución del dinero (reconciliable; banco = NULL).
  if p_mode = 'distribute' then
    v_quotient := v_bal / n;                       -- división entera
    v_remainder := v_bal - v_quotient * n;         -- resto -> banca
    if v_quotient > 0 then
      foreach r in array v_remaining loop
        update public.player_balances set balance = balance + v_quotient, updated_at = now()
          where game_id = p_game and player_ref = r;
        perform public._p2_post(p_game, 'player_exit_distribution', p_target.public_ref, r, v_quotient,
                                null, null, null, p_removed_by, null, gen_random_uuid());
      end loop;
    end if;
    if v_remainder > 0 then
      perform public._p2_post(p_game, 'player_exit_remainder_to_bank', p_target.public_ref, null, v_remainder,
                              null, null, null, p_removed_by, null, gen_random_uuid());
    end if;
  else  -- 'to_bank' (por defecto)
    if v_bal > 0 then
      perform public._p2_post(p_game, 'player_exit_to_bank', p_target.public_ref, null, v_bal,
                              null, null, null, p_removed_by, null, gen_random_uuid());
    end if;
  end if;
  update public.player_balances set balance = 0, updated_at = now()
    where game_id = p_game and player_ref = p_target.public_ref;

  -- Propiedades activas del saliente -> banca (disponibles para compra). Conserva historial.
  with returned as (
    update public.property_ownership set released_at = now(), released_reason = 'player_exit'
     where game_id = p_game and owner_ref = p_target.public_ref and released_at is null
    returning property_ref
  )
  select coalesce(jsonb_agg(property_ref order by property_ref), '[]'::jsonb) into v_returned from returned;
  if v_returned <> '[]'::jsonb then
    perform public._audit(p_game, 'properties_returned_to_bank', auth.uid(), p_target.id, array[p_target.id],
              null, jsonb_build_object('properties', v_returned, 'reason', 'player_exit'), p_reason, false);
  end if;

  -- Orden de turnos: quitar al saliente preservando current = turn_order_refs[turn_index].
  if v_left_is_cur then
    v_new_cur := rt.turn_order_refs[(rt.turn_index % array_length(rt.turn_order_refs, 1)) + 1];  -- siguiente válido
  else
    v_new_cur := v_cur;                                                                          -- el actual no cambia
  end if;
  v_new_idx := array_position(v_remaining, v_new_cur);
  if v_new_idx is null then v_new_idx := 1; end if;   -- salvaguarda
  update public.game_runtime set turn_order_refs = v_remaining, turn_index = v_new_idx
    where game_id = p_game;   -- turn_number intacto

  -- Marca de salida (conserva fila e historial; deja de ser participante activo).
  update public.players set left_at = now(), left_reason = nullif(btrim(coalesce(p_reason,'')),''),
         removed_by_ref = p_removed_by, row_version = row_version + 1
    where id = p_target.id;

  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'player_left', auth.uid(), p_target.id, array[p_target.id],
            jsonb_build_object('balance', v_bal, 'was_current', v_left_is_cur),
            jsonb_build_object('mode', p_mode, 'removed_by', p_removed_by, 'remaining', n,
                               'distributed', case when p_mode='distribute' then v_bal - v_remainder else 0 end,
                               'remainder_to_bank', v_remainder, 'properties_returned', v_returned), p_reason, false);
  perform public._emit_active_signal(p_game);
  return jsonb_build_object('left_ref', p_target.public_ref, 'mode', p_mode,
                            'amount', v_bal, 'properties_returned', v_returned, 'runtime_version', v_ver);
end $$;
revoke all on function public._p2_remove_player(uuid, public.players, text, text, text) from public, anon, authenticated;

-- ── 7) Snapshot activo: añade 'properties' (catálogo + propietario actual, saneado) ──
create or replace function public.get_active_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; rt public.game_runtime; me public.players; v_cur text; v_players jsonb; v_ledger jsonb;
        v_is_host boolean; v_late jsonb; v_props jsonb;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where code = upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode = 'P0002'; end if;
  if g.status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  select * into me from public.players where game_id = g.id and auth_uid = auth.uid() and kicked_at is null and left_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  select * into rt from public.game_runtime where game_id = g.id;
  v_cur := rt.turn_order_refs[rt.turn_index];
  v_is_host := me.id = g.host_player_id;

  select jsonb_agg(jsonb_build_object(
           'public_ref', p.public_ref, 'display_name', p.display_name, 'token_id', p.token_id,
           'balance', b.balance, 'is_current', p.public_ref = v_cur)
           order by array_position(rt.turn_order_refs, p.public_ref))
    into v_players
    from public.players p
    join public.player_balances b on b.game_id = p.game_id and b.player_ref = p.public_ref
    where p.game_id = g.id and p.public_ref = any(rt.turn_order_refs);

  select jsonb_agg(jsonb_build_object(
           'ledger_ref', l.ledger_ref, 'seq', l.seq, 'kind', l.kind, 'from_ref', l.from_ref, 'to_ref', l.to_ref,
           'amount', l.amount, 'before_balance', l.before_balance, 'after_balance', l.after_balance,
           'reason', l.reason, 'actor_ref', l.actor_ref,
           'reverts_ref', (select r.ledger_ref from public.ledger r where r.id = l.reverts_ledger_id),
           'created_at', l.created_at) order by l.seq desc)
    into v_ledger
    from (select * from public.ledger where game_id = g.id order by seq desc limit 25) l;

  -- Propiedades: catálogo activo + propietario actual (null = disponible en banca). Sin ids internos.
  select coalesce(jsonb_agg(jsonb_build_object(
           'property_ref', c.property_ref, 'board_key', c.board_key, 'group_key', c.group_key,
           'name', c.name, 'kind', c.kind, 'price', c.price, 'base_rent', c.base_rent,
           'is_buyable', c.is_buyable, 'sort_order', c.sort_order,
           'owner_ref', (select o.owner_ref from public.property_ownership o
                          where o.game_id = g.id and o.property_ref = c.property_ref and o.released_at is null))
           order by c.board_key, c.sort_order), '[]'::jsonb)
    into v_props
    from public.property_catalog c where c.active;

  if v_is_host then
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', lr.public_ref, 'name', lr.desired_name, 'token', lr.desired_token,
             'device_label', lr.device_label) order by lr.created_at), '[]'::jsonb)
      into v_late from public.late_join_requests lr where lr.game_id=g.id and lr.status='pending';
  else
    v_late := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'game', jsonb_build_object('code', g.code, 'status', g.status,
      'config', jsonb_build_object(
        'initial_money', coalesce((g.config->>'initial_money')::int, 3000),
        'min_players',   coalesce((g.config->>'min_players')::int, 6),
        'max_players',   coalesce((g.config->>'max_players')::int, 16),
        'allow_late_join', coalesce((g.config->>'allow_late_join')::boolean, false))),
    'me', jsonb_build_object('public_ref', me.public_ref, 'is_host', v_is_host,
      'balance', (select balance from public.player_balances where game_id = g.id and player_ref = me.public_ref),
      'is_current', me.public_ref = v_cur),
    'turn', jsonb_build_object('turn_number', rt.turn_number, 'current_player_ref', v_cur,
      'order', to_jsonb(rt.turn_order_refs)),
    'players', coalesce(v_players, '[]'::jsonb),
    'ledger_recent', coalesce(v_ledger, '[]'::jsonb),
    'properties', v_props,
    'late_join_requests', v_late,
    'runtime_status', rt.runtime_status,
    'control', jsonb_build_object(
      'paused_by_ref', rt.paused_by_ref, 'finished_by_ref', rt.finished_by_ref, 'reason', rt.status_reason),
    'runtime_version', rt.runtime_version);
end $$;
