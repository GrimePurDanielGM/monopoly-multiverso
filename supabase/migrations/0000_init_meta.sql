-- Fase 0 — Baseline de infraestructura. NO contiene tablas de juego
-- (ni partidas, ni jugadores, ni tableros, ni cartas, ni banco).
-- Reconstruible desde cero con `supabase db reset`.

create schema if not exists meta;

create table if not exists meta.app_meta (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

insert into meta.app_meta (key, value) values ('phase', '0')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- RPC trivial de salud para validar conectividad cliente/servidor en Fase 0.
create or replace function public.fase0_healthcheck()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'ok', true,
    'server_time', now(),
    'phase', (select value from meta.app_meta where key = 'phase')
  );
$$;
