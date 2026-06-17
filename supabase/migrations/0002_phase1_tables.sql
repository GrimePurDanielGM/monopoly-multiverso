-- Fase 1 — Tablas, índices, ciclo de FK y append-only.

create table public.token_catalog (
  id text primary key,
  label text not null,
  icon text not null,
  catalog_version int not null default 0,
  provisional boolean not null default true,
  active boolean not null default true,
  sort_order int not null default 0
);

-- games SIN la FK a players todavía (rompe el ciclo en el DDL).
create table public.games (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  status game_status not null default 'lobby',
  host_player_id uuid,
  config jsonb not null default '{}'::jsonb,
  turn_order uuid[] null,
  version int not null default 0,
  audit_seq bigint not null default 0,
  create_request_id uuid not null,
  created_at timestamptz not null default now(),
  started_at timestamptz null,
  cancelled_at timestamptz null,
  constraint games_code_len check (char_length(code) = 6),
  constraint games_name_len check (char_length(name) between 3 and 40),
  constraint games_active_iff_started check ((status = 'active') = (started_at is not null))
);
create unique index games_code_key           on public.games (code);
create unique index games_create_request_key on public.games (create_request_id);

create table public.players (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  public_ref text not null default public.gen_public_ref(),
  auth_uid uuid null,                 -- nullable; se CONSERVA en filas expulsadas (server-only)
  display_name text not null,
  display_name_norm text generated always as (public.normalize_name(display_name)) stored,
  token_id text references public.token_catalog(id),
  join_status player_join_status not null default 'joined',
  kicked_at timestamptz null,
  last_seen_at timestamptz not null default now(),
  row_version int not null default 0,
  created_at timestamptz not null default now(),
  constraint players_name_len check (char_length(btrim(display_name)) between 2 and 24)
);
-- Únicos PARCIALES: solo jugadores activos (no expulsados).
create unique index players_game_auth_active_key  on public.players (game_id, auth_uid)
  where auth_uid is not null and kicked_at is null;
create unique index players_game_name_active_key  on public.players (game_id, display_name_norm)
  where kicked_at is null;
create unique index players_game_token_active_key on public.players (game_id, token_id)
  where token_id is not null and kicked_at is null;
create unique index players_game_pubref_key       on public.players (game_id, public_ref);
create index        players_game_idx              on public.players (game_id);
create index        players_kicked_lookup_idx     on public.players (game_id, auth_uid) where kicked_at is not null;

-- Cierre del ciclo de FK.
alter table public.games
  add constraint games_host_fk foreign key (host_player_id)
  references public.players(id) on delete set null;

create table public.host_recovery (
  game_id uuid primary key references public.games(id) on delete cascade,
  pin_hash text not null,
  pin_salt text not null,
  algo text not null,
  iterations int not null,
  failed_attempts int not null default 0,
  locked_until timestamptz null,
  updated_at timestamptz not null default now()
);

-- Solicitudes de RECUPERACIÓN de identidad (reclamar fila activa existente). Sin uid.
create table public.player_recovery_requests (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null default public.gen_public_ref(),
  game_id uuid not null references public.games(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  device_label text null,
  status request_status not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz null
);
create unique index pending_recovery_per_player
  on public.player_recovery_requests (player_id) where status = 'pending';

-- Solicitudes de REENTRADA (sesión expulsada -> fila NUEVA). Sin uid.
create table public.player_reentry_requests (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null default public.gen_public_ref(),
  game_id uuid not null references public.games(id) on delete cascade,
  prior_player_id uuid not null references public.players(id) on delete cascade,
  desired_name text not null,
  device_label text null,
  status request_status not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  new_player_id uuid null references public.players(id) on delete set null
);

-- Secretos de solicitud: el auth_uid del solicitante NUNCA es legible por clientes.
create table public.request_secrets (
  request_id uuid primary key,
  requester_auth_uid uuid not null,
  created_at timestamptz not null default now()
);

-- Auditoría append-only (server-only; sin política de lectura para clientes).
create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  seq bigint not null,
  type text not null,
  actor_auth_uid uuid null,
  actor_player_id uuid null references public.players(id) on delete set null,
  affected_player_ids uuid[] not null default '{}',
  before jsonb null,
  after jsonb null,
  reason text null,
  automatic boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index audit_seq_per_game on public.audit_events (game_id, seq);

create or replace function public.forbid_mutation() returns trigger language plpgsql as $$
begin raise exception 'audit_events es append-only'; end $$;
create trigger audit_no_update before update or delete on public.audit_events
  for each row execute function public.forbid_mutation();
