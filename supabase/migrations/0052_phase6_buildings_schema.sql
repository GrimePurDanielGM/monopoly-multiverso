-- Fase 6 — Casas, hoteles e hipotecas (solo CALLES de color). Esquema, stock, helpers y triggers.
-- · game_property_state: estado de construcción/hipoteca por propiedad (calle) de una partida.
-- · game_runtime.houses_available (32) / hotels_available (12): stock físico del banco por partida.
-- · monopolio = poseer TODAS las calles del grupo dentro de su MISMO tablero (no se combinan tableros).
-- · al liberar una propiedad (venta/bancarrota/salida) un trigger devuelve sus construcciones al stock.
-- Mantiene RLS deny-all, snapshot saneado y los patrones de Fases 1–5.

-- ── Nuevos kinds de ledger (construcción/venta/hipoteca) en las constraints existentes ──
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check CHECK ((kind = ANY (ARRAY['seed'::text, 'bank_to_player'::text, 'player_to_bank'::text, 'player_to_player'::text, 'host_player_transfer'::text, 'host_adjust'::text, 'host_revert'::text, 'late_join_seed'::text, 'player_exit_to_bank'::text, 'player_exit_distribution'::text, 'player_exit_remainder_to_bank'::text, 'property_purchase'::text, 'rent_payment'::text, 'property_auction_purchase'::text, 'bankruptcy_cash_to_bank'::text, 'bankruptcy_cash_to_player'::text, 'pass_start_bonus'::text, 'guardian_toll'::text, 'tax_payment'::text, 'parking_pot_payout'::text, 'jail_release_payment'::text, 'card_bank_payment'::text, 'card_bank_charge'::text, 'card_player_payment'::text, 'card_player_charge'::text, 'building_purchase'::text, 'building_sale'::text, 'hotel_purchase'::text, 'hotel_sale'::text, 'mortgage_received'::text, 'unmortgage_payment'::text])));

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
    ELSE false
END);

-- ── Stock físico del banco por partida ──
alter table public.game_runtime add column if not exists houses_available int not null default 32;
alter table public.game_runtime add column if not exists hotels_available int not null default 12;

-- ── Estado de construcción/hipoteca por propiedad (solo calles que tengan estado) ──
create table if not exists public.game_property_state (
  game_id uuid not null references public.games(id) on delete cascade,
  property_ref text not null,
  houses int not null default 0 check (houses between 0 and 4),
  has_hotel boolean not null default false,
  mortgaged boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (game_id, property_ref),
  constraint gps_no_houses_with_hotel check (not (has_hotel and houses > 0))
);
alter table public.game_property_state enable row level security;  -- deny-all: solo accesible vía RPC SECURITY DEFINER

-- ── Helpers de monopolio / grupo (por TABLERO + grupo de color, solo calles) ──
create or replace function public._p6_group_total(p_board text, p_group text) returns int language sql stable as $$
  select count(*)::int from public.property_catalog where board_key=p_board and group_key=p_group and kind='street' and active;
$$;
-- nº de calles del grupo (board+group) que posee un jugador en la partida
create or replace function public._p6_owns_in_group(p_game uuid, p_owner text, p_board text, p_group text) returns int language sql stable security definer set search_path=public,pg_temp as $$
  select count(*)::int from public.property_ownership o
    join public.property_catalog c on c.property_ref=o.property_ref
    where o.game_id=p_game and o.owner_ref=p_owner and o.released_at is null
      and c.board_key=p_board and c.group_key=p_group and c.kind='street' and c.active;
$$;
-- ¿el dueño de p_prop posee TODO su grupo? (monopolio); false si no es calle o no tiene dueño
create or replace function public._p6_is_monopoly(p_game uuid, p_prop text) returns boolean language plpgsql stable security definer set search_path=public,pg_temp as $$
declare c public.property_catalog; v_owner text; begin
  select * into c from public.property_catalog where property_ref=p_prop and active;
  if not found or c.kind<>'street' then return false; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_prop and released_at is null;
  if v_owner is null then return false; end if;
  return public._p6_owns_in_group(p_game, v_owner, c.board_key, c.group_key) = public._p6_group_total(c.board_key, c.group_key);
end $$;
-- coste de deshipoteca = hipoteca + 10% (redondeo hacia arriba)
create or replace function public._p6_unmortgage_cost(p_mortgage int) returns int language sql immutable as $$
  select case when p_mortgage is null then null else ceil(p_mortgage * 1.1)::int end;
$$;
-- estado (houses, has_hotel, mortgaged) de una propiedad, con valores por defecto si no hay fila
create or replace function public._p6_state(p_game uuid, p_prop text) returns table(houses int, has_hotel boolean, mortgaged boolean)
  language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(s.houses,0), coalesce(s.has_hotel,false), coalesce(s.mortgaged,false)
  from (select 1) z left join public.game_property_state s on s.game_id=p_game and s.property_ref=p_prop;
$$;
revoke all on function public._p6_owns_in_group(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public._p6_is_monopoly(uuid,text) from public, anon, authenticated;
revoke all on function public._p6_state(uuid,text) from public, anon, authenticated;

-- ── Al LIBERAR una propiedad (venta/subasta/bancarrota/salida) se devuelven sus construcciones al banco
--    y se limpia su estado. Garantiza que el stock siempre cuadra aunque Fases 2/3 no conozcan Fase 6. ──
create or replace function public._p6_on_release() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare st public.game_property_state; begin
  if new.released_at is not null and old.released_at is null then
    select * into st from public.game_property_state where game_id=new.game_id and property_ref=new.property_ref;
    if found then
      -- las casas vuelven al stock; un hotel devuelve 1 hotel (sus 4 casas ya volvieron al construirlo).
      update public.game_runtime set
        houses_available = houses_available + st.houses,
        hotels_available = hotels_available + (case when st.has_hotel then 1 else 0 end)
        where game_id=new.game_id;
      delete from public.game_property_state where game_id=new.game_id and property_ref=new.property_ref;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_p6_on_release on public.property_ownership;
create trigger trg_p6_on_release before update on public.property_ownership
  for each row execute function public._p6_on_release();

-- ── Helpers de uniformidad de construcción (nivel = hotel→5, si no nº de casas) y de hipoteca en el grupo ──
-- nivel mínimo entre las calles del grupo (board+group); calles sin fila cuentan como 0.
create or replace function public._p6_group_min_level(p_game uuid, p_board text, p_group text) returns int
  language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(min(case when s.has_hotel then 5 else coalesce(s.houses,0) end), 0)
  from public.property_catalog c
  left join public.game_property_state s on s.game_id=p_game and s.property_ref=c.property_ref
  where c.board_key=p_board and c.group_key=p_group and c.kind='street' and c.active;
$$;
-- nivel máximo entre las calles del grupo (para la venta uniforme inversa).
create or replace function public._p6_group_max_level(p_game uuid, p_board text, p_group text) returns int
  language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(max(case when s.has_hotel then 5 else coalesce(s.houses,0) end), 0)
  from public.property_catalog c
  left join public.game_property_state s on s.game_id=p_game and s.property_ref=c.property_ref
  where c.board_key=p_board and c.group_key=p_group and c.kind='street' and c.active;
$$;
-- ¿alguna calle del grupo está hipotecada?
create or replace function public._p6_group_has_mortgage(p_game uuid, p_board text, p_group text) returns boolean
  language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.property_catalog c
    join public.game_property_state s on s.game_id=p_game and s.property_ref=c.property_ref
    where c.board_key=p_board and c.group_key=p_group and c.kind='street' and c.active and s.mortgaged);
$$;
-- ¿todas las DEMÁS calles del grupo (≠ p_prop) están en 4 casas u hotel? (requisito para construir hotel)
create or replace function public._p6_group_rest_max(p_game uuid, p_board text, p_group text, p_prop text) returns boolean
  language sql stable security definer set search_path=public,pg_temp as $$
  select not exists(select 1 from public.property_catalog c
    left join public.game_property_state s on s.game_id=p_game and s.property_ref=c.property_ref
    where c.board_key=p_board and c.group_key=p_group and c.kind='street' and c.active and c.property_ref<>p_prop
      and not (coalesce(s.has_hotel,false) or coalesce(s.houses,0)=4));
$$;
revoke all on function public._p6_group_min_level(uuid,text,text) from public, anon, authenticated;
revoke all on function public._p6_group_max_level(uuid,text,text) from public, anon, authenticated;
revoke all on function public._p6_group_has_mortgage(uuid,text,text) from public, anon, authenticated;
revoke all on function public._p6_group_rest_max(uuid,text,text,text) from public, anon, authenticated;
