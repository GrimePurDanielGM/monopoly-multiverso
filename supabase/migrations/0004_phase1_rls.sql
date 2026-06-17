-- Fase 1 — RLS, helper de pertenencia y grants.

-- Pertenencia ACTIVA (jamás considera miembro a una fila kicked).
create or replace function public.is_game_member(p_game uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.players p
    where p.game_id = p_game and p.auth_uid = auth.uid() and p.kicked_at is null
  )
$$;

alter table public.games                    enable row level security;
alter table public.players                  enable row level security;
alter table public.token_catalog            enable row level security;
alter table public.audit_events             enable row level security;
alter table public.host_recovery            enable row level security;
alter table public.player_recovery_requests enable row level security;
alter table public.player_reentry_requests  enable row level security;
alter table public.request_secrets          enable row level security;

-- Lectura solo a miembros activos. NINGUNA política de escritura (todo vía RPC/Edge).
create policy games_select   on public.games   for select using (public.is_game_member(id));
-- players: solo filas ACTIVAS (las expulsadas quedan server-only y no exponen auth_uid).
create policy players_select on public.players for select using (public.is_game_member(game_id) and kicked_at is null);
-- token_catalog: lectura pública (referencia).
create policy tokens_select  on public.token_catalog for select using (true);
-- solicitudes: visibles a miembros (host). No contienen uid.
create policy recovery_select on public.player_recovery_requests for select using (public.is_game_member(game_id));
create policy reentry_select  on public.player_reentry_requests  for select using (public.is_game_member(game_id));

-- audit_events, host_recovery, request_secrets: SIN políticas => deny-all a clientes.

-- Grants: ninguna escritura directa de cliente; solo SELECT donde hay política.
revoke all on all tables in schema public from anon, authenticated;
grant select on public.games, public.players, public.token_catalog,
                public.player_recovery_requests, public.player_reentry_requests
  to authenticated;
grant select on public.token_catalog to anon;
