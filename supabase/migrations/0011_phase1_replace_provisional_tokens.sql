-- Fase 1 — Sustitución de 7 fichas provisionales no disponibles físicamente por 7 nuevas.
-- ADITIVA: NO borra filas (integridad histórica y FK de partidas existentes). Solo desactiva
-- las 7 antiguas e inserta las 7 nuevas, en la MISMA catalog_version (0). Idempotente.
-- No edita 0003 ni ninguna migración aplicada. No toca fichas ya asignadas a jugadores.

-- 1) Desactivar las 7 antiguas (ids reales del seed 0003: Bolt/Radioactive/Book/Train/Guitarrilla/Battery/Ship).
update public.token_catalog
   set active = false
 where id in ('flux_capacitor', 'plutonium_case', 'sports_almanac', 'time_train', 'guitar', 'mr_fusion', 'battleship');

-- 2) Insertar las 7 nuevas (activas, provisionales, versión 0, sort_order coherente 21–27).
--    on conflict: re-activa y actualiza (idempotente ante reejecución controlada).
insert into public.token_catalog (id, label, icon, catalog_version, provisional, active, sort_order) values
  ('penguin',        'Pingüino',       'penguin',        0, true, true, 21),
  ('t_rex',          'T-Rex',          't-rex',          0, true, true, 22),
  ('rider',          'Jinete',         'rider',          0, true, true, 23),
  ('spinning_wheel', 'Rueca',          'spinning-wheel', 0, true, true, 24),
  ('iron',           'Plancha',        'iron',           0, true, true, 25),
  ('peter_mayday',   'Peter & Mayday', 'peter-mayday',   0, true, true, 26),
  ('babypool',       'Babypool',       'babypool',       0, true, true, 27)
on conflict (id) do update
  set label = excluded.label,
      icon = excluded.icon,
      active = true,
      provisional = true,
      catalog_version = excluded.catalog_version,
      sort_order = excluded.sort_order;

-- Resultado esperado: 20 fichas activas en v0 (13 antiguas conservadas + 7 nuevas), >= 16.
