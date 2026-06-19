-- Fase 4 (corrección) — Orden REAL del tablero Classic (40 casillas, extraído de las fotos del tablero
-- físico). Sustituye el anillo "derivado" del Classic por el orden exacto, con casillas no-propiedad
-- (impuestos, Caja de Comunidad, Suerte, cárcel/solo visitas, parking, ve a la cárcel).
--
-- Regreso al Futuro: se MANTIENE el catálogo completo (28 propiedades) y su anillo DERIVADO como
-- PROVISIONAL (las fotos muestran propiedades — Coche de Biff, Cines Essex/Holomax — que el listado
-- físico facilitado omite; el orden definitivo de RdF se fijará en una migración posterior). No se
-- desactiva ninguna propiedad.

-- Marca de orden provisional por casilla (RdF lo es hasta confirmar su orden).
alter table public.board_spaces add column if not exists provisional boolean not null default false;

-- ── Classic: reconstruir el anillo con el orden exacto (40 casillas, índices 0..39) ──
delete from public.board_spaces where board_key = 'classic';
insert into public.board_spaces
  (space_ref, board_key, space_index, name, space_type, property_ref, is_start, sort_order, provisional) values
  ('cl-sp-00','classic', 0,'Salida',                        'start',     null,                  true, 0, false),
  ('cl-sp-01','classic', 1,'Ronda de Valencia',             'property',  'cl-ronda-valencia',   false, 1, false),
  ('cl-sp-02','classic', 2,'Caja de Comunidad',             'card',      null,                  false, 2, false),
  ('cl-sp-03','classic', 3,'Plaza Lavapiés',                'property',  'cl-plaza-lavapies',   false, 3, false),
  ('cl-sp-04','classic', 4,'Impuesto sobre el capital',     'tax',       null,                  false, 4, false),
  ('cl-sp-05','classic', 5,'Estación de Goya',              'property',  'cl-estacion-goya',    false, 5, false),
  ('cl-sp-06','classic', 6,'Glorieta Cuatro Caminos',       'property',  'cl-cuatro-caminos',   false, 6, false),
  ('cl-sp-07','classic', 7,'Suerte',                        'card',      null,                  false, 7, false),
  ('cl-sp-08','classic', 8,'Avenida Reina Victoria',        'property',  'cl-reina-victoria',   false, 8, false),
  ('cl-sp-09','classic', 9,'Calle Bravo Murillo',           'property',  'cl-bravo-murillo',    false, 9, false),
  ('cl-sp-10','classic',10,'Cárcel / Solo visitas',         'jail',      null,                  false,10, false),
  ('cl-sp-11','classic',11,'Glorieta de Bilbao',            'property',  'cl-bilbao',           false,11, false),
  ('cl-sp-12','classic',12,'Compañía de Electricidad',      'property',  'cl-cia-electricidad', false,12, false),
  ('cl-sp-13','classic',13,'Calle Alberto Aguilera',        'property',  'cl-alberto-aguilera', false,13, false),
  ('cl-sp-14','classic',14,'Calle Fuencarral',              'property',  'cl-fuencarral',       false,14, false),
  ('cl-sp-15','classic',15,'Estación de las Delicias',      'property',  'cl-estacion-delicias',false,15, false),
  ('cl-sp-16','classic',16,'Avenida Felipe II',             'property',  'cl-felipe-ii',        false,16, false),
  ('cl-sp-17','classic',17,'Caja de Comunidad',             'card',      null,                  false,17, false),
  ('cl-sp-18','classic',18,'Calle Velázquez',               'property',  'cl-velazquez',        false,18, false),
  ('cl-sp-19','classic',19,'Calle Serrano',                 'property',  'cl-serrano',          false,19, false),
  ('cl-sp-20','classic',20,'Parking gratuito',              'parking',   null,                  false,20, false),
  ('cl-sp-21','classic',21,'Avenida de América',            'property',  'cl-america',          false,21, false),
  ('cl-sp-22','classic',22,'Suerte',                        'card',      null,                  false,22, false),
  ('cl-sp-23','classic',23,'Calle María de Molina',         'property',  'cl-maria-molina',     false,23, false),
  ('cl-sp-24','classic',24,'Calle Cea Bermúdez',            'property',  'cl-cea-bermudez',     false,24, false),
  ('cl-sp-25','classic',25,'Estación del Mediodía',         'property',  'cl-estacion-mediodia',false,25, false),
  ('cl-sp-26','classic',26,'Avenida de los Reyes Católicos','property',  'cl-reyes-catolicos',  false,26, false),
  ('cl-sp-27','classic',27,'Calle Bailén',                  'property',  'cl-bailen',           false,27, false),
  ('cl-sp-28','classic',28,'Compañía de Aguas',             'property',  'cl-cia-aguas',        false,28, false),
  ('cl-sp-29','classic',29,'Plaza de España',               'property',  'cl-plaza-espana',     false,29, false),
  ('cl-sp-30','classic',30,'Ve a la cárcel',                'go_to_jail',null,                  false,30, false),
  ('cl-sp-31','classic',31,'Puerta del Sol',                'property',  'cl-puerta-sol',       false,31, false),
  ('cl-sp-32','classic',32,'Calle Alcalá',                  'property',  'cl-alcala',           false,32, false),
  ('cl-sp-33','classic',33,'Caja de Comunidad',             'card',      null,                  false,33, false),
  ('cl-sp-34','classic',34,'Gran Vía',                      'property',  'cl-gran-via',         false,34, false),
  ('cl-sp-35','classic',35,'Estación del Norte',            'property',  'cl-estacion-norte',   false,35, false),
  ('cl-sp-36','classic',36,'Suerte',                        'card',      null,                  false,36, false),
  ('cl-sp-37','classic',37,'Paseo de la Castellana',        'property',  'cl-castellana',       false,37, false),
  ('cl-sp-38','classic',38,'Impuesto de lujo',              'tax',       null,                  false,38, false),
  ('cl-sp-39','classic',39,'Paseo del Prado',               'property',  'cl-prado',            false,39, false);

-- ── Regreso al Futuro: anillo derivado actual = PROVISIONAL (orden por confirmar) ──
update public.board_spaces set provisional = true where board_key = 'back_to_the_future';

-- Salvaguarda: toda casilla 'property' del Classic debe apuntar a una propiedad real existente.
do $$
declare v_bad int;
begin
  select count(*) into v_bad from public.board_spaces s
   where s.board_key = 'classic' and s.space_type = 'property'
     and not exists (select 1 from public.property_catalog c where c.property_ref = s.property_ref);
  if v_bad > 0 then raise exception 'CLASSIC_SPACES_BROKEN: % casillas sin propiedad válida', v_bad; end if;
end $$;
