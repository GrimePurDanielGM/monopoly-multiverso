-- Fase 4 (pulido) — Ficha completa de propiedad: campos de la TARJETA de título.
-- Aditivo: añade alquileres por casas/hotel, coste de casa/hotel e hipoteca al catálogo, para poder
-- mostrar la tarjeta completa (solo CONSULTA; construir/hipotecar siguen sin implementarse). Datos
-- transcritos de docs/catalog_extraction_phase3.md (leídos de las cartas). No inventa: stations/
-- transports solo tienen rent_1..rent_3; utilities no tienen alquiler de mejoras (su renta es por dados).
-- price = 2 × mortgage está CONFIRMADO en el tablero para las 56 ⇒ mortgage_value = price/2.

alter table public.property_catalog
  add column if not exists rent_1 int,
  add column if not exists rent_2 int,
  add column if not exists rent_3 int,
  add column if not exists rent_4 int,
  add column if not exists rent_hotel int,
  add column if not exists house_cost int,
  add column if not exists hotel_cost int,
  add column if not exists mortgage_value int;

-- Hipoteca: invariante confirmado price = 2 × hipoteca.
update public.property_catalog set mortgage_value = price / 2 where active;

-- Estaciones/transportes: alquiler 50/100/200 (por nº poseído; acumulado aún no implementado).
update public.property_catalog
  set rent_1 = 50, rent_2 = 100, rent_3 = 200
  where active and kind in ('station', 'transport');

-- Calles: alquileres con 1/2/3/4 casas y hotel + coste de casa/hotel (idénticos casa y hotel por nivel).
update public.property_catalog c set
  rent_1 = v.r1, rent_2 = v.r2, rent_3 = v.r3, rent_4 = v.r4, rent_hotel = v.rh,
  house_cost = v.hc, hotel_cost = v.hc
from (values
  -- Classic
  ('cl-ronda-valencia',   10,  30,   90,  160,  250,  50),
  ('cl-plaza-lavapies',   20,  60,  180,  320,  450,  50),
  ('cl-cuatro-caminos',   30,  90,  270,  400,  550,  50),
  ('cl-reina-victoria',   30,  90,  270,  400,  550,  50),
  ('cl-bravo-murillo',    40, 100,  300,  450,  600,  50),
  ('cl-alberto-aguilera', 50, 150,  450,  625,  750, 100),
  ('cl-bilbao',           50, 150,  450,  625,  750, 100),
  ('cl-fuencarral',       60, 180,  500,  700,  900, 100),
  ('cl-felipe-ii',        70, 200,  550,  750,  950, 100),
  ('cl-velazquez',        70, 200,  550,  750,  950, 100),
  ('cl-serrano',          80, 220,  600,  800, 1000, 100),
  ('cl-maria-molina',     90, 250,  700,  875, 1050, 150),
  ('cl-america',          90, 250,  700,  875, 1050, 150),
  ('cl-cea-bermudez',    100, 300,  750,  925, 1100, 150),
  ('cl-reyes-catolicos', 110, 330,  800,  975, 1150, 150),
  ('cl-bailen',          110, 330,  800,  975, 1150, 150),
  ('cl-plaza-espana',    120, 360,  850, 1025, 1200, 150),
  ('cl-puerta-sol',      130, 390,  900, 1100, 1275, 200),
  ('cl-alcala',          130, 390,  900, 1100, 1275, 200),
  ('cl-gran-via',        150, 450, 1000, 1200, 1400, 200),
  ('cl-castellana',      175, 500, 1100, 1300, 1500, 200),
  ('cl-prado',           200, 600, 1400, 1700, 2000, 200),
  -- Back to the Future (espejo por nivel)
  ('bf-jones-a',          10,  30,   90,  160,  250,  50),
  ('bf-jones-d',          20,  60,  180,  320,  450,  50),
  ('bf-statler-auto-1',   30,  90,  270,  400,  550,  50),
  ('bf-statler-caballos', 30,  90,  270,  400,  550,  50),
  ('bf-statler-auto-2',   40, 100,  300,  450,  600,  50),
  ('bf-pohatchee',        50, 150,  450,  625,  750, 100),
  ('bf-essex',            50, 150,  450,  625,  750, 100),
  ('bf-holomax',          60, 180,  500,  700,  900, 100),
  ('bf-instituto-hv-1',   70, 200,  550,  750,  950, 100),
  ('bf-instituto-hv-2',   70, 200,  550,  750,  950, 100),
  ('bf-strickland',       80, 220,  600,  800, 1000, 100),
  ('bf-mcfly-1',          90, 250,  700,  875, 1050, 150),
  ('bf-baines',           90, 250,  700,  875, 1050, 150),
  ('bf-mcfly-2',         100, 300,  750,  925, 1100, 150),
  ('bf-cafe-lou',        110, 330,  800,  975, 1150, 150),
  ('bf-palace-saloon',   110, 330,  800,  975, 1150, 150),
  ('bf-cafe-80s',        120, 360,  850, 1025, 1200, 150),
  ('bf-herreria-doc',    130, 390,  900, 1100, 1275, 200),
  ('bf-mansion-doc',     130, 390,  900, 1100, 1275, 200),
  ('bf-laboratorio-doc', 150, 450, 1000, 1200, 1400, 200),
  ('bf-torre-reloj-1',   175, 500, 1100, 1300, 1500, 200),
  ('bf-torre-reloj-2',   200, 600, 1400, 1700, 2000, 200)
) as v(ref, r1, r2, r3, r4, rh, hc)
where c.property_ref = v.ref and c.active;
