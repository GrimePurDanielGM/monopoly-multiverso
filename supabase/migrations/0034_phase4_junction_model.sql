-- Fase 4 (corrección 4) — Modelo del CRUCE entre tableros (intersección con guardián).
-- · game_guardians: posición dinámica del guardián de cada tablero por partida ('own' custodia la
--   continuación en tu propio tablero; 'cross' custodia el paso al Parking del otro tablero). Por defecto
--   custodia el cruce ('cross'), de modo que seguir en tu tablero es gratis y cruzar paga peaje.
-- · game_runtime.pending_junction: cuando un movimiento alcanza la cárcel-guardián con pasos restantes,
--   el movimiento se DETIENE ahí y el jugador debe elegir destino (no avanza solo).
-- · ledger 'guardian_toll': peaje (jugador -> banca) al pasar por la entrada custodiada.

create table public.game_guardians (
  game_id uuid not null references public.games(id) on delete cascade,
  board_key text not null check (board_key in ('classic','back_to_the_future')),
  guards text not null default 'cross' check (guards in ('own','cross')),
  updated_at timestamptz not null default now(),
  primary key (game_id, board_key)
);
alter table public.game_guardians enable row level security;   -- deny-all: solo SECURITY DEFINER
revoke all on public.game_guardians from anon, authenticated;

alter table public.game_runtime add column if not exists pending_junction jsonb null;

-- Siembra idempotente de los guardianes de una partida (ambos tableros, custodiando el cruce).
create or replace function public._p4_ensure_guardians(p_game uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.game_guardians(game_id, board_key, guards)
  select p_game, b.board_key, 'cross'
  from (values ('classic'),('back_to_the_future')) as b(board_key)
  on conflict (game_id, board_key) do nothing;
end $$;
revoke all on function public._p4_ensure_guardians(uuid) from public, anon, authenticated;

-- Backfill para partidas activas existentes.
do $$ declare r record; begin
  for r in select id from public.games where status='active' loop perform public._p4_ensure_guardians(r.id); end loop;
end $$;

-- ── Ledger: peaje del guardián (jugador -> banca) ─────────────────────────────────
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check check (kind in
  ('seed','bank_to_player','player_to_bank','player_to_player','host_player_transfer','host_adjust','host_revert','late_join_seed',
   'player_exit_to_bank','player_exit_distribution','player_exit_remainder_to_bank',
   'property_purchase','rent_payment','property_auction_purchase',
   'bankruptcy_cash_to_bank','bankruptcy_cash_to_player','pass_start_bonus','guardian_toll'));

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
    when 'pass_start_bonus' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'guardian_toll' then        -- peaje: jugador -> banca
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    else false
  end
);
