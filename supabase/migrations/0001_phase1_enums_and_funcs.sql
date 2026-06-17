-- Fase 1 — Tipos y funciones base (no toca Fase 0).
create type game_status        as enum ('lobby','active','cancelled');
create type player_join_status as enum ('joined','ready');
create type request_status     as enum ('pending','approved','rejected','cancelled','expired');

-- Normalización de nombres: trim + colapsar espacios internos + minúsculas (immutable).
create or replace function public.normalize_name(input text)
returns text language sql immutable as $$
  select lower(regexp_replace(btrim(input), '\s+', ' ', 'g'))
$$;

-- Generador de identificador público opaco (no es el uuid interno ni el auth_uid).
create or replace function public.gen_public_ref()
returns text language sql volatile as $$
  select 'P-' || upper(substr(replace(gen_random_uuid()::text,'-',''), 1, 10))
$$;
