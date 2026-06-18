-- Fase 2 — Banco digital: saldo materializado, ledger inmutable e idempotencia.
-- Invariante: saldo(player) = Σ amount(to_ref = player) − Σ amount(from_ref = player).
-- El banco se representa como NULL en from_ref/to_ref.

-- ── Saldo materializado por jugador (fuente operativa de la app) ──────────────────
create table public.player_balances (
  game_id    uuid   not null,
  player_ref text   not null,
  balance    bigint not null,
  updated_at timestamptz not null default now(),
  constraint player_balances_pk primary key (game_id, player_ref),
  constraint player_balances_nonneg check (balance >= 0),                 -- saldos nunca negativos
  constraint player_balances_max    check (balance <= 1000000000000),     -- límite funcional defensivo
  -- FK compuesta por public_ref (usa la constraint promovida en 0013).
  constraint player_balances_player_fk foreign key (game_id, player_ref)
    references public.players (game_id, public_ref) on delete cascade
);

-- ── Ledger inmutable (registro histórico que EXPLICA cada cambio) ─────────────────
create table public.ledger (
  id                 uuid primary key default gen_random_uuid(),   -- interno, NUNCA expuesto
  ledger_ref         text not null,                                 -- opaco público; lo genera gen_ledger_ref(game_id)
  game_id            uuid not null references public.games(id) on delete cascade,
  seq                bigint not null,
  kind               text   not null check (kind in
                       ('seed','bank_to_player','player_to_bank','player_to_player',
                        'host_player_transfer','host_adjust','host_revert')),
  from_ref           text   null,                                  -- NULL = banco (refs históricas, SIN FK)
  to_ref             text   null,                                  -- NULL = banco
  amount             bigint not null check (amount > 0 and amount <= 10000000), -- tope por operación
  before_balance     bigint null,                                  -- SOLO host_adjust
  after_balance      bigint null,
  reason             text   null,
  actor_ref          text   null,                                  -- public_ref que originó; NULL = sistema/banco
  reverts_ledger_id  uuid   null references public.ledger(id),     -- enlace de compensación
  request_id         uuid   null,                                  -- NULL solo para 'seed' (determinista)
  created_at         timestamptz not null default now(),

  -- Motivo saneado cuando existe.
  constraint ledger_reason_len check (reason is null or char_length(btrim(reason)) between 3 and 500),

  -- Estructura por tipo (no depende solo de las RPC):
  constraint ledger_shape check (
    case kind
      when 'seed' then
        from_ref is null and to_ref is not null and reverts_ledger_id is null
        and request_id is null and before_balance is null and after_balance is null
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
        and ( ((from_ref is null) <> (to_ref is null))                       -- exactamente un lado banco
           or (from_ref is not null and to_ref is not null and from_ref <> to_ref) )
      else false
    end
  )
);
create unique index ledger_game_seq_key       on public.ledger (game_id, seq);
create unique index ledger_game_ledgerref_key on public.ledger (game_id, ledger_ref);
create        index ledger_game_recent_idx    on public.ledger (game_id, seq desc);
create        index ledger_reverts_idx        on public.ledger (reverts_ledger_id) where reverts_ledger_id is not null;
-- Idempotencia económica (no-seed): unique GLOBAL por (game_id, request_id), sin depender del tipo.
create unique index ledger_game_request_key   on public.ledger (game_id, request_id) where request_id is not null;

-- Append-only (reutiliza la guard existente de Fase 1).
create trigger ledger_no_update before update or delete on public.ledger
  for each row execute function public.forbid_mutation();

-- ── Idempotencia GLOBAL de TODAS las mutaciones activas (económicas y de turno) ───
create table public.active_requests (
  game_id     uuid not null references public.games(id) on delete cascade,
  request_id  uuid not null,
  op          text not null,
  result      jsonb not null,
  created_at  timestamptz not null default now(),
  constraint active_requests_pk primary key (game_id, request_id)
);

alter table public.player_balances enable row level security;       -- sin políticas => deny-all directo
alter table public.ledger          enable row level security;
alter table public.active_requests enable row level security;
revoke all on public.player_balances, public.ledger, public.active_requests from anon, authenticated;
