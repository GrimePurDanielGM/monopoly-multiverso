-- Fase 6 (pulido 2) — Estructura preparada para imágenes propias de cada peón (efecto 3D, futuro).
-- ADITIVA: solo añade dos columnas NULLABLE al catálogo de fichas. No asigna ninguna imagen (no se inventan
-- imágenes todavía). El `icon` sigue siendo el identificador interno (slug); el frontend ya muestra el nombre
-- en español (`label`) y un emoji derivado del slug mientras no haya imagen.
alter table public.token_catalog
  add column if not exists image_url text,
  add column if not exists image_alt text;

comment on column public.token_catalog.image_url is 'URL de la imagen del peón (futuro, efecto 3D). NULL = usar emoji del slug.';
comment on column public.token_catalog.image_alt is 'Texto alternativo de la imagen del peón (accesibilidad). NULL = usar el nombre.';
