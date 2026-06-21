# Reglas implementadas

Resumen funcional de lo que la app hace cumplir (host-assisted: la app valida y registra; el
anfitrión arbitra lo que no se puede automatizar con seguridad). Por fases.

## Fase 1 — Sala y acceso
- Crear partida con código; unirse por código; recuperación de anfitrión y de jugador.
- Lobby: elegir ficha (peón), listo/no listo, configuración de la sala.
- PWA instalable; reconexión.

## Fase 2 — Partida activa, banco y turnos
- Saldos privados (cada jugador ve solo el suyo; los demás se ocultan).
- Banco: ingresos/pagos, transferencias entre jugadores, registro en el ledger.
- Turnos por orden; pausar / reanudar / finalizar partida.
- Incorporación tardía (con aprobación), salida y expulsión.

## Fase 3 — Propiedades
- Compra de propiedades; subastas; alquiler básico.
- Bancarrota (frente a banca o a un acreedor) y devolución/transferencia de propiedades.

## Fase 4 — Tablero y movimiento
- Tablero visual; movimiento por dados; doble tablero (Classic + Regreso al Futuro) con cruce.
- Guardianes en los cruces (peaje/decisión de ruta).
- Historial local de partidas en el dispositivo.

## Fase 5 — Casillas especiales
- Cárcel: entrar, 3 turnos, intento por turno, dobles, pagar fianza, carta «sal de la cárcel».
- Impuestos; bote de Aparcamiento Gratuito (Parking).
- Dados virtuales o físicos (configurable: solo virtual / permitir físico / solo físico).
- Servicios (alquiler por dados, combinado) y estaciones (alquiler acumulativo).
- Guardia anti-doble-cobro de alquiler en la misma caída (rent-once).
- Cartas: 4 mazos con robo/descarte, efectos automáticos y resolución manual de las ambiguas.

## Fase 6 — Construcción, hipotecas y alquiler avanzado
- Casas y hoteles con stock configurable (mín. 32 casas / 12 hoteles); construcción uniforme.
- Opción «construir sin el grupo completo» (configurable por el anfitrión).
- Hipotecar / deshipotecar (coste de deshipoteca = hipoteca × 1,1).
- Alquiler avanzado: base, doble por monopolio, por nº de casas y por hotel; hipotecada no cobra.
- Solicitudes de construcción con aprobación del anfitrión; UI de tarjeta de propiedad por tipo.

## Fase 7 — Tratos entre jugadores
- Trato entre dos jugadores: dinero, propiedades, cartas conservables y un acuerdo personal
  (texto libre, **sin** ejecución automática — se cumple a mano, con aviso).
- Confirmación bilateral + aprobación del anfitrión cuando hay propiedades, cartas o acuerdo
  (solo dinero ⇒ no necesita anfitrión). Contraofertas. Ejecución **atómica** (todo o nada).
- La vista del trato es **relativa a cada jugador** («Tú entregas / Tú recibes»); el anfitrión no
  participante lo ve neutral.
- Propiedades **hipotecadas** se transfieren hipotecadas (el receptor no cobra alquiler hasta
  deshipotecar). Propiedades **con construcciones**: solo si el anfitrión activa
  «Permitir tratos con propiedades construidas»; entonces se transfieren con sus casas/hotel
  (no vuelven al banco, el stock no cambia).
- Revalidación al ejecutar: si el estado cambió (p. ej. la propiedad dejó de pertenecer), el trato
  se marca «inválido» y no ejecuta nada.

## Fase 8 — Cartas
- Modelo de carta completo + infraestructura de importación de cartas reales (ver
  [`datos-pendientes.md`](datos-pendientes.md)). Las cartas actuales son temporales hasta importar
  los textos oficiales.

## Privacidad y seguridad (transversal)
- Tablas deny-all; toda mutación pasa por RPC `SECURITY DEFINER` con validación.
- El snapshot está saneado: sin ids internos ni identidades; nunca expone saldos ajenos.
- Idempotencia por `request_id`, control de versión optimista y operaciones atómicas.

Limitaciones conocidas: ver [`manual-de-uso.md`](manual-de-uso.md) §Limitaciones.
