-- ============================================================================
-- Fase 7 — Tratos avanzados entre jugadores · Modelo de datos + ledger + helpers de validación/ejecución.
-- Patrón: tablas deny-all (solo vía RPC SECURITY DEFINER), public_ref opaco, idempotencia/version en las RPC
-- (0062), ejecución atómica. El dinero del trato es reconciliable en el ledger (kind 'trade_money'); las
-- transferencias de propiedades y cartas quedan en auditoría.
-- ============================================================================

-- ── 1) Estado del trato ─────────────────────────────────────────────────────
do $$ begin
  if not exists (select 1 from pg_type where typname = 'trade_status') then
    create type public.trade_status as enum
      ('pending','countered','host_review','executed','rejected','cancelled','invalidated');
  end if;
end $$;

-- ── 2) Propuestas de trato (deny-all) ───────────────────────────────────────
create table if not exists public.game_trade_proposals (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null default public.gen_public_ref(),
  game_id uuid not null references public.games(id) on delete cascade,
  from_ref text not null,                 -- creador (public_ref)
  to_ref text not null,                   -- contraparte (public_ref)
  from_money bigint not null default 0 check (from_money >= 0),
  to_money bigint not null default 0 check (to_money >= 0),
  agreement_text text null,
  requires_host boolean not null default false,
  pending_party text null,                -- de quién se espera la próxima acción (to_ref si pending; from_ref si countered)
  status public.trade_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz null,
  resolved_by_ref text null,
  result_seq bigint null,
  constraint trade_not_self check (from_ref <> to_ref),
  foreign key (game_id, from_ref) references public.players(game_id, public_ref),
  foreign key (game_id, to_ref) references public.players(game_id, public_ref)
);
create index if not exists game_trade_proposals_game_idx on public.game_trade_proposals(game_id, status);
alter table public.game_trade_proposals enable row level security;  -- deny-all

-- ── 3) Ítems del trato (propiedades / cartas, por lado) ──────────────────────
create table if not exists public.game_trade_items (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.game_trade_proposals(id) on delete cascade,
  side text not null check (side in ('from','to')),
  item_type text not null check (item_type in ('property','card')),
  ref text not null                       -- property_ref o card_ref
);
create index if not exists game_trade_items_proposal_idx on public.game_trade_items(proposal_id);
alter table public.game_trade_items enable row level security;  -- deny-all

-- ── 4) Ledger: nuevo kind 'trade_money' (dinero entre jugadores dentro de un trato) ──
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check CHECK ((kind = ANY (ARRAY[
  'seed','bank_to_player','player_to_bank','player_to_player','host_player_transfer','host_adjust','host_revert',
  'late_join_seed','player_exit_to_bank','player_exit_distribution','player_exit_remainder_to_bank',
  'property_purchase','rent_payment','property_auction_purchase','bankruptcy_cash_to_bank','bankruptcy_cash_to_player',
  'pass_start_bonus','guardian_toll','tax_payment','parking_pot_payout','jail_release_payment',
  'card_bank_payment','card_bank_charge','card_player_payment','card_player_charge',
  'building_purchase','building_sale','hotel_purchase','hotel_sale','mortgage_received','unmortgage_payment',
  'trade_money'])));

alter table public.ledger drop constraint ledger_shape;
alter table public.ledger add constraint ledger_shape CHECK (
CASE kind
    WHEN 'seed'::text THEN ((from_ref IS NULL) AND (to_ref IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'late_join_seed'::text THEN ((from_ref IS NULL) AND (to_ref IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'bank_to_player'::text THEN ((from_ref IS NULL) AND (to_ref IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'player_to_bank'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'player_to_player'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NOT NULL) AND (from_ref <> to_ref) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'host_player_transfer'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NOT NULL) AND (from_ref <> to_ref) AND (reason IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'host_adjust'::text THEN ((before_balance IS NOT NULL) AND (after_balance IS NOT NULL) AND (before_balance <> after_balance) AND (amount = abs((after_balance - before_balance))) AND (((after_balance > before_balance) AND (from_ref IS NULL) AND (to_ref IS NOT NULL)) OR ((after_balance < before_balance) AND (from_ref IS NOT NULL) AND (to_ref IS NULL))) AND (reason IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL))
    WHEN 'host_revert'::text THEN ((reverts_ledger_id IS NOT NULL) AND (reason IS NOT NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL) AND (((from_ref IS NULL) <> (to_ref IS NULL)) OR ((from_ref IS NOT NULL) AND (to_ref IS NOT NULL) AND (from_ref <> to_ref))))
    WHEN 'player_exit_to_bank'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'player_exit_distribution'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NOT NULL) AND (from_ref <> to_ref) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'player_exit_remainder_to_bank'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'property_purchase'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'rent_payment'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NOT NULL) AND (from_ref <> to_ref) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'property_auction_purchase'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'bankruptcy_cash_to_bank'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'bankruptcy_cash_to_player'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NOT NULL) AND (from_ref <> to_ref) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL))
    WHEN 'pass_start_bonus'::text THEN ((from_ref IS NULL) AND (to_ref IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'guardian_toll'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'tax_payment'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'jail_release_payment'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'card_bank_charge'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'parking_pot_payout'::text THEN ((from_ref IS NULL) AND (to_ref IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'card_bank_payment'::text THEN ((from_ref IS NULL) AND (to_ref IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'card_player_charge'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NOT NULL) AND (from_ref <> to_ref) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'card_player_payment'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NOT NULL) AND (from_ref <> to_ref) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'building_purchase'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'building_sale'::text THEN ((from_ref IS NULL) AND (to_ref IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'hotel_purchase'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'hotel_sale'::text THEN ((from_ref IS NULL) AND (to_ref IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'mortgage_received'::text THEN ((from_ref IS NULL) AND (to_ref IS NOT NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'unmortgage_payment'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NULL) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    WHEN 'trade_money'::text THEN ((from_ref IS NOT NULL) AND (to_ref IS NOT NULL) AND (from_ref <> to_ref) AND (reverts_ledger_id IS NULL) AND (request_id IS NOT NULL) AND (before_balance IS NULL) AND (after_balance IS NULL))
    ELSE false
END);

-- ── 5) Helpers ──────────────────────────────────────────────────────────────
-- Límite de dinero por lado de un trato (coherente con el tope de _p2_move).
create or replace function public._p7_money_cap() returns bigint language sql immutable as $$ select 10000000::bigint $$;

-- ¿jugador activo para tratos? (existe, no expulsado/abandonado/en bancarrota)
create or replace function public._p7_active(p_game uuid, p_ref text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.players where game_id=p_game and public_ref=p_ref
                  and kicked_at is null and left_at is null and bankrupt_at is null);
$$;

-- ¿propiedad incluida en algún trato pendiente (excluyendo uno)?
create or replace function public._p7_prop_in_pending(p_game uuid, p_prop text, p_exclude uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.game_trade_items i join public.game_trade_proposals pr on pr.id=i.proposal_id
    where pr.game_id=p_game and pr.status in ('pending','countered','host_review')
      and i.item_type='property' and i.ref=p_prop and (p_exclude is null or pr.id <> p_exclude));
$$;

-- ¿carta (card_ref) ya ofrecida por un jugador en otro trato pendiente?
create or replace function public._p7_card_in_pending(p_game uuid, p_owner text, p_card text, p_exclude uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.game_trade_items i join public.game_trade_proposals pr on pr.id=i.proposal_id
    where pr.game_id=p_game and pr.status in ('pending','countered','host_review') and i.item_type='card' and i.ref=p_card
      and (p_exclude is null or pr.id <> p_exclude)
      and ((i.side='from' and pr.from_ref=p_owner) or (i.side='to' and pr.to_ref=p_owner)));
$$;

-- ¿la propiedad tiene construcciones (casas u hotel)?
create or replace function public._p7_has_buildings(p_game uuid, p_prop text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select houses > 0 or has_hotel from public.game_property_state where game_id=p_game and property_ref=p_prop), false);
$$;

-- requires_host = hay propiedades, cartas o acuerdo personal (solo dinero ⇒ no requiere anfitrión)
create or replace function public._p7_needs_host(p_from_props text[], p_to_props text[], p_from_cards text[], p_to_cards text[], p_agreement text) returns boolean
language sql immutable as $$
  select coalesce(array_length(p_from_props,1),0) > 0 or coalesce(array_length(p_to_props,1),0) > 0
      or coalesce(array_length(p_from_cards,1),0) > 0 or coalesce(array_length(p_to_cards,1),0) > 0
      or nullif(btrim(coalesce(p_agreement,'')),'') is not null;
$$;

-- Validación COMPLETA de los términos (lanza error saneado si algo no es válido). Se usa al crear y al ejecutar.
create or replace function public._p7_check(
  p_game uuid, p_from text, p_to text, p_from_money bigint, p_to_money bigint,
  p_from_props text[], p_to_props text[], p_from_cards text[], p_to_cards text[], p_exclude uuid
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_prop text; v_card text; v_bal bigint; v_cap bigint := public._p7_money_cap();
begin
  if p_from = p_to then raise exception 'SELF_TRADE_NOT_ALLOWED'; end if;
  if not public._p7_active(p_game, p_from) or not public._p7_active(p_game, p_to) then raise exception 'PLAYER_NOT_ACTIVE'; end if;
  -- Dinero: enteros no negativos, dentro del tope, y con saldo suficiente.
  if p_from_money is null or p_from_money < 0 or p_from_money > v_cap or p_to_money is null or p_to_money < 0 or p_to_money > v_cap then
    raise exception 'INVALID_TRADE_AMOUNT';
  end if;
  if p_from_money > 0 then
    select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_from;
    if coalesce(v_bal,0) < p_from_money then raise exception 'INSUFFICIENT_FUNDS'; end if;
  end if;
  if p_to_money > 0 then
    select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_to;
    if coalesce(v_bal,0) < p_to_money then raise exception 'INSUFFICIENT_FUNDS'; end if;
  end if;
  -- Propiedades del lado A (las ofrece p_from).
  if p_from_props is not null then foreach v_prop in array p_from_props loop
    if not exists(select 1 from public.property_ownership where game_id=p_game and property_ref=v_prop and owner_ref=p_from and released_at is null) then raise exception 'PROPERTY_NOT_OWNED'; end if;
    if public._p7_has_buildings(p_game, v_prop) then raise exception 'PROPERTY_HAS_BUILDINGS'; end if;
    if public._p7_prop_in_pending(p_game, v_prop, p_exclude) then raise exception 'PROPERTY_ALREADY_IN_PENDING_TRADE'; end if;
  end loop; end if;
  -- Propiedades del lado B (las ofrece p_to).
  if p_to_props is not null then foreach v_prop in array p_to_props loop
    if not exists(select 1 from public.property_ownership where game_id=p_game and property_ref=v_prop and owner_ref=p_to and released_at is null) then raise exception 'PROPERTY_NOT_OWNED'; end if;
    if public._p7_has_buildings(p_game, v_prop) then raise exception 'PROPERTY_HAS_BUILDINGS'; end if;
    if public._p7_prop_in_pending(p_game, v_prop, p_exclude) then raise exception 'PROPERTY_ALREADY_IN_PENDING_TRADE'; end if;
  end loop; end if;
  -- Cartas del lado A.
  if p_from_cards is not null then foreach v_card in array p_from_cards loop
    if not exists(select 1 from public.game_held_cards where game_id=p_game and player_ref=p_from and card_ref=v_card) then raise exception 'CARD_NOT_OWNED'; end if;
    if public._p7_card_in_pending(p_game, p_from, v_card, p_exclude) then raise exception 'CARD_ALREADY_IN_PENDING_TRADE'; end if;
  end loop; end if;
  -- Cartas del lado B.
  if p_to_cards is not null then foreach v_card in array p_to_cards loop
    if not exists(select 1 from public.game_held_cards where game_id=p_game and player_ref=p_to and card_ref=v_card) then raise exception 'CARD_NOT_OWNED'; end if;
    if public._p7_card_in_pending(p_game, p_to, v_card, p_exclude) then raise exception 'CARD_ALREADY_IN_PENDING_TRADE'; end if;
  end loop; end if;
end $$;

-- Transferencia atómica (asume términos ya validados por _p7_check). Mueve dinero, propiedades y cartas.
create or replace function public._p7_transfer(p_proposal_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare pr public.game_trade_proposals; it record;
begin
  select * into pr from public.game_trade_proposals where id = p_proposal_id;
  -- Dinero (un asiento por lado con importe > 0; request_id único por asiento).
  if pr.from_money > 0 then
    perform public._p2_move(pr.game_id, pr.from_ref, pr.to_ref, pr.from_money);
    perform public._p2_post(pr.game_id, 'trade_money', pr.from_ref, pr.to_ref, pr.from_money, null, null, 'Trato '||pr.public_ref, pr.from_ref, null, gen_random_uuid());
  end if;
  if pr.to_money > 0 then
    perform public._p2_move(pr.game_id, pr.to_ref, pr.from_ref, pr.to_money);
    perform public._p2_post(pr.game_id, 'trade_money', pr.to_ref, pr.from_ref, pr.to_money, null, null, 'Trato '||pr.public_ref, pr.to_ref, null, gen_random_uuid());
  end if;
  -- Propiedades: lado 'from' → to_ref; lado 'to' → from_ref.
  for it in select side, ref from public.game_trade_items where proposal_id=p_proposal_id and item_type='property' loop
    update public.property_ownership set released_at=now(), released_reason='trade'
      where game_id=pr.game_id and property_ref=it.ref and released_at is null;
    insert into public.property_ownership(game_id, property_ref, owner_ref)
      values (pr.game_id, it.ref, case when it.side='from' then pr.to_ref else pr.from_ref end);
    perform public._audit(pr.game_id, 'trade_property_transferred', auth.uid(), null, null, null,
      jsonb_build_object('property', it.ref, 'from', case when it.side='from' then pr.from_ref else pr.to_ref end,
                         'to', case when it.side='from' then pr.to_ref else pr.from_ref end, 'trade', pr.public_ref), null, false);
  end loop;
  -- Cartas: lado 'from' → to_ref; lado 'to' → from_ref (mueve UNA del tipo).
  for it in select side, ref from public.game_trade_items where proposal_id=p_proposal_id and item_type='card' loop
    delete from public.game_held_cards where id = (
      select id from public.game_held_cards where game_id=pr.game_id
        and player_ref = case when it.side='from' then pr.from_ref else pr.to_ref end
        and card_ref = it.ref order by acquired_at limit 1);
    insert into public.game_held_cards(game_id, player_ref, card_ref)
      values (pr.game_id, case when it.side='from' then pr.to_ref else pr.from_ref end, it.ref);
    perform public._audit(pr.game_id, 'trade_card_transferred', auth.uid(), null, null, null,
      jsonb_build_object('card', it.ref, 'from', case when it.side='from' then pr.from_ref else pr.to_ref end,
                         'to', case when it.side='from' then pr.to_ref else pr.from_ref end, 'trade', pr.public_ref), null, false);
  end loop;
end $$;

revoke all on function public._p7_active(uuid,text) from public, anon, authenticated;
revoke all on function public._p7_prop_in_pending(uuid,text,uuid) from public, anon, authenticated;
revoke all on function public._p7_card_in_pending(uuid,text,text,uuid) from public, anon, authenticated;
revoke all on function public._p7_has_buildings(uuid,text) from public, anon, authenticated;
revoke all on function public._p7_check(uuid,text,text,bigint,bigint,text[],text[],text[],text[],uuid) from public, anon, authenticated;
revoke all on function public._p7_transfer(uuid) from public, anon, authenticated;
