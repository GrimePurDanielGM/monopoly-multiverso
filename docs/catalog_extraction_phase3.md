# Catálogo real de propiedades — extracción revisable (Fase 3, corrección)

Extraído de las fotos de las cartas (título de propiedad) de los dos tableros.
Las cartas muestran **alquileres, coste de casa/hotel e hipoteca**, pero **no el precio de compra**
(va impreso en el **tablero**). El precio `= 2 × mortgage_value` quedó **CONFIRMADO con la foto del
tablero** (`IMG_4979.HEIC`): es el tablero estándar de Madrid; verificadas las anclas
**Estación del Norte 200**, **Paseo de la Castellana 350**, **Paseo del Prado 400** (todas = 2×hipoteca),
y el tablero de Regreso al Futuro espeja al Classic. Por tanto `price_source = "board"` para las 56.
Confianza global: **alta** (alquileres/hipotecas leídos de las cartas; precios confirmados en el tablero).

Tipos: `street` (calles), `station` (estaciones Classic), `transport` (transportes RdF),
`utility` (compañías Classic + Condensador de Fluzo + Mr. Fusión), `special` (no comprables; aquí ninguna
carta de propiedad es special — las casillas especiales no tienen carta de título).

Notas de modelo (decisiones para Fase 3):
- **Estaciones/transportes**: `base_rent = 25` (alquiler con 1). El multiplicador por nº poseído
  (25/50/100/200) NO se implementa aún (aprobado: sin "estaciones acumuladas"); `pay_rent` cobra el base.
- **Utilities**: el alquiler es por dados (4×/10×). Sin dado en esta fase ⇒ `base_rent = 0` y `pay_rent`
  no aplica a utilities todavía (se compran, su alquiler por dados queda para fase futura). Se relaja
  `property_buyable_positive` a `price > 0 and base_rent >= 0`.
- `rent_1..rent_4`, `rent_hotel`, `house_cost`, `hotel_cost` se guardan para fases futuras (casas/hoteles
  NO se implementan ahora). En BtF los alquileres con mejoras espejan el grupo equivalente del Classic.

Leyenda confianza: `high` (leído directo / invariante estándar), `med` (inferido del grupo equivalente),
`low` = NEEDS_REVIEW.

## CLASSIC (board_key = classic) — 28 propiedades

| property_ref | group_key | name | kind | price | base_rent | rent_1 | rent_2 | rent_3 | rent_4 | rent_hotel | house_cost | hotel_cost | mortgage | confidence | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cl-ronda-valencia | marron | Ronda de Valencia | street | 60 | 2 | 10 | 30 | 90 | 160 | 250 | 50 | 50 | 30 | high | |
| cl-plaza-lavapies | marron | Plaza Lavapiés | street | 60 | 4 | 20 | 60 | 180 | 320 | 450 | 50 | 50 | 30 | high | rent_4 leído ~300; estándar 320 (no afecta a Fase 3) |
| cl-cuatro-caminos | celeste | Glorieta Cuatro Caminos | street | 100 | 6 | 30 | 90 | 270 | 400 | 550 | 50 | 50 | 50 | high | |
| cl-reina-victoria | celeste | Avenida Reina Victoria | street | 100 | 6 | 30 | 90 | 270 | 400 | 550 | 50 | 50 | 50 | high | |
| cl-bravo-murillo | celeste | Calle Bravo Murillo | street | 120 | 8 | 40 | 100 | 300 | 450 | 600 | 50 | 50 | 60 | high | |
| cl-alberto-aguilera | rosa | Calle Alberto Aguilera | street | 140 | 10 | 50 | 150 | 450 | 625 | 750 | 100 | 100 | 70 | high | |
| cl-bilbao | rosa | Glorieta de Bilbao | street | 140 | 10 | 50 | 150 | 450 | 625 | 750 | 100 | 100 | 70 | high | |
| cl-fuencarral | rosa | Calle Fuencarral | street | 160 | 12 | 60 | 180 | 500 | 700 | 900 | 100 | 100 | 80 | high | |
| cl-felipe-ii | naranja | Avenida Felipe II | street | 180 | 14 | 70 | 200 | 550 | 750 | 950 | 100 | 100 | 90 | high | |
| cl-velazquez | naranja | Calle Velázquez | street | 180 | 14 | 70 | 200 | 550 | 750 | 950 | 100 | 100 | 90 | high | |
| cl-serrano | naranja | Calle Serrano | street | 200 | 16 | 80 | 220 | 600 | 800 | 1000 | 100 | 100 | 100 | high | |
| cl-maria-molina | rojo | Calle María de Molina | street | 220 | 18 | 90 | 250 | 700 | 875 | 1050 | 150 | 150 | 110 | high | |
| cl-america | rojo | Avenida de América | street | 220 | 18 | 90 | 250 | 700 | 875 | 1050 | 150 | 150 | 110 | high | |
| cl-cea-bermudez | rojo | Calle Cea Bermúdez | street | 240 | 20 | 100 | 300 | 750 | 925 | 1100 | 150 | 150 | 120 | high | hipoteca cortada en foto; estándar 120 |
| cl-reyes-catolicos | amarillo | Avenida de los Reyes Católicos | street | 260 | 22 | 110 | 330 | 800 | 975 | 1150 | 150 | 150 | 130 | high | |
| cl-bailen | amarillo | Calle Bailén | street | 260 | 22 | 110 | 330 | 800 | 975 | 1150 | 150 | 150 | 130 | high | |
| cl-plaza-espana | amarillo | Plaza de España | street | 280 | 24 | 120 | 360 | 850 | 1025 | 1200 | 150 | 150 | 140 | high | |
| cl-puerta-sol | verde | Puerta del Sol | street | 300 | 26 | 130 | 390 | 900 | 1100 | 1275 | 200 | 200 | 150 | high | |
| cl-alcala | verde | Calle Alcalá | street | 300 | 26 | 130 | 390 | 900 | 1100 | 1275 | 200 | 200 | 150 | high | |
| cl-gran-via | verde | Gran Vía | street | 320 | 28 | 150 | 450 | 1000 | 1200 | 1400 | 200 | 200 | 160 | high | |
| cl-castellana | azul | Paseo de la Castellana | street | 350 | 35 | 175 | 500 | 1100 | 1300 | 1500 | 200 | 200 | 175 | high | |
| cl-prado | azul | Paseo del Prado | street | 400 | 50 | 200 | 600 | 1400 | 1700 | 2000 | 200 | 200 | 200 | high | la más cara |
| cl-estacion-norte | estaciones | Estación del Norte | station | 200 | 25 | 50 | 100 | 200 | | | | | 100 | high | rent por nº de estaciones (no acumulado aún) |
| cl-estacion-delicias | estaciones | Estación de las Delicias | station | 200 | 25 | 50 | 100 | 200 | | | | | 100 | high | |
| cl-estacion-mediodia | estaciones | Estación del Mediodía | station | 200 | 25 | 50 | 100 | 200 | | | | | 100 | high | |
| cl-estacion-goya | estaciones | Estación de Goya | station | 200 | 25 | 50 | 100 | 200 | | | | | 100 | high | **CARTA HECHA A MANO** (perdida); normalizada como "Estación de Goya"; valores confirmados por el usuario |
| cl-cia-aguas | servicios | Compañía de Aguas | utility | 150 | 0 | | | | | | | | 75 | high | alquiler por dados (4×/10×): diferido a fase con dado |
| cl-cia-electricidad | servicios | Compañía de Electricidad | utility | 150 | 0 | | | | | | | | 75 | high | hipoteca cortada en foto; estándar 75; alquiler por dados diferido |

## BACK TO THE FUTURE (board_key = back_to_the_future) — 28 propiedades
Mismos valores económicos que el Classic (espejo por grupo); temática "kornas de plutonio" en vez de casas.

| property_ref | group_key | name | kind | price | base_rent | rent_1 | rent_2 | rent_3 | rent_4 | rent_hotel | house_cost | hotel_cost | mortgage | confidence | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bf-jones-a | marron | A. Jones Transporte de Estiércol | street | 60 | 2 | 10 | 30 | 90 | 160 | 250 | 50 | 50 | 30 | high | base leído; mejoras espejo Classic |
| bf-jones-d | marron | D. Jones Transporte de Estiércol | street | 60 | 4 | 20 | 60 | 180 | 320 | 450 | 50 | 50 | 30 | high | base leído |
| bf-statler-auto-1 | celeste | Automóviles Statler | street | 100 | 6 | 30 | 90 | 270 | 400 | 550 | 50 | 50 | 50 | med | dos cartas "Automóviles Statler" (base 6 y 8); asignación 1ª/3ª NEEDS_REVIEW |
| bf-statler-caballos | celeste | Caballos Honest Joe Statler | street | 100 | 6 | 30 | 90 | 270 | 400 | 550 | 50 | 50 | 50 | high | |
| bf-statler-auto-2 | celeste | Automóviles Statler | street | 120 | 8 | 40 | 100 | 300 | 450 | 600 | 50 | 50 | 60 | med | la "Automóviles Statler" de base 8 |
| bf-pohatchee | rosa | Autocine Pohatchee | street | 140 | 10 | 50 | 150 | 450 | 625 | 750 | 100 | 100 | 70 | high | |
| bf-essex | rosa | Cines Essex | street | 140 | 10 | 50 | 150 | 450 | 625 | 750 | 100 | 100 | 70 | high | |
| bf-holomax | rosa | Cines Holomax | street | 160 | 12 | 60 | 180 | 500 | 700 | 900 | 100 | 100 | 80 | high | |
| bf-instituto-hv-1 | naranja | Instituto de Hill Valley | street | 180 | 14 | 70 | 200 | 550 | 750 | 950 | 100 | 100 | 90 | med | dos cartas "Instituto de Hill Valley" (ambas base 14) |
| bf-instituto-hv-2 | naranja | Instituto de Hill Valley | street | 180 | 14 | 70 | 200 | 550 | 750 | 950 | 100 | 100 | 90 | med | |
| bf-strickland | naranja | Oficina de Comisario Strickland | street | 200 | 16 | 80 | 220 | 600 | 800 | 1000 | 100 | 100 | 100 | high | |
| bf-mcfly-1 | rojo | Residencia McFly | street | 220 | 18 | 90 | 250 | 700 | 875 | 1050 | 150 | 150 | 110 | med | dos cartas "Residencia McFly" (base 18 y 20) |
| bf-baines | rojo | Residencia Baines | street | 220 | 18 | 90 | 250 | 700 | 875 | 1050 | 150 | 150 | 110 | high | |
| bf-mcfly-2 | rojo | Residencia McFly | street | 240 | 20 | 100 | 300 | 750 | 925 | 1100 | 150 | 150 | 120 | med | la "Residencia McFly" de base 20 |
| bf-cafe-lou | amarillo | Café de Lou | street | 260 | 22 | 110 | 330 | 800 | 975 | 1150 | 150 | 150 | 130 | high | |
| bf-palace-saloon | amarillo | Palace Saloon | street | 260 | 22 | 110 | 330 | 800 | 975 | 1150 | 150 | 150 | 130 | high | |
| bf-cafe-80s | amarillo | Café 80's | street | 280 | 24 | 120 | 360 | 850 | 1025 | 1200 | 150 | 150 | 140 | high | |
| bf-herreria-doc | verde | Herrería de Doc | street | 300 | 26 | 130 | 390 | 900 | 1100 | 1275 | 200 | 200 | 150 | high | |
| bf-mansion-doc | verde | Mansión de Doc | street | 300 | 26 | 130 | 390 | 900 | 1100 | 1275 | 200 | 200 | 150 | high | |
| bf-laboratorio-doc | verde | Laboratorio de Doc | street | 320 | 28 | 150 | 450 | 1000 | 1200 | 1400 | 200 | 200 | 160 | high | |
| bf-torre-reloj-1 | azul | Torre del Reloj | street | 350 | 35 | 175 | 500 | 1100 | 1300 | 1500 | 200 | 200 | 175 | med | dos cartas "Torre del Reloj" (base 35 y 50) |
| bf-torre-reloj-2 | azul | Torre del Reloj | street | 400 | 50 | 200 | 600 | 1400 | 1700 | 2000 | 200 | 200 | 200 | med | la "Torre del Reloj" de base 50 |
| bf-coche-biff | transportes | Coche de Biff | transport | 200 | 25 | 50 | 100 | 200 | | | | | 100 | high | rent por nº de transportes (no acumulado aún) |
| bf-aeropatin | transportes | Aeropatín | transport | 200 | 25 | 50 | 100 | 200 | | | | | 100 | high | |
| bf-tren-tiempo | transportes | Tren del Tiempo | transport | 200 | 25 | 50 | 100 | 200 | | | | | 100 | high | |
| bf-patinete | transportes | Patinete | transport | 200 | 25 | 50 | 100 | 200 | | | | | 100 | high | |
| bf-condensador-flujo | servicios | Condensador de Fluzo | utility | 150 | 0 | | | | | | | | 75 | high | alquiler por dados; diferido a fase con dado |
| bf-mr-fusion | servicios | Mr. Fusión | utility | 150 | 0 | | | | | | | | 75 | high | |

## Resumen
- 56 propiedades comprables (28 + 28). 0 inventadas.
- 44 calles, 4 estaciones, 4 transportes, 4 utilities.
- Estación de Goya (hecha a mano) integrada como estación válida.
- `price` derivado de `2 × mortgage` (las cartas no muestran precio de compra).
- Nombres duplicados (Automóviles Statler ×2, Instituto de Hill Valley ×2, Residencia McFly ×2,
  Torre del Reloj ×2) desambiguados con sufijo en `property_ref`.
