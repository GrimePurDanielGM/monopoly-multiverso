-- Fase 5 — Casillas especiales: MODELO (esquema + ledger + catálogo de cartas).
-- Añade impuestos (con bote de Parking), cárcel (estado por jugador), cartas (mazos por partida) y los
-- nuevos asientos de ledger. Patrones aprobados: tablas internas deny-all (solo SECURITY DEFINER), sin
-- ids internos en el snapshot, idempotencia y runtime_version intactos. No implementa casas/hoteles/
-- hipotecas/alquiler avanzado.

-- ── Discriminadores en board_spaces (hoy las especiales solo se distinguen por nombre) ──
alter table public.board_spaces add column if not exists card_deck text
  check (card_deck is null or card_deck in ('chance','community_chest','past','future'));
alter table public.board_spaces add column if not exists tax_amount int
  check (tax_amount is null or tax_amount > 0);

update public.board_spaces set card_deck='community_chest' where board_key='classic' and space_type='card' and name='Caja de Comunidad';
update public.board_spaces set card_deck='chance'          where board_key='classic' and space_type='card' and name='Suerte';
update public.board_spaces set card_deck='future'          where board_key='back_to_the_future' and space_type='card' and name='Futuro';
update public.board_spaces set card_deck='past'            where board_key='back_to_the_future' and space_type='card' and name='Pasado';
update public.board_spaces set tax_amount=200 where space_type='tax' and space_index=4;
update public.board_spaces set tax_amount=100 where space_type='tax' and space_index=38;

-- ── game_runtime: bote de Parking + estado transitorio de cartas/pagos ──
alter table public.game_runtime
  add column if not exists parking_pot bigint not null default 0 check (parking_pot >= 0 and parking_pot <= 2500),
  add column if not exists last_card_draw jsonb,      -- última carta robada (pública, para el modal/recientes)
  add column if not exists pending_card jsonb,        -- carta de resolución manual pendiente (de su dueño)
  add column if not exists pending_payment jsonb;     -- pago obligado no cubierto (impuesto) -> pagar/bancarrota

-- ── Estado de cárcel por jugador: la presencia de fila = está en la cárcel ──
create table public.game_jail (
  game_id uuid not null references public.games(id) on delete cascade,
  player_ref text not null,
  board_key text not null check (board_key in ('classic','back_to_the_future')),
  jail_turns int not null default 0,
  created_at timestamptz not null default now(),
  primary key (game_id, player_ref),
  foreign key (game_id, player_ref) references public.players(game_id, public_ref)
);
alter table public.game_jail enable row level security;   -- deny-all: solo SECURITY DEFINER
revoke all on public.game_jail from anon, authenticated;

-- ── Catálogo de cartas (global). Cartas TEMPORALES marcadas (temporary=true) hasta sustituir por reales ──
create table public.card_catalog (
  card_ref text primary key,
  deck_key text not null check (deck_key in ('chance','community_chest','past','future')),
  title text not null,
  description text not null,
  effect_type text not null check (effect_type in
    ('bank_credit','bank_debit','each_player_credit','each_player_debit','to_start','to_jail','back_steps','jail_free','manual')),
  amount int,                                   -- importe (efectos de dinero) o nº de casillas (back_steps)
  keepable boolean not null default false,      -- conservable en inventario (p. ej. salir de la cárcel)
  temporary boolean not null default false,     -- carta provisional, pendiente de carta oficial
  sort_order int not null default 0,
  active boolean not null default true
);
alter table public.card_catalog enable row level security;   -- deny-all
revoke all on public.card_catalog from anon, authenticated;

-- ── Estado del mazo por partida (orden persistente; sin azar para ser determinista y reconciliable) ──
create table public.game_card_decks (
  game_id uuid not null references public.games(id) on delete cascade,
  deck_key text not null check (deck_key in ('chance','community_chest','past','future')),
  draw_pile text[] not null default '{}',       -- card_ref por robar (frente = siguiente)
  discard_pile text[] not null default '{}',    -- card_ref descartadas
  updated_at timestamptz not null default now(),
  primary key (game_id, deck_key)
);
alter table public.game_card_decks enable row level security;   -- deny-all
revoke all on public.game_card_decks from anon, authenticated;

-- ── Cartas conservables en mano de un jugador (inventario) ──
create table public.game_held_cards (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  player_ref text not null,
  card_ref text not null references public.card_catalog(card_ref),
  acquired_at timestamptz not null default now(),
  foreign key (game_id, player_ref) references public.players(game_id, public_ref)
);
alter table public.game_held_cards enable row level security;   -- deny-all
revoke all on public.game_held_cards from anon, authenticated;
create index game_held_cards_owner_idx on public.game_held_cards(game_id, player_ref);

-- ── Semilla de cartas TEMPORALES (idéntica por mazo; cubre todos los efectos soportados + una manual) ──
do $$
declare d text; decks text[] := array['chance','community_chest','past','future'];
begin
  foreach d in array decks loop
    insert into public.card_catalog(card_ref, deck_key, title, description, effect_type, amount, keepable, temporary, sort_order) values
      (d||'-credit-200',  d, '(Temporal) Cobras de la banca',        'Carta temporal — pendiente de sustituir por carta real. Cobra 200 de la banca.', 'bank_credit', 200, false, true, 1),
      (d||'-debit-50',    d, '(Temporal) Pagas a la banca',          'Carta temporal — pendiente de sustituir por carta real. Paga 50 a la banca.',    'bank_debit',  50,  false, true, 2),
      (d||'-each-credit', d, '(Temporal) Cada jugador te paga',       'Carta temporal — pendiente de sustituir por carta real. Cada jugador te paga 20.','each_player_credit', 20, false, true, 3),
      (d||'-each-debit',  d, '(Temporal) Pagas a cada jugador',       'Carta temporal — pendiente de sustituir por carta real. Paga 20 a cada jugador.', 'each_player_debit', 20, false, true, 4),
      (d||'-to-start',    d, '(Temporal) Avanza hasta la Salida',     'Carta temporal — pendiente de sustituir por carta real. Avanza hasta la Salida (cobras el sueldo).', 'to_start', null, false, true, 5),
      (d||'-back-3',      d, '(Temporal) Retrocede 3 casillas',       'Carta temporal — pendiente de sustituir por carta real. Retrocede 3 casillas.',  'back_steps', 3, false, true, 6),
      (d||'-to-jail',     d, '(Temporal) Ve a la cárcel',             'Carta temporal — pendiente de sustituir por carta real. Ve a la cárcel sin pasar por la Salida.', 'to_jail', null, false, true, 7),
      (d||'-jail-free',   d, '(Temporal) Sal de la cárcel gratis',    'Carta temporal — pendiente de sustituir por carta real. Consérvala hasta que la necesites.', 'jail_free', null, true, true, 8),
      (d||'-manual',      d, '(Temporal) Carta de resolución manual', 'Carta temporal — pendiente de sustituir por carta real. Su efecto aún no está automatizado: resuélvela manualmente.', 'manual', null, false, true, 9);
  end loop;
end $$;

-- ── Siembra idempotente de los mazos de una partida (orden del catálogo; descarte vacío) ──
create or replace function public._p5_ensure_decks(p_game uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare d text; decks text[] := array['chance','community_chest','past','future']; v_pile text[];
begin
  foreach d in array decks loop
    if not exists (select 1 from public.game_card_decks where game_id = p_game and deck_key = d) then
      select coalesce(array_agg(card_ref order by sort_order, card_ref), '{}') into v_pile
        from public.card_catalog where deck_key = d and active;
      insert into public.game_card_decks(game_id, deck_key, draw_pile, discard_pile)
        values (p_game, d, v_pile, '{}')
        on conflict (game_id, deck_key) do nothing;
    end if;
  end loop;
end $$;
revoke all on function public._p5_ensure_decks(uuid) from public, anon, authenticated;

-- Backfill de mazos para partidas activas existentes.
do $$ declare r record; begin
  for r in select id from public.games where status='active' loop perform public._p5_ensure_decks(r.id); end loop;
end $$;

-- ── Ledger Fase 5: impuestos, bote de Parking, multa de cárcel y efectos de carta ──
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check check (kind in
  ('seed','bank_to_player','player_to_bank','player_to_player','host_player_transfer','host_adjust','host_revert','late_join_seed',
   'player_exit_to_bank','player_exit_distribution','player_exit_remainder_to_bank',
   'property_purchase','rent_payment','property_auction_purchase',
   'bankruptcy_cash_to_bank','bankruptcy_cash_to_player','pass_start_bonus','guardian_toll',
   'tax_payment','parking_pot_payout','jail_release_payment',
   'card_bank_payment','card_bank_charge','card_player_payment','card_player_charge'));

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
    when 'guardian_toll' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'tax_payment' then                 -- impuesto: jugador -> banca (alimenta el bote)
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'jail_release_payment' then        -- multa de salida de cárcel: jugador -> banca (al bote)
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'card_bank_charge' then            -- carta: jugador -> banca
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'parking_pot_payout' then          -- cobro del bote: banca -> jugador
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'card_bank_payment' then           -- carta: banca -> jugador
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'card_player_charge' then          -- carta: otro jugador -> yo
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'card_player_payment' then         -- carta: yo -> otro jugador
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    else false
  end
);
