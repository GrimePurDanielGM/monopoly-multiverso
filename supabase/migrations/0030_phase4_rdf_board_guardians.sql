-- Fase 4 (corrección 2) — Tablero Regreso al Futuro DEFINITIVO (40 casillas, orden exacto del tablero
-- físico) + base de "guardianes/centinelas" para el montaje de doble tablero.
--
-- RdF deja de ser provisional: 28 propiedades reales (incluidos Coche de Biff y Cines Essex/Holomax) en
-- su posición exacta, con impuestos (Mecánico, Dona), Futuro/Pasado (cartas), cárcel/solo-visitas, parking
-- e ir-a-la-cárcel. Corrige el precio del grupo naranja para que coincida con el tablero (Strickland 180,
-- Instituto 1985 = 200; espeja al Classic: 180→14, 200→16) y fija los nombres con su año.
--
-- Montaje de doble tablero (documentado): los dos tableros se unen por la esquina de PARKING de cada uno
-- (Parking↔Parking) y, en el lado opuesto, Ve-a-la-cárcel de uno con Solo-visitas/cárcel del otro. Aquí se
-- modela un GUARDIÁN por tablero en su esquina de Parking, que en el futuro permitirá decidir entre seguir
-- en el tablero actual o pasar al otro. La lógica de cruce automático queda para una fase posterior.

-- ── Guardianes/centinelas (modelo) ───────────────────────────────────────────────
alter table public.board_spaces add column if not exists guardian boolean not null default false;
alter table public.board_spaces add column if not exists links_to_board text null
  check (links_to_board is null or links_to_board in ('classic','back_to_the_future'));

-- ── Catálogo RdF: corrección de precios/alquiler del naranja + nombres con su año ──
update public.property_catalog set price = 180, base_rent = 14 where property_ref = 'bf-strickland';
update public.property_catalog set price = 200, base_rent = 16 where property_ref = 'bf-instituto-hv-2';
update public.property_catalog set name = 'A. Jones Transporte de Estiércol 1885' where property_ref='bf-jones-a';
update public.property_catalog set name = 'D. Jones Transporte de Estiércol 1955' where property_ref='bf-jones-d';
update public.property_catalog set name = 'Tren del Tiempo 1885'                   where property_ref='bf-tren-tiempo';
update public.property_catalog set name = 'Caballos Honest Joe Statler 1885'       where property_ref='bf-statler-caballos';
update public.property_catalog set name = 'Automóviles Statler 1955'               where property_ref='bf-statler-auto-1';
update public.property_catalog set name = 'Automóviles Statler 2015'               where property_ref='bf-statler-auto-2';
update public.property_catalog set name = 'Autocine Pohatchee 1955'                where property_ref='bf-pohatchee';
update public.property_catalog set name = 'Mr. Fusión, reactor casero'             where property_ref='bf-mr-fusion';
update public.property_catalog set name = 'Cines Essex 1985'                       where property_ref='bf-essex';
update public.property_catalog set name = 'Cines Holomax 2015'                     where property_ref='bf-holomax';
update public.property_catalog set name = 'Coche de Biff 1955'                     where property_ref='bf-coche-biff';
update public.property_catalog set name = 'Oficina del Comisario Strickland 1885'  where property_ref='bf-strickland';
update public.property_catalog set name = 'Instituto de Hill Valley 1955'          where property_ref='bf-instituto-hv-1';
update public.property_catalog set name = 'Instituto de Hill Valley 1985'          where property_ref='bf-instituto-hv-2';
update public.property_catalog set name = 'Residencia Baines 1955'                 where property_ref='bf-baines';
update public.property_catalog set name = 'Residencia McFly 1985'                  where property_ref='bf-mcfly-1';
update public.property_catalog set name = 'Residencia McFly 2015'                  where property_ref='bf-mcfly-2';
update public.property_catalog set name = 'Patinete 1985'                          where property_ref='bf-patinete';
update public.property_catalog set name = 'Palace Saloon 1885'                     where property_ref='bf-palace-saloon';
update public.property_catalog set name = 'Café de Lou 1955'                       where property_ref='bf-cafe-lou';
update public.property_catalog set name = 'Café 80''s 2015'                        where property_ref='bf-cafe-80s';
update public.property_catalog set name = 'Herrería de Doc 1885'                   where property_ref='bf-herreria-doc';
update public.property_catalog set name = 'Mansión de Doc 1955'                    where property_ref='bf-mansion-doc';
update public.property_catalog set name = 'Laboratorio de Doc 1985'                where property_ref='bf-laboratorio-doc';
update public.property_catalog set name = 'Aeropatín 2015'                         where property_ref='bf-aeropatin';
update public.property_catalog set name = 'Torre del Reloj 1885'                   where property_ref='bf-torre-reloj-1';
update public.property_catalog set name = 'Torre del Reloj 1955'                   where property_ref='bf-torre-reloj-2';

-- ── Reconstruir el anillo de RdF con el orden EXACTO (40 casillas, 0..39) ─────────
delete from public.board_spaces where board_key = 'back_to_the_future';
insert into public.board_spaces
  (space_ref, board_key, space_index, name, space_type, property_ref, is_start, sort_order, provisional) values
  ('bf-sp-00','back_to_the_future', 0,'Salida',                              'start',     null,                 true, 0, false),
  ('bf-sp-01','back_to_the_future', 1,'A. Jones Transporte de Estiércol 1885','property', 'bf-jones-a',          false, 1, false),
  ('bf-sp-02','back_to_the_future', 2,'Futuro',                              'card',      null,                 false, 2, false),
  ('bf-sp-03','back_to_the_future', 3,'D. Jones Transporte de Estiércol 1955','property', 'bf-jones-d',          false, 3, false),
  ('bf-sp-04','back_to_the_future', 4,'Mecánico',                            'tax',       null,                 false, 4, false),
  ('bf-sp-05','back_to_the_future', 5,'Tren del Tiempo 1885',                'property',  'bf-tren-tiempo',      false, 5, false),
  ('bf-sp-06','back_to_the_future', 6,'Caballos Honest Joe Statler 1885',    'property',  'bf-statler-caballos', false, 6, false),
  ('bf-sp-07','back_to_the_future', 7,'Pasado',                              'card',      null,                 false, 7, false),
  ('bf-sp-08','back_to_the_future', 8,'Automóviles Statler 1955',            'property',  'bf-statler-auto-1',   false, 8, false),
  ('bf-sp-09','back_to_the_future', 9,'Automóviles Statler 2015',            'property',  'bf-statler-auto-2',   false, 9, false),
  ('bf-sp-10','back_to_the_future',10,'Solo visitas / Cárcel',              'jail',      null,                 false,10, false),
  ('bf-sp-11','back_to_the_future',11,'Autocine Pohatchee 1955',             'property',  'bf-pohatchee',        false,11, false),
  ('bf-sp-12','back_to_the_future',12,'Mr. Fusión, reactor casero',          'property',  'bf-mr-fusion',        false,12, false),
  ('bf-sp-13','back_to_the_future',13,'Cines Essex 1985',                    'property',  'bf-essex',            false,13, false),
  ('bf-sp-14','back_to_the_future',14,'Cines Holomax 2015',                  'property',  'bf-holomax',          false,14, false),
  ('bf-sp-15','back_to_the_future',15,'Coche de Biff 1955',                  'property',  'bf-coche-biff',       false,15, false),
  ('bf-sp-16','back_to_the_future',16,'Oficina del Comisario Strickland 1885','property', 'bf-strickland',       false,16, false),
  ('bf-sp-17','back_to_the_future',17,'Futuro',                              'card',      null,                 false,17, false),
  ('bf-sp-18','back_to_the_future',18,'Instituto de Hill Valley 1955',       'property',  'bf-instituto-hv-1',   false,18, false),
  ('bf-sp-19','back_to_the_future',19,'Instituto de Hill Valley 1985',       'property',  'bf-instituto-hv-2',   false,19, false),
  ('bf-sp-20','back_to_the_future',20,'Parking gratuito',                    'parking',   null,                 false,20, false),
  ('bf-sp-21','back_to_the_future',21,'Residencia Baines 1955',              'property',  'bf-baines',           false,21, false),
  ('bf-sp-22','back_to_the_future',22,'Pasado',                              'card',      null,                 false,22, false),
  ('bf-sp-23','back_to_the_future',23,'Residencia McFly 1985',               'property',  'bf-mcfly-1',          false,23, false),
  ('bf-sp-24','back_to_the_future',24,'Residencia McFly 2015',               'property',  'bf-mcfly-2',          false,24, false),
  ('bf-sp-25','back_to_the_future',25,'Patinete 1985',                       'property',  'bf-patinete',         false,25, false),
  ('bf-sp-26','back_to_the_future',26,'Palace Saloon 1885',                  'property',  'bf-palace-saloon',    false,26, false),
  ('bf-sp-27','back_to_the_future',27,'Café de Lou 1955',                    'property',  'bf-cafe-lou',         false,27, false),
  ('bf-sp-28','back_to_the_future',28,'Condensador de Fluzo',                'property',  'bf-condensador-flujo',false,28, false),
  ('bf-sp-29','back_to_the_future',29,'Café 80''s 2015',                     'property',  'bf-cafe-80s',         false,29, false),
  ('bf-sp-30','back_to_the_future',30,'Ve a la cárcel',                      'go_to_jail',null,                 false,30, false),
  ('bf-sp-31','back_to_the_future',31,'Herrería de Doc 1885',                'property',  'bf-herreria-doc',     false,31, false),
  ('bf-sp-32','back_to_the_future',32,'Mansión de Doc 1955',                 'property',  'bf-mansion-doc',      false,32, false),
  ('bf-sp-33','back_to_the_future',33,'Futuro',                              'card',      null,                 false,33, false),
  ('bf-sp-34','back_to_the_future',34,'Laboratorio de Doc 1985',             'property',  'bf-laboratorio-doc',  false,34, false),
  ('bf-sp-35','back_to_the_future',35,'Aeropatín 2015',                      'property',  'bf-aeropatin',        false,35, false),
  ('bf-sp-36','back_to_the_future',36,'Pasado',                              'card',      null,                 false,36, false),
  ('bf-sp-37','back_to_the_future',37,'Torre del Reloj 1885',                'property',  'bf-torre-reloj-1',    false,37, false),
  ('bf-sp-38','back_to_the_future',38,'Dona al fondo de la Torre del Reloj', 'tax',       null,                 false,38, false),
  ('bf-sp-39','back_to_the_future',39,'Torre del Reloj 1955',                'property',  'bf-torre-reloj-2',    false,39, false);

-- ── Guardianes en la esquina de Parking de cada tablero (punto de montaje) ────────
update public.board_spaces set guardian = true, links_to_board = 'back_to_the_future'
  where board_key = 'classic' and space_type = 'parking';
update public.board_spaces set guardian = true, links_to_board = 'classic'
  where board_key = 'back_to_the_future' and space_type = 'parking';

-- ── Salvaguardas ─────────────────────────────────────────────────────────────────
do $$
declare v_bad int; v_n int;
begin
  select count(*) into v_n from public.board_spaces where board_key='back_to_the_future' and active;
  if v_n <> 40 then raise exception 'RDF_RING_NOT_40: %', v_n; end if;
  select count(*) into v_bad from public.board_spaces s
   where s.board_key='back_to_the_future' and s.space_type='property'
     and not exists (select 1 from public.property_catalog c where c.property_ref=s.property_ref);
  if v_bad > 0 then raise exception 'RDF_SPACES_BROKEN: %', v_bad; end if;
  -- toda propiedad RdF del catálogo debe tener su casilla (no se pierde ninguna).
  select count(*) into v_bad from public.property_catalog c
   where c.board_key='back_to_the_future' and c.active
     and not exists (select 1 from public.board_spaces s where s.property_ref=c.property_ref);
  if v_bad > 0 then raise exception 'RDF_PROPS_WITHOUT_SPACE: %', v_bad; end if;
end $$;
