-- Fase 3 (corrección) — Catálogo REAL de propiedades extraído de las cartas de los dos tableros.
-- Sustituye el catálogo de prueba. 56 propiedades (28 Classic + 28 Regreso al Futuro).
-- Precio = 2×hipoteca, CONFIRMADO con la foto del tablero (IMG_4979): tablero estándar de Madrid; anclas
-- verificadas Estación 200, Castellana 350, Paseo del Prado 400; RdF espeja al Classic.
-- price_source='board'. Ver docs/catalog_extraction_phase3.md.

-- Tipo nuevo 'transport' (transportes de Regreso al Futuro). price_source distingue origen del precio.
alter table public.property_catalog drop constraint property_catalog_kind_check;
alter table public.property_catalog add constraint property_catalog_kind_check
  check (kind in ('street','station','transport','utility','special'));
alter table public.property_catalog add column if not exists price_source text not null default 'board'
  check (price_source in ('board','derived_from_mortgage'));
-- Utilities comprables con base_rent=0 (alquiler por dados, fuera de alcance): relajar la constraint.
alter table public.property_catalog drop constraint property_buyable_positive;
alter table public.property_catalog add constraint property_buyable_positive
  check (not is_buyable or (price > 0 and base_rent >= 0));

-- Vaciar catálogo de prueba (y posesiones que lo referencian: datos de smoke, no de usuario real).
delete from public.property_ownership;
delete from public.property_catalog;

-- ── CLASSIC (board_key=classic) ──────────────────────────────────────────────────
insert into public.property_catalog
  (property_ref, board_key, group_key, name, kind, price, base_rent, is_buyable, sort_order) values
  ('cl-ronda-valencia','classic','marron','Ronda de Valencia','street',60,2,true,10),
  ('cl-plaza-lavapies','classic','marron','Plaza Lavapiés','street',60,4,true,11),
  ('cl-cuatro-caminos','classic','celeste','Glorieta Cuatro Caminos','street',100,6,true,20),
  ('cl-reina-victoria','classic','celeste','Avenida Reina Victoria','street',100,6,true,21),
  ('cl-bravo-murillo','classic','celeste','Calle Bravo Murillo','street',120,8,true,22),
  ('cl-alberto-aguilera','classic','rosa','Calle Alberto Aguilera','street',140,10,true,30),
  ('cl-bilbao','classic','rosa','Glorieta de Bilbao','street',140,10,true,31),
  ('cl-fuencarral','classic','rosa','Calle Fuencarral','street',160,12,true,32),
  ('cl-felipe-ii','classic','naranja','Avenida Felipe II','street',180,14,true,40),
  ('cl-velazquez','classic','naranja','Calle Velázquez','street',180,14,true,41),
  ('cl-serrano','classic','naranja','Calle Serrano','street',200,16,true,42),
  ('cl-maria-molina','classic','rojo','Calle María de Molina','street',220,18,true,50),
  ('cl-america','classic','rojo','Avenida de América','street',220,18,true,51),
  ('cl-cea-bermudez','classic','rojo','Calle Cea Bermúdez','street',240,20,true,52),
  ('cl-reyes-catolicos','classic','amarillo','Avenida de los Reyes Católicos','street',260,22,true,60),
  ('cl-bailen','classic','amarillo','Calle Bailén','street',260,22,true,61),
  ('cl-plaza-espana','classic','amarillo','Plaza de España','street',280,24,true,62),
  ('cl-puerta-sol','classic','verde','Puerta del Sol','street',300,26,true,70),
  ('cl-alcala','classic','verde','Calle Alcalá','street',300,26,true,71),
  ('cl-gran-via','classic','verde','Gran Vía','street',320,28,true,72),
  ('cl-castellana','classic','azul','Paseo de la Castellana','street',350,35,true,80),
  ('cl-prado','classic','azul','Paseo del Prado','street',400,50,true,81),
  ('cl-estacion-norte','classic','estaciones','Estación del Norte','station',200,25,true,90),
  ('cl-estacion-delicias','classic','estaciones','Estación de las Delicias','station',200,25,true,91),
  ('cl-estacion-mediodia','classic','estaciones','Estación del Mediodía','station',200,25,true,92),
  ('cl-estacion-goya','classic','estaciones','Estación de Goya','station',200,25,true,93),
  ('cl-cia-aguas','classic','servicios','Compañía de Aguas','utility',150,0,true,100),
  ('cl-cia-electricidad','classic','servicios','Compañía de Electricidad','utility',150,0,true,101);

-- ── REGRESO AL FUTURO (board_key=back_to_the_future) — espeja los valores del Classic ─
insert into public.property_catalog
  (property_ref, board_key, group_key, name, kind, price, base_rent, is_buyable, sort_order) values
  ('bf-jones-a','back_to_the_future','marron','A. Jones Transporte de Estiércol','street',60,2,true,10),
  ('bf-jones-d','back_to_the_future','marron','D. Jones Transporte de Estiércol','street',60,4,true,11),
  ('bf-statler-auto-1','back_to_the_future','celeste','Automóviles Statler','street',100,6,true,20),
  ('bf-statler-caballos','back_to_the_future','celeste','Caballos Honest Joe Statler','street',100,6,true,21),
  ('bf-statler-auto-2','back_to_the_future','celeste','Automóviles Statler','street',120,8,true,22),
  ('bf-pohatchee','back_to_the_future','rosa','Autocine Pohatchee','street',140,10,true,30),
  ('bf-essex','back_to_the_future','rosa','Cines Essex','street',140,10,true,31),
  ('bf-holomax','back_to_the_future','rosa','Cines Holomax','street',160,12,true,32),
  ('bf-instituto-hv-1','back_to_the_future','naranja','Instituto de Hill Valley','street',180,14,true,40),
  ('bf-instituto-hv-2','back_to_the_future','naranja','Instituto de Hill Valley','street',180,14,true,41),
  ('bf-strickland','back_to_the_future','naranja','Oficina de Comisario Strickland','street',200,16,true,42),
  ('bf-mcfly-1','back_to_the_future','rojo','Residencia McFly','street',220,18,true,50),
  ('bf-baines','back_to_the_future','rojo','Residencia Baines','street',220,18,true,51),
  ('bf-mcfly-2','back_to_the_future','rojo','Residencia McFly','street',240,20,true,52),
  ('bf-cafe-lou','back_to_the_future','amarillo','Café de Lou','street',260,22,true,60),
  ('bf-palace-saloon','back_to_the_future','amarillo','Palace Saloon','street',260,22,true,61),
  ('bf-cafe-80s','back_to_the_future','amarillo','Café 80''s','street',280,24,true,62),
  ('bf-herreria-doc','back_to_the_future','verde','Herrería de Doc','street',300,26,true,70),
  ('bf-mansion-doc','back_to_the_future','verde','Mansión de Doc','street',300,26,true,71),
  ('bf-laboratorio-doc','back_to_the_future','verde','Laboratorio de Doc','street',320,28,true,72),
  ('bf-torre-reloj-1','back_to_the_future','azul','Torre del Reloj','street',350,35,true,80),
  ('bf-torre-reloj-2','back_to_the_future','azul','Torre del Reloj','street',400,50,true,81),
  ('bf-coche-biff','back_to_the_future','transportes','Coche de Biff','transport',200,25,true,90),
  ('bf-aeropatin','back_to_the_future','transportes','Aeropatín','transport',200,25,true,91),
  ('bf-tren-tiempo','back_to_the_future','transportes','Tren del Tiempo','transport',200,25,true,92),
  ('bf-patinete','back_to_the_future','transportes','Patinete','transport',200,25,true,93),
  ('bf-condensador-flujo','back_to_the_future','servicios','Condensador de Fluzo','utility',150,0,true,100),
  ('bf-mr-fusion','back_to_the_future','servicios','Mr. Fusión','utility',150,0,true,101);
