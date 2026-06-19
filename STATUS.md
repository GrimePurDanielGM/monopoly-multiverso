# Estado del proyecto — lista viva

## Fase 4 — Movimiento y tablero (base) · **`Fase 4: COMPLETADA` (pendiente validación manual)**
- **Corrección ampliada 4 (2026-06-19) — cruce entre tableros (intersecciones), IMPLEMENTADO:** al alcanzar
  la esquina de **cárcel/solo-visitas con pasos restantes**, el movimiento **se DETIENE y obliga a ELEGIR**
  destino — ya no avanza solo (antes un 12 desde Salida cruzaba directo a Electricidad sin preguntar). Hay
  **dos destinos**: **seguir** en el propio tablero (Glorieta de Bilbao en Classic / Autocine Pohatchee en
  RdF) o **cruzar** al Parking gratuito del otro tablero; **uno es gratis** (la entrada que el guardián NO
  custodia) y **el otro paga peaje** (donde está el guardián). Pasar por la entrada libre **desplaza** el
  guardián a custodiarla; pasar por la custodiada **paga el peaje** (ledger `guardian_toll`) y el guardián
  se queda. La **cárcel/solo-visitas es solo de paso** (no descuenta del número); el **Parking sí cuenta**
  como casilla de aterrizaje. Modelo: tabla `game_guardians` (posición dinámica del guardián por partida,
  `own`/`cross`), `game_runtime.pending_junction` (pausa el movimiento a mitad), RPC `resolve_junction`
  (`0034`/`0035`); `move_player`/`roll_and_move`/`end_turn` rechazan acciones con cruce pendiente
  (`JUNCTION_PENDING`) y siembran guardianes. El snapshot expone `pending_junction` y `guardians` (`0036`);
  el frontend muestra el bloque de decisión con los dos destinos (gratis/peaje) y oculta tirar/mover hasta
  resolver. **Fix clave:** el parser del snapshot rechazaba el `kind` `guardian_toll` (ledger nuevo) →
  `SNAPSHOT_INVALID` tras cruzar; añadido a `LedgerKind`/`KINDS`/`kindLabel`. Suites: SQL `junction_phase4`
  (6/6: detención, `JUNCTION_PENDING`, seguir-gratis, cruzar-libre, cruzar-con-peaje, `NO_PENDING_JUNCTION`);
  unit `movement` (decisión de cruce: dos destinos, no deja tirar, `onResolveJunction`) y parser
  (`guardian_toll`); E2E `junction.spec` (cruce completo Chromium). Aplicado a dev (`0034`,`0035`,`0036`).
  **No se avanza a Fase 5.**
- **Corrección ampliada 3 (2026-06-19) — montaje en cruz + guardianes:** los dos tableros se montan
  DESPLAZADOS, haciendo coincidir esquinas opuestas (`0032`): **Cárcel/Solo-visitas del Classic ↔ Parking del
  RdF** y **Parking del Classic ↔ Cárcel/Solo-visitas del RdF** (antes Parking↔Parking; corregido). Cada
  **guardián vive en la cárcel** de su tablero y custodia DOS entradas: el Classic en su cárcel (Glorieta de
  Bilbao ó Parking del RdF) y el RdF en la suya (Autocine Pohatchee ó Parking del Classic), con **peaje 100**
  (ajustable). Columnas `links_to_index`/`guardian_toll`; el snapshot expone `spaces.links_to_index/guardian_toll`
  y `board_links` con las 4 esquinas (`0033`); la vista visual marca el guardián en la cárcel y, al tocarla,
  muestra sus dos entradas protegidas y el peaje, con la nota de montaje en cruz. **Mecánica dinámica
  (pasar gratis por la entrada libre → el guardián se desplaza a ella; pasar por la custodiada → pagas el
  peaje y se queda) queda MODELADA, VISUALIZADA y documentada**: su activación durante el juego forma parte
  del motor de cruce entre tableros (intersecciones), diferido. `board_phase4` actualizada; unit
  `BoardView` (guardián en cárcel, peaje, montaje en cruz); E2E `movement.spec`. Aplicado a dev
  (`0032`,`0033`). **No se avanza a Fase 5.**
- **Corrección ampliada 2 (2026-06-19):** **safe area iOS** en los modales a pantalla completa (`Ver tablero`
  y `Tablero de propiedades`): cabecera con `padding-top: max(.75rem, env(safe-area-inset-top))`, footer con
  `safe-area-inset-bottom` y `100dvh`; `Cerrar` y el selector de tablero ya no quedan bajo la Dynamic
  Island/notch (viewport-fit=cover ya estaba). **Tablero RdF DEFINITIVO** (`0030`): 40 casillas con el orden
  exacto del tablero físico (28 propiedades reales — incl. Coche de Biff y Cines Essex/Holomax —, Futuro/
  Pasado, Mecánico/Dona, cárcel/parking/ir-a-la-cárcel); corrige el naranja (Strickland 180, Instituto 1985
  = 200) y fija los nombres con su año; **ya no es provisional**. **Guardianes/centinelas** (`0030`/`0031`):
  columnas `guardian`/`links_to_board`; un guardián por tablero en la esquina de **Parking** que enlaza con
  el otro (montaje Parking↔Parking; la otra unión Ve-a-la-cárcel↔Solo-visitas y el cruce automático quedan
  para fase posterior). El snapshot expone `spaces.guardian/links_to_board` y `board_links`; la vista visual
  marca los guardianes (🛡️) y muestra la nota de montaje de doble tablero. **Sonido** intermedio "ti-cling"
  (tick agudo + dos campanitas con leve brillo metálico), sigue con `HTMLAudioElement`+asset+iOS. Privacidad
  de saldos, restricción de compra (turno + casilla) y corrección de posición del anfitrión mantenidas.
  Suites: `board_phase4` ampliada (RdF definitivo, naranja, guardianes); unit con safe-area y guardianes;
  E2E `movement.spec` (safe area, cambio de tablero, casilla real de RdF, montaje). Aplicado a dev
  (`0030`,`0031`). **No se avanza a Fase 5.**
- **Corrección ampliada (2026-06-19):** sonido más suave (WAV "ding-cling" senoidal); **tablero Classic con el
  orden REAL de 40 casillas** (`0028`, extraído de las fotos: salida, propiedades en su sitio, impuestos,
  Caja de Comunidad, Suerte, cárcel/solo-visitas, parking, ir-a-la-cárcel; índice 1 = Ronda de Valencia,
  30 = ir a la cárcel). **RdF se mantiene con su catálogo completo (28 props) y orden DERIVADO PROVISIONAL**
  (`provisional=true`): las fotos muestran propiedades — Coche de Biff, Cines Essex/Holomax — que el listado
  físico facilitado omitía; el orden definitivo de RdF se fijará al confirmarlo (no se desactivó nada).
  **Privacidad de saldos** (`0029`): el snapshot solo expone MI saldo; los ajenos van ocultos (ni el
  anfitrión los ve); los movimientos siguen mostrando importes; la subasta rechaza pujas sin fondos con
  error saneado. **Restricción de compra** (`0029`): `request_property_purchase` exige ser el jugador actual
  y estar EN la casilla de esa propiedad (`NOT_CURRENT_PLAYER`/`NOT_ON_PROPERTY`); pujar no exige turno.
  **Tablero visual interactivo** (`BoardView`): cuadrado con 4 lados/esquinas, fichas **por nombre de
  jugador**, tocar casilla → detalle, pestañas Clásico/RdF, usable en móvil. **Corrección de posición del
  anfitrión** trasladada al panel "Correcciones del anfitrión" (tablero+casilla+motivo). Suites nuevas
  `privacy_phase4` (4) y `purchase_restriction_phase4` (6); `board_phase4` ampliada. Aplicado a dev
  (`0028`,`0029`); E2E `movement.spec` reescrito (tablero visual, privacidad, restricción, alquiler, salida)
  y `properties.spec` adaptado a la nueva regla de compra. **No se avanza a Fase 5.**
- **Estado:** backend local + **dev remoto aplicado**, frontend, SQL Fases 1–4, integración local, E2E
  Chromium+WebKit y build verdes; desplegado en Vercel. Cierre 2026-06-19. **No se avanza a Fase 5.**
- **Alcance:** sistema base de posiciones y movimiento que conecta el núcleo económico con la posición
  real. Catálogo de casillas, posición por jugador, mover manual, tirar dados, paso por salida (cobro),
  caer en propiedad (disponible/mía/de otro/no comprable), visualización de tablero, auditoría e
  historial, sincronización multiusuario, guardianes y **cruce/intersecciones entre los dos tableros**
  (decisión en la cárcel-guardián con peaje; ver Corrección 4). **Fuera de alcance (diferido):** cartas,
  cárcel (reclusión), parking (premio), ruleta, casas, hoteles, hipotecas.
- **Modelo de tablero (`0025`):** tabla `board_spaces` (catálogo global, deny-all) **derivada del catálogo
  real** sin inventar topología: anillo por tablero = 1 casilla `start` (Salida, índice 0) + 1 casilla
  `property` por propiedad del catálogo en orden de `sort_order` (Clásico 29, RdF 29; **58 casillas**). El
  enum `space_type` admite start/property/tax/card/jail/go_to_jail/parking/special; en Fase 4 solo se
  generan start y property. **Las casillas no-propiedad (impuestos/suerte/cárcel/parking) quedan diferidas**
  hasta confirmar la topología física (evita inventar posiciones). Cada `property` apunta a un
  `property_ref` real (FK); las no comprables no tendrían `property_ref`.
- **Posiciones (`0025`):** tabla `player_positions` (deny-all, una por jugador/partida, conserva historial,
  no se borra). Siembra en la salida del tablero inicial (`classic`) en `start_game` y en `resolve_late_join`
  (misma transacción); helper idempotente `_p4_ensure_positions` + backfill de partidas ya activas. Saliente/
  expulsado/bancarrota conserva su última posición; deja de poder mover.
- **RPC (`0026`):** `move_player` (jugador actual, activo, running; 1–12; avanza en su tablero; al superar el
  final vuelve a la salida y cobra el bonus), `roll_and_move` (dos dados 1–6, mueve la suma, registra la
  tirada), `host_set_player_position` (anfitrión, motivo obligatorio; coloca la ficha **sin** cobrar salida
  ni disparar compra/alquiler). Patrón Fase 2 íntegro: idempotencia (con guard pausa/finalización) → lock
  `game_runtime FOR UPDATE` → permisos → `runtime_version` → efecto → ledger/auditoría → **1 Broadcast**.
- **Ledger/auditoría:** nuevo ledger monetario **`pass_start_bonus`** (banca→jugador, reconciliable; suena
  el efecto de "dinero recibido"); eventos de dominio `player_moved`, `passed_start`, `player_rolled`,
  `host_set_position`. El movimiento sin dinero NO crea ledger falso (solo auditoría).
- **Snapshot (`0027`):** añade `boards` (anillo + bonus), `spaces`, `positions`, `my_position`,
  `current_space`, `last_roll`, `last_move`, y `config.start_bonus` (def. 200). Saneado: sin ids internos,
  `auth_uid`, `game_id` ni tablas directas (verificado por test).
- **UI:** bloque **"Movimiento"** en la pantalla principal (turno, tablero/casilla actuales, última tirada y
  resultado, **Tirar dados**, **Mover manualmente**, avisos de turno/pausa/finalización/espectador) con
  acciones **desde el contexto de la casilla** (solicitar compra / pagar alquiler, reutilizando los flujos de
  Fase 3, sin compra directa). Vista dedicada **"Ver tablero"** (`BoardModal`, modal a pantalla completa con
  scroll propio): recorrido por tablero (Clásico/RdF), nombre/tipo/precio/propietario, **fichas** de los
  jugadores (resalta mi posición y el jugador actual) y **corrección de posición del anfitrión** (motivo
  obligatorio). Responsive móvil (acordeones, sin hover).
- **Integración:** alquiler/compra/subasta/bancarrota/abandono/expulsión/pausa/finalización/espectador y
  Broadcast como invalidación, intactos. El turno NO avanza automáticamente (se pulsa "Finalizar turno").
- **Migraciones:** `0025_phase4_board`, `0026_phase4_movement`, `0027_phase4_snapshot` (no destructivas).
- **Pruebas:** SQL Fase 4 **30** (board 6, movement 7, start_bonus 4, position_corrections 5, rls 5,
  reconcile 3); SQL Fases 1–3 sin regresión. Unit **246** (movement: matemática del anillo, selectores,
  permisos; componentes `MovementPanel`/`BoardModal`). E2E `movement.spec` (posición inicial, dados, ver
  tablero+fichas, corrección de posición, compra/alquiler por casilla, paso por salida, persistencia) en
  Chromium y WebKit; **36/36 E2E** verdes. typecheck/lint/build limpios.
- **Supabase dev:** `xazuytlseobprxqkdpjy` (monopoly-multiverso-dev) con `0025`–`0027` aplicadas (Management
  API; el pooler cuelga `db push`) e historial registrado; smoke backend OK (58 casillas, ring 29, 3 RPC).
- **Riesgos restantes (no bloqueantes):** las casillas no-propiedad (impuestos/cartas/cárcel/parking) y el
  segundo tablero por intersecciones se implementarán en fases posteriores con la topología confirmada.

## Fase 0 — Esqueleto · **COMPLETADA Y VALIDADA**
- **Estado:** `COMPLETADA`
- **Fecha de cierre:** 2026-06-15
- **Validada en:** Mac, iPhone (Safari) y Android (Chrome).

### Pruebas superadas
- [x] Monorepo pnpm operativo + TypeScript estricto.
- [x] Lint, typecheck, tests y build de producción: en verde.
- [x] PWA instalable (manifest válido, service worker, modo standalone, update controlada).
- [x] Supabase local funcionando (reconstruible desde cero con migraciones versionadas).
- [x] Migración baseline aplicada en local y en remoto (solo infraestructura: schema `meta` + RPC de salud).
- [x] Edge Function `healthcheck` operativa en local y en remoto.
- [x] Motor compartido importado desde una ÚNICA fuente por web y Edge Function (sin copia).
- [x] Realtime validado: conexión · envío/recepción · desconexión · reconexión · segundo evento tras reconexión.
- [x] Despliegue en Vercel correcto (HTTPS).

### Referencias de despliegue (rellenar con tus valores; sin secretos)
- Web (Vercel): definida por `vercel.json` (build `pnpm --filter @multiverso/web build`, salida `apps/web/dist`).
  URL de producción: _<pendiente de anotar desde el panel de Vercel>_.
- Backend/Edge (Supabase): proyecto remoto del panel de Supabase.
  Endpoint de la función: `https://<project-ref>.supabase.co/functions/v1/healthcheck`.
- (No se anotan claves ni `project-ref` reales en el repositorio.)

### Incidencias resueltas durante la fase
1. `vite.config.ts` no resolvía `node:url` → añadido `@types/node` y `types:["node"]` en el tsconfig de la web.
2. ESLint flat config no encontraba el meta-paquete → añadido `typescript-eslint`; globals de Node para `.cjs/.mjs/.js`.
3. Build PWA fallaba por `virtual:pwa-register` → añadido `workbox-window`.
4. `config.toml` incompatible con Supabase CLI 2.106.0 (`[auth.anonymous]`) → reemplazado por `enable_anonymous_sign_ins = true` dentro de `[auth]`.
5. Prueba de Realtime se quedaba colgada tras "Conectado" → el canal no recibía sus propios broadcasts; corregido con `broadcast: { self: true }` y timeout explícito por fase.
6. Vercel fallaba en `pnpm install --frozen-lockfile` (`ERR_PNPM_IGNORED_BUILDS: esbuild`) → en pnpm 11 la clave válida es `allowBuilds: { esbuild: true }` en `pnpm-workspace.yaml` (la antigua `onlyBuiltDependencies` no se aplicaba). Verificado empíricamente con pnpm 11.6.0.

### Riesgos pendientes NO bloqueantes
- iOS PWA: el websocket de Realtime muere en segundo plano; mitigado con resync/re-suscripción al volver a primer plano (a robustecer en fases con estado de partida).
- Datos del juego (tableros, precios, alquileres, hipotecas, stock físico, catálogo de cartas) aún por aportar; bloquean fases ≥4, no la Fase 1.
- Límites de plan de Supabase/Vercel en partidas largas: a vigilar, sin impacto en Fase 0/1.

## Fase 1 — Sala, jugadores y anfitrión · **`Fase 1: COMPLETADA`**
- **Backend: COMPLETADO Y VALIDADO** (detalle más abajo).
- **Frontend (lobby): COMPLETADO** (Bloques 1–6, detalle más abajo).
- **Fase 1 en conjunto: `COMPLETADA`** (cierre 2026-06-18).
  - **Implementación local y remota completada** (web en Vercel + Supabase/Edge en el proyecto dev).
  - **Validación manual COMPLETADA** en los dispositivos y navegadores disponibles: creación de
    partida, unión desde varios dispositivos/navegadores, selección de fichas, preparado/no
    preparado, sincronización Realtime, inicio simultáneo, QR, cámara y escáner, segundo plano y
    retorno, pérdida y recuperación de red, compartir código y enlace, instalación PWA, responsive,
    recuperación del anfitrión, recuperación del puesto de jugador desde varios dispositivos, y
    diálogos + acceso visible a recuperación tras las correcciones.
  - **Android: pendiente como validación adicional NO bloqueante** (no hay dispositivo Android
    disponible ahora mismo; sin fallo conocido de Android).
  - **Sin defectos bloqueantes conocidos.**
  - Último commit funcional de correcciones: `9e44699`. Último commit de estado previo al cierre: `8488a48`.

## Fase 2 — Partida activa (banco digital, turnos, correcciones) · **`Fase 2: COMPLETADA`**
- **Estado:** `COMPLETADA` (cierre 2026-06-18). Backend local + dev remoto, frontend, integración,
  E2E y despliegue: verdes. Sin defectos bloqueantes conocidos.
- **Alcance:** estado activo autoritativo; orden de turnos saneado por `public_ref`; jugador actual
  derivado; finalizar turno (manual, sin dado); banco digital (saldo entero, banco ilimitado);
  transferencias banco↔jugador (anfitrión) y jugador↔jugador; correcciones del anfitrión (ajuste de
  saldo, fijar turno, transferencia en su nombre, reversión compensatoria por `ledger_ref`), todas
  con motivo y auditadas; ledger append-only; idempotencia global; concurrencia por
  `runtime_version`; snapshot saneado; Broadcast mínimo `active_state_changed`; reanudación.
  **No incluye** propiedades, tablero, dado, cartas, cárcel, guardianes, ruleta, casas/hoteles ni tratos.
- **Migraciones:** `0013_phase2_runtime`, `0014_phase2_economy_tables`, `0015_phase2_active_rpcs`,
  `0016_phase2_start_game`. Aplicadas en LOCAL y en DEV remoto (`xazuytlseobprxqkdpjy`). El índice
  `players(game_id, public_ref)` se promovió a constraint (`players_game_pubref_uniq`) para la FK.
- **Seguridad:** RLS deny-all en `game_runtime`/`player_balances`/`ledger`/`active_requests`; acceso
  solo por RPC `SECURITY DEFINER`; helpers internos revocados; ledger inmutable (trigger); snapshot
  sin ids internos/`auth_uid`/`turn_order`(uuid)/secretos; `ledger_ref` opaco. Bundle `dist` sin
  service-role/pepper/sb_secret_; cero ids internos en cliente.
- **Pruebas:** SQL Fase 2 **43** (economy 14, turns 6, corrections 7, revert 6, idempotency 4, rls 3,
  reconcile 3) + Fase 1 **68** sin regresión. Unit/componente web **158** (incl. selectores, parser
  saneado, no-op, idempotencia cliente, componentes de turno/banco/correcciones). Integración local
  real (economía, turnos, idempotencia, versión, **Broadcast** y resync). **E2E Playwright
  Chromium + WebKit** del escenario completo de partida activa (crear→6 jugadores→iniciar→saldos→
  banca→turno→transferencia→ajuste→reversión→sincronización→recarga conserva estado).
- **Remoto dev:** snapshot activo, end_turn, banca, idempotencia, RLS y conflicto de versión
  verificados contra `xazuytlseobprxqkdpjy`; smoke multiusuario remota superada. **Nota:** la
  re-ejecución inmediata de smokes remotas de 6 jugadores queda limitada por el *rate limit* de
  *sign-in* anónimo del proyecto dev (volumen de pruebas), condición transitoria de entorno, no del producto.
- **Android físico:** pendiente como validación adicional NO bloqueante (igual que Fase 1).
- **Reanudación de jugador en partida activa (corrección 2026-06-18, `395080f`):** un jugador que
  cerraba la pestaña no podía volver a la partida activa (dead-end en `/j/{CODE}` y sin acceso visible
  a recuperar; el anfitrión tampoco veía las solicitudes durante la partida). **Backend ya lo soportaba**
  (`my_status`/`request_recovery` sin restricción de estado); corrección **solo frontend/routing**:
  - `/j/{CODE}` y `/unirse` detectan membresía y **reanudan** (lobby o activa) sin re-unirse ni elegir
    ficha; si no eres miembro y la partida está `active`, ofrecen "Recuperar mi jugador" y "Recuperar
    partida como anfitrión" (no `join_game`).
  - La pantalla `not_member` es consciente del estado; el anfitrión ve la bandeja de solicitudes
    también en la partida activa; Home añade "Recuperar mi jugador".
  - Validado: integración local real (misma sesión + recuperación en `active`: mismo `public_ref`/saldo/
    orden, sin fila nueva, sesión antigua pierde el control) y **E2E Chromium + WebKit** (`player-resume`).
    Verificado en remoto desplegado (acceso visible en `/j/{activa}` y Home). **Pendiente de validación
    manual.**
- **Recargar partida + control de la partida (corrección 2026-06-18, `eddb8fb`+`e64e0e2`):**
  - **"Recargar partida"** era un enlace sin efecto visible. Ahora es un **botón real y accesible**
    que reconecta el canal Realtime si está caído, recarga `get_active_snapshot_by_code` y sustituye
    el store, con "Recargando…", confirmación (`aria-live`) y error+reintento; evita doble pulsación;
    no recarga la página ni crea sesión nueva.
  - **Estado de ejecución `running`/`paused`/`finished`** (migración `0017`, en `game_runtime`; **no
    toca el enum histórico `games.status`**). RPC nuevas solo-anfitrión, idempotentes, con
    `runtime_version`, auditadas y Broadcast mínimo: `pause_game_runtime`, `resume_game_runtime`,
    `finish_game_runtime`. **Pausada/finalizada rechazan en servidor** las 7 mutaciones económicas/de
    turno (`GAME_PAUSED`/`GAME_FINISHED`); `finished` es **terminal** (no se reanuda), conserva ledger
    y saldos, y el snapshot sigue legible. Orden: idempotencia → estado → versión.
  - **UI:** bloque "Control de la partida" (anfitrión): running→Pausar/Finalizar, paused→Reanudar/
    Finalizar, finished→solo resumen. Pausa con confirmación; en pausa, banner "Partida en pausa" para
    todos y todas las acciones deshabilitadas. **Finalizar con confirmación fuerte** (`ConfirmDialog`
    accesible: foco inicial en "No, continuar jugando", Escape=No, clic fuera no confirma, botón
    destructivo, sin doble envío). Pantalla "Partida finalizada" persistente tras recarga.
  - Validado: SQL `control_phase2` (9), integración local real (pausa/reanudar/finalizar), unit/
    componente (diálogo de finalización: abre/No/Escape/Sí-una-vez/doble-click/foco/terminal),
    **E2E Chromium + WebKit** (`game-control`), y **smoke remota dev** (running→paused→GAME_PAUSED→
    resumed→finished→GAME_FINISHED). **Pendiente de validación manual.**
- **Incorporaciones tardías controladas (2026-06-18, `ffb4508`+`482d010`, migración `0018`):**
  durante una partida iniciada, una sesión nueva puede pedir entrar **bajo aprobación del anfitrión**.
  - **Config `allow_late_join`** (boolean, default `false`, solo configurable en lobby; en la whitelist
    de `update_config`; expuesta saneada en los snapshots). UI: toggle "Permitir que entren jugadores
    después de iniciar" con el texto explicativo.
  - **Flujo separado** de recuperación de identidad y de reentrada de expulsados. `/j/{CODE}` en activa
    para una sesión nueva: si `allow_late_join`, ofrece "Solicitar entrar como nuevo jugador" además de
    recuperar jugador/anfitrión; si no, solo recuperación.
  - **`request_late_join`/`resolve_late_join`** (solo anfitrión al aprobar; `SECURITY DEFINER`,
    idempotentes, `runtime_version`, auditadas, Broadcast). El aprobado entra en una transacción:
    jugador nuevo + saldo `initial_money` + ledger **`late_join_seed`** (tipo nuevo) + **al FINAL** de
    `turn_order_refs` **sin** tocar turno/`turn_number`/jugador actual; `runtime_version +1`; reconcilia.
    Rechazo no crea nada. En `finished` → `GAME_FINISHED`; en `paused` se puede aprobar (gestión
    administrativa) pero el nuevo no actúa hasta reanudar. Sala llena → `GAME_FULL`.
  - **UI anfitrión:** bandeja diferenciada "Solicitudes para entrar en la partida" (no se mezcla con
    recuperación/reentrada). **Solicitante:** "Solicitud pendiente de aprobación…"; al aprobar entra
    automáticamente con su identidad/saldo; al rechazar, mensaje claro.
  - Validado: SQL `latejoin_phase2` (18), integración local real, **E2E Chromium+WebKit** (`late-join`:
    off→sin entrada, on→solicitar/rechazar/reintentar/aprobar/aparece-en-todos/saldo/recarga/GAME_FULL),
    y **smoke remota dev** (config, solicitud, host la ve, aprobación, nuevo jugador al final con saldo,
    turno intacto). **Pendiente de validación manual.**
- **Salida/expulsión de jugador en partida activa (2026-06-18, migración `0019`):** un jugador puede
  **abandonar** y el anfitrión puede **sacar** a otro; se conserva la fila y el historial.
  - **Marca de salida** en `players`: `left_at` / `left_reason` / `removed_by_ref` (no se borra nada).
    El saliente **deja de ser miembro activo**: excluido en `_require_active_player`, en el snapshot
    activo (`me`) y en el de lobby (`_lobby_snapshot`) → su pantalla pasa a "ya no formas parte".
  - **Dinero (reconciliable, banco = NULL):** **a la banca** por defecto (`player_exit_to_bank`); o
    **reparto** entre restantes (solo lo autoriza el anfitrión) con división entera
    (`player_exit_distribution`) y **resto a la banca** (`player_exit_remainder_to_bank`). Tipos de
    ledger nuevos; idempotencia por `left_at` (los asientos de reparto usan request_id propio).
  - **Orden de turnos:** se quita del `turn_order_refs` preservando la invariante
    `current = turn_order_refs[turn_index]`; si el saliente no era el actual, el turno no cambia; si lo
    era, pasa al siguiente válido. `turn_number` intacto. El anfitrión **no** puede abandonar
    (`HOST_CANNOT_LEAVE`) ni ser expulsado (`CANNOT_REMOVE_HOST`) → la partida nunca queda sin control.
  - **`leave_active_game`** (solo el propio jugador, siempre a la banca) y **`remove_active_player`**
    (solo anfitrión, banca o reparto): `SECURITY DEFINER`, idempotentes, `runtime_version`, auditadas,
    `game_runtime FOR UPDATE`, un único Broadcast, sin ids internos. Permitidas en `running` y `paused`
    (gestión administrativa); en `finished` → `GAME_FINISHED`.
  - **UI:** por fila, "Abandonar partida" (mi jugador, si no soy anfitrión) y "Sacar jugador" (anfitrión,
    sobre otros; nunca sobre sí mismo ni visible a no-anfitriones). Confirmaciones obligatorias: abandono
    (`No, seguir jugando` / `Sí, abandonar partida`) y expulsión con **selector de destino del saldo**
    (Devolver a la banca = por defecto / Repartir entre restantes) (`Cancelar` / `Sí, sacar jugador`).
  - **Propiedades y cartas (Fase 3, solo documentado, NO implementado):** si un jugador abandona o es
    expulsado, sus propiedades volverán a la banca (disponibles para compra) y las cartas conservables
    al mazo/banca/estado disponible; no se repartirán entre jugadores. Subasta/reparto, si se quiere,
    será una regla nueva en su momento.
  - También se corrigió una divergencia previa del lobby: `allow_late_join` se movió al helper
    `_lobby_snapshot` para que `by_code` y `by_id` coincidan (`bycode_phase1` verde).
  - Validado: SQL `exit_phase2` (11), integración local real **y smoke remota dev** (abandono→banca,
    expulsión+reparto con resto, fuera del orden, turno, reconciliación, permisos), unit/componente
    (botones por rol y diálogos), **E2E Chromium+WebKit** (`player-exit`: expulsar→banca, abandonar,
    expulsar+repartir, persistencia tras recargar). **Pendiente de validación manual.**
- **Mínimo de jugadores configurable a 2 (2026-06-18, solo frontend — sin migración):** para facilitar
  las pruebas manuales, el anfitrión puede fijar `min_players = 2` (el **default sigue siendo 6**; el
  máximo sigue en 16). El **backend ya lo permitía** (`update_config` valida `v_min >= 2`; `start_game`
  exige `v_active >= v_min`), por lo que **no hubo cambio de backend**: solo se bajó el suelo funcional de
  la UI (`hostConfig.MIN_FLOOR` 6→2 y los `min` de los inputs del formulario). `min_players = 1` sigue
  siendo inválido (`INVALID_PLAYER_LIMITS`).
  - Validado: SQL `minplayers_phase2` (4: configurar 2, iniciar con 2, NO con 1, rechazar 1),
    unit `hostConfig`/`GameConfigForm` (permite 2, rechaza 1, atributo `min=2`), **E2E Chromium+WebKit**
    (`min-players`: la UI permite 2, no inicia con 1, sí con 2). El E2E `player-exit` se simplificó a
    anfitrión + 3 jugadores (misma cobertura). **Pendiente de validación manual.**
- **Commits:** backend Fase 2 `d6a514f`, frontend `cb9574c`, reanudación `395080f`, control backend
  `eddb8fb`, control frontend `e64e0e2`, late-join backend `ffb4508`, late-join frontend `482d010`,
  salida/expulsión `0019` `8b7fcff`, mínimo 2 jugadores `d4b495d`.

## Fase 3 — Propiedades base (catálogo, compra, alquiler, devolución) · **`Fase 3: COMPLETADA`**
Sistema base de propiedades del tablero (migración `0020`). NO incluye casas/hoteles/hipotecas/
subastas/cartas/cárcel/dado/movimiento por casillas/tablero visual (fases posteriores).
- **Catálogo (`property_catalog`, referencia global por migración; deny-all):** `property_ref` opaco,
  `board_key` (`classic` | `back_to_the_future`), `group_key`, `name`, `kind`
  (`street`/`station`/`utility`/`special`), `price`, `base_rent`, `is_buyable`, `sort_order`. Constraint:
  las comprables exigen `price>0` y `base_rent>0` (el ledger exige `amount>0`). Catálogo mínimo de
  prueba: 7 propiedades por tablero (6 comprables + 1 especial), ampliable. El cliente no puede inventar
  propiedades (FK + validación en RPC).
- **Posesión (`property_ownership`, per-game, episódica; deny-all):** `property_ref`, `owner_ref`,
  `acquired_at`, `acquired_by_ledger_ref`, `released_at`, `released_reason`. Único parcial: un solo
  propietario activo por `(game, property)`. Disponible = sin fila activa. No se borra historial.
- **`buy_property`** (jugador activo, `running`): valida existencia/comprable/libre/saldo; paga el precio
  a la banca (ledger `property_purchase`); asigna la propiedad; `runtime_version+1`; auditada; 1 Broadcast;
  idempotente. Errores: `PROPERTY_NOT_FOUND/NOT_BUYABLE/ALREADY_OWNED`, `INSUFFICIENT_FUNDS`,
  `GAME_PAUSED/FINISHED`, `VERSION_CONFLICT`.
- **`pay_rent`** (pagador activo, `running`): propietario activo, no a uno mismo (`SELF_RENT`),
  `base_rent`, sin saldo negativo (`INSUFFICIENT_FUNDS`); transferencia pagador→propietario (ledger
  `rent_payment`); idempotente. (Sin multiplicadores/grupos/casas: modelo preparado para ampliar.)
- **Devolución a banca al salir/expulsar:** integrada en `_p2_remove_player` (misma transacción): las
  propiedades activas del saliente pasan a `released_at`/`released_reason='player_exit'` y vuelven a estar
  disponibles; **sin ledger monetario** (auditoría `properties_returned_to_bank`); no se reparten ni
  subastan. Regla aprobada: *si un jugador sale o es expulsado, sus propiedades vuelven a la banca y
  quedan disponibles para compra.* (Cartas conservables: documentado para fases futuras, no implementado.)
- **Snapshot activo:** añade `properties` (catálogo activo + `owner_ref` actual, `null`=disponible),
  saneado. La UI deriva disponible/mía/de-otro, puede-comprar/puede-pagar y propiedades por jugador.
- **UI:** sección "Propiedades" por tablero (precio, alquiler, estado: Disponible / Propiedad de X / Tuya /
  No comprable) con **Comprar** (disponible) y **Pagar alquiler** (de otro); bloque "Mis propiedades";
  recuento de propiedades por jugador en la lista. Confirmaciones obligatorias (foco en Cancelar, Escape
  cancela, sin doble envío): "¿Comprar {propiedad} por {importe}?" y "¿Pagar {importe} de alquiler a
  {jugador} por {propiedad}?". En pausa/finalización: solo consulta, acciones deshabilitadas.
- **Ledger:** tipos `property_purchase` (jugador→banca) y `rent_payment` (pagador→propietario),
  reconciliables; la devolución no usa ledger monetario. Reconciliación monetaria intacta.
- **Seguridad:** RLS deny-all en `property_catalog`/`property_ownership`; solo RPC `SECURITY DEFINER`;
  helpers revocados; cliente sin SELECT directo; snapshot saneado; sin ids internos.
- Validado: SQL `properties_phase3` (13) + `rent_phase3` (7) + `property_exit_phase3` (4) +
  `reconcile_properties_phase3` (2) + `rls_properties_phase3` (6) = **32**; sin regresión en Fase 1/2
  (`rls_phase1` se encadena tras `integration_phase1`). Unit/componente (parser, selectores de compra/
  alquiler, agrupación, `PropertiesPanel`, diálogos): **+** sobre 186. Integración local real (comprar,
  alquiler, pausa bloquea, salida devuelve a banca, recompra). **E2E Chromium+WebKit** (`properties`:
  comprar→alquiler→pausa→salida-a-banca→recompra→persistencia) **34/34 suite completa**. typecheck/lint/
  build limpios; `dist` sin secretos ni ids internos. Aplicado a `monopoly-multiverso-dev`; desplegado en
  Vercel; smoke remota OK. **Pendiente de validación manual.**
- **Commit:** propiedades Fase 3 `0020` (este commit).

## Fase 3 — CORRECCIÓN AMPLIADA · **`COMPLETADA Y DESPLEGADA`** (pendiente validación manual)
Migraciones `0021`–`0024` (catálogo real, compra con aprobación+subasta, abandono con aprobación+bancarrota,
snapshot ampliado) + frontend completo. Aplicado a `monopoly-multiverso-dev` (vía Management API por el
cuelgue del pooler), desplegado en Vercel (`2e0c38c` → bundle `index-BknBW7A4.js`, UI nueva, backend dev),
**smoke remota de navegador OK** (compra con aprobación → subasta → bancarrota a jugador → espectador).
Commit `2e0c38c`, árbol limpio.
- **Feedback sonoro "dinero recibido" (solo frontend):** flash "+X recibidos" + sonido cuando **MI**
  saldo aumenta entre snapshots. NO suena en el primer snapshot, ni al bajar/no cambiar el saldo, ni por el
  saldo de otro, ni dos veces por el mismo `runtime_version`, ni para espectadores. Preferencia local
  "Sonido al recibir dinero" (default on, `localStorage`); falla en silencio. Lógica: `receiveMoney` +
  `useReceiveMoney`.
- **Audio fiable en iPhone (solo frontend):** se sustituyó Web Audio sintetizado por **`HTMLAudioElement`
  + asset WAV** (`public/sounds/cash-register.wav`, sintetizado/libre de derechos, sonido "ding-cling" de
  caja registradora más audible en móvil). **Desbloqueo robusto iOS**: en la 1ª interacción real
  (`pointerdown`/`touchend`/`click`) se reproduce el asset en silencio dentro del gesto (`primeCashSound`,
  idempotente); si el navegador rechaza `play()` no se marca desbloqueado y un nuevo gesto reintenta. El
  modo silencioso físico del iPhone puede silenciarlo (no se sortea, documentado). Tests: `cashSound`
  (desbloqueo, reproducción, fallback iOS/Safari, sin `Audio`, preferencia).
- **Rediseño de propiedades (solo frontend):** la pantalla principal solo muestra un **resumen ligero**
  (`PropertiesSummary`: "Mis propiedades" + recuento por jugador desplegable + botón **Ver tablero de
  propiedades**), sin catálogo completo ni acciones. Las acciones viven en una vista dedicada
  **Tablero de propiedades** (`PropertyBoardModal`, modal a pantalla completa con scroll propio): agrupa
  por tablero (Clásico / Regreso al futuro) y por grupo de color/tipo (acordeones `<details>`, sin depender
  de hover), tarjetas compactas con estado claro (Libre/Tuya/Ocupada/En subasta/No comprable), precio,
  alquiler y propietario; aquí se solicita compra, se puja, se ve la subasta y se paga alquiler. Flujos de
  Fase 3 intactos (aprobación del host, subastas, alquiler, bancarrota, espectador). Eliminado
  `PropertiesPanel`. Responsive móvil (grid 1→2 col, botones ≥40px, footer "Volver" sticky).
- **Validación:** typecheck/lint/build limpios; **unit 229** (43 ficheros); **E2E 34/34** en Chromium
  (`android-chrome`) + WebKit (`iphone-safari`), incluido `properties.spec` reescrito para el tablero modal.
- **Catálogo real (`0021`):** 56 propiedades extraídas de las fotos (28 Classic + 28 RdF), sustituye al de
  prueba. Tipos street/station/transport/utility. **Precio CONFIRMADO con la foto del tablero (IMG_4979):**
  `price_source='board'`, `= 2×hipoteca` (anclas verificadas Estación 200, Castellana 350, Prado 400; RdF
  espeja al Classic). Estación de Goya (hecha a mano) integrada. Utilities comprables con `base_rent=0`
  (alquiler por dados, fuera de alcance). Tabla: `docs/catalog_extraction_phase3.md`.
- **Compra SIEMPRE con aprobación (`0022`):** `request_property_purchase` (jugador) + `resolve_property_purchase`
  (anfitrión, revalida y cobra). `buy_property` directo **revocado**. **Subasta:** `start/place/close/cancel_property_auction`
  (puja > actual y ≤ saldo; cierre adjudica o sin pujas; `WINNER_INSUFFICIENT_FUNDS` deja abierta).
  Ledger `property_auction_purchase`.
- **Abandono con aprobación (`0023`):** `request_leave_active` (directo solo si sin saldo ni propiedades) +
  `resolve_leave_active` (anfitrión elige destino del dinero). `leave_active_game` directo **revocado**.
  La expulsión (`remove_active_player`) sigue siendo directa del anfitrión con destino del dinero.
- **Bancarrota (`0023`):** `request_bankruptcy` (a banca / a jugador) + `resolve_bankruptcy`. A banca:
  dinero+propiedades a banca. A jugador: dinero+propiedades **al acreedor** (transferencia de posesión,
  sin ledger monetario de propiedad). El deudor queda **espectador** (`bankrupt_at`, fuera del orden, puede
  consultar el snapshot pero no actuar). Ledger `bankruptcy_cash_to_bank/_to_player`.
- **Snapshot (`0024`):** estado de cada jugador (active/bankrupt-espectador), `me.is_spectator`, `properties`
  con `in_auction`, `auctions`, `purchase_requests`/`leave_requests`/`bankruptcy_requests` (bandejas host).
- **Frontend:** `PropertiesPanel` ("Solicitar compra", estado En subasta), `AuctionsPanel` (pujar + cerrar/
  cancelar host), bandejas del anfitrión (`PurchaseRequestsTray`/`LeaveRequestsTray`/`BankruptcyRequestsTray`),
  `BankruptcyDialog` (a banca / a jugador + acreedor + motivo), estado **espectador** (aviso + acciones
  ocultas), badges de estado en `PlayerBalances`. Tipos/parser/selectores/errores ampliados.
- **Seguridad:** todas las tablas nuevas deny-all; RPC `SECURITY DEFINER`; helpers revocados; sin ids internos.
- **Validado:** SQL `purchase_phase3` (10) + `leave_bankrupt_phase3` (4) + `properties_phase3` (7) +
  `rent_phase3` (3) + `property_exit_phase3` (3) + `rls_properties_phase3` (8) = **35**, sin regresión Fase 1/2.
  Unit/componente **206** (PropertiesPanel, AuctionsPanel, bandejas, BankruptcyDialog, pantalla). Integración
  local real (compra con aprobación, subasta, alquiler, pausa, bancarrota a jugador). **E2E Chromium+WebKit**
  (`properties`: solicitar→aprobar / subastar→pujar→cerrar / bancarrota a jugador → espectador). typecheck/
  lint/build limpios. Aplicado a dev (Management API). **Pendiente:** smoke remota navegador, Vercel, commit/push.

## Pendiente para fases siguientes (no en Fase 0/1/2/3)
- Datos reales de tableros, títulos, precios, alquileres, hipotecas, stock físico.
- Esquema definitivo de juego (propiedades, construcciones, cartas, banco, etc.).
- Catálogo de cartas (transcripción de las fotos) + mazo especial de parking.

## Decisiones técnicas Fase 0
- React 18.3 / Vite 5 / Tailwind 3.4 / Zustand 4: estabilidad sobre novedad.
- Motor consumido como FUENTE TS (sin paso de build) por web y Deno.
- PWA `registerType: 'prompt'` para actualización controlada.
- Autorización explícita de build scripts (`allowBuilds: { esbuild: true }`, pnpm 11).

## Fase 1 — Backend (sala/jugadores/anfitrión) · **COMPLETADO**
- **Estado:** `COMPLETADO`
- **Fecha de cierre:** 2026-06-17
- **Migraciones 0000–0007 aplicadas LOCAL y REMOTAMENTE** (proyecto de desarrollo).
  `0007` añade `GRANT SELECT` a `service_role` sobre `games` y `host_recovery`: la Edge
  `recover_host` las lee por PostgREST directo; `service_role` salta RLS pero igual
  necesita el grant de tabla — sin él devolvía `42501 insufficient_privilege`.
- **Pruebas SQL (Supabase local real):** Integración **14/14**. RLS **11/11**. Exit 0.
- **Edge Functions desplegadas en dev:** `create_game` y `recover_host`. Desde el arreglo CORS
  usan `verify_jwt = false` en `config.toml` (solo desactiva la verificación PREVIA de la
  plataforma, que rechazaba con 401 el preflight `OPTIONS` y bloqueaba CORS en el navegador);
  la autenticación sigue siendo OBLIGATORIA **dentro** del código (validan el JWT con Supabase
  Auth y responden `401 NOT_AUTHENTICATED` si falta/inválido). CORS por allowlist de orígenes
  (`vercel.app`, `localhost:5173`, `127.0.0.1:5173`) con reflejo dinámico + `Vary: Origin`, sin
  `*` ni credenciales de navegador. PBKDF2, pepper, service-role, RLS, RPC, bloqueo de PIN,
  auditoría y validación de fichas: intactos.
- **PBKDF2:** **600.000 iteraciones** (PBKDF2-HMAC-SHA256 con pepper de Edge; tiempo constante).
- **Benchmark remoto del Edge desplegado (Deno WebCrypto, 25 muestras):**
  **p50 90,8 ms · p95 91,0 ms · p99 91,3 ms** → holgadamente bajo el umbral orientativo de 300 ms.
- **Pruebas remotas (dev) en verde:** `create_game`; `recover_host` con código inexistente
  (`GAME_NOT_FOUND`), PIN incorrecto (`INVALID_PIN`), PIN correcto (`ok:true`) y normalización
  (espacios y minúsculas → `ok:true`).
- **Commit:** `d11d524` ("Completar backend de sala de Fase 1") en `main`.
- **Riesgos pendientes NO bloqueantes:**
  - iOS PWA: el websocket de Realtime muere en segundo plano; mitigar con resync/re-suscripción
    al volver a primer plano (clave para la sala sincronizada del frontend de Fase 1).
  - Quedan ~32 partidas de prueba desechables en la BD dev (validación remota); limpieza
    pendiente de confirmación (borrado condicionado por el guard append-only de `audit_events`).
  - Límites de plan de Supabase/Vercel en partidas largas: a vigilar.
  - Datos del juego (tableros, precios, cartas, etc.) aún por aportar; bloquean fases ≥4, no Fase 1.
- (Sin secretos: no se anotan `HOST_PIN_PEPPER`, service-role key, JWT ni `project-ref`.)

## Fase 1 — Frontend (lobby) · **COMPLETADO** (validación manual parcial — 2026-06-18)
- **Estado:** `COMPLETADO` en código y pruebas automáticas. **Validación en dispositivos: PENDIENTE.**
- **Fecha de cierre de implementación:** 2026-06-17
- **Bloques entregados:**
  - **B1** Inicio · crear (con ficha obligatoria + PIN) · unirse por código/enlace `/j/:code`.
  - **B2** Sala sincronizada: snapshot autoritativo (`get_lobby_snapshot_by_code`), fichas, "preparado".
  - **B3** Realtime privado (`room:{CODE}`), Presence (solo `public_ref`), heartbeat y reconexión.
  - **B4** Controles del anfitrión: expulsión (por `public_ref`), configuración, cancelación, inicio
    (concurrencia optimista `p_expected_version`).
  - **B5** Recuperación de jugador, reentrada tras expulsión y recuperación de anfitrión (PIN).
  - **B6** Compartir (código/enlace/QR) · escáner QR · responsive · accesibilidad · PWA · E2E final.
- **Bloque 6 — detalle:**
  - **Compartir:** código de 6 caracteres, enlace `{VITE_PUBLIC_BASE_URL}/j/{CODE}`, **QR generado en local**
    (`qrcode`, sin servicio externo), `Copiar código`, `Copiar enlace`, `Compartir` (Web Share API con
    *fallback* a portapapeles). El QR/compartir **solo** llevan el enlace público: nunca JWT, PIN, IDs internos.
  - **Escáner QR:** acción explícita antes de pedir cámara · `BarcodeDetector` con *fallback* `@zxing/browser`
    · validación de dominio permitido y código · normalización (trim+mayúsculas) · **liberación de cámara**
    en detección/cancelar/cerrar/desmontar/segundo plano · *fallback* manual permanente (código o enlace).
  - **Responsive:** móvil 320–360 px sin scroll horizontal, *safe-area*, objetivos táctiles ≥44 px,
    `font-size:16px` en inputs (sin zoom iOS); lobby a dos columnas en tablet/escritorio.
  - **Accesibilidad:** foco visible (`:focus-visible`), `role="alert"`/`aria-live` para conexión/estado/copias/
    errores, diálogos con foco inicial + *focus-trap* + Escape + retorno de foco, alt del QR,
    `prefers-reduced-motion`.
  - **PWA:** banners discretos de instalación y de actualización (`useRegisterSW`); **no** se promete offline
    completo (aviso de "sin conexión" + reintento al volver).
- **Pruebas automáticas (en verde):**
  - Unitarias + componente (web): **127 pasan, 11 omitidas** (las omitidas son integración con red, ver abajo).
  - Motor: **15/15**. `verify:engine`: misma fuente única (checksum reproducible).
  - Integración local real (gated `SB_URL`/`SB_ANON`): **11/11** (host, realtime, recuperación).
  - **E2E Playwright multiusuario (Supabase local real)** sobre **iPhone 13 (Safari/WebKit)** y
    **Pixel 7 (Chrome/Chromium)**, **4/4 por dispositivo (8 en total)**:
    escenario principal (anfitrión crea, comparte, **5 se unen en contextos independientes**, todos eligen
    ficha distinta y marcan preparado → **6/6**, el anfitrión inicia → **todos ven "La partida ha comenzado"**),
    código inexistente, unión por enlace `/j/:code`, y aviso offline sin pantalla en blanco.
  - `typecheck` y `lint`: limpios. `build`: correcto.
- **Seguridad verificada (guards automáticos):**
  - **Bundle de producción (`apps/web/dist`) sin secretos:** 0 coincidencias de
    `SUPABASE_SERVICE_ROLE_KEY`, `HOST_PIN_PEPPER`, `sb_secret_`, `service_role` ni del JWT de service-role.
    (La clave **anon** sí está, por diseño: es pública y RLS protege el estado.)
  - Test de fuente `no-secrets-source`: el código cliente no contiene esos secretos.
  - Tests existentes que siguen pasando: sin IDs internos en el snapshot (`no-internal-id`),
    sin *broadcast* emitido desde el cliente (`no-broadcast-emit`), Presence solo con `public_ref`.
  - El PIN nunca sale del estado local del formulario (no a store, localStorage, logs ni URL).
- **Riesgos / límites conocidos (NO bloqueantes):**
  - **Cámara/QR real**: el escáner se prueba en unidad (mock de `@zxing/browser` y `getUserMedia`) — el flujo
    con cámara física **solo se puede validar a mano** (entra en la checklist).
  - iOS PWA: el websocket de Realtime muere en segundo plano; mitigado con resync al volver a primer plano.
  - Build con aviso de *chunk* > 500 kB (un único bundle); no afecta a la funcionalidad. Optimización futura.
  - Las pruebas de integración Realtime son sensibles al arranque del contenedor tras `db reset`
    (si fallan por 0 eventos, reintentar con Realtime ya "healthy"; no es un defecto del producto).

### Checklist de validación manual en dispositivos reales (PARCIALMENTE VALIDADO — 2026-06-18)
> Requisito: nada de esto se marca como validado sin pruebas físicas. iPhone (Safari), Android (Chrome) y Mac.

**Validado manualmente** (varios dispositivos/navegadores; todos los clientes transicionaron a
`active` y muestran "La partida ha comenzado" — placeholder previsto de fin de Fase 1, no un error):
- [x] **Flujo principal multiusuario** (2026-06-18): creación, unión multidispositivo, sincronización
      del lobby, selección de fichas, estado "preparado", inicio por el anfitrión y transición
      sincronizada de todos los clientes a `active`.
- [x] **Pérdida y recuperación de red** (2026-06-18).
- [x] **Compartir** código, enlace y menú nativo (2026-06-18).
- [x] **Instalación y apertura como PWA** (2026-06-18).
- [x] **Responsive** en ventana estrecha y ancha (2026-06-18).
- [x] **QR y cámara** (validados con anterioridad).
- [x] **Segundo plano y reconexión** (validados con anterioridad).

**Defectos detectados el 2026-06-18 y CORREGIDOS (pendiente de revalidación manual por el responsable):**
- [~] **Accesibilidad de diálogos CORREGIDA y validada automáticamente en Chromium/WebKit.** En Safari
      el `Tab` no recorría los controles: se distinguió el ajuste de macOS "Full Keyboard Access"
      (comportamiento del navegador, no de la app) del *focus-trap* de los diálogos. Corregido con un
      hook común (`useDialogA11y`) que gestiona el `Tab` por completo (no depende del orden de tabulación
      nativo, válido en WebKit), foco inicial, Escape, retorno de foco al disparador (vía teclado) y
      botón visible Cerrar/Cancelar en todos los diálogos (`ConfirmDialog` — expulsión/cancelación/inicio
      —, QR ampliado y escáner QR). Sin forzar `tabIndex` en controles nativos. **Validado con Playwright
      en Chromium y WebKit, en local y contra el despliegue remoto** (6/6 por entorno). **Pendiente de
      revalidación manual por el responsable.**
- [~] **Acceso visible a la recuperación del anfitrión CORREGIDO.** La pantalla inicial añade
      "Recuperar partida como anfitrión" → `/recuperar`, con texto que pide código + PIN, no sugiere
      crear partida nueva ni confundir con recuperar un jugador. **Recuperación funcional validada en
      `lobby` y en `active`** (el backend lo permite — `host_recovery_success` sin restricción de estado;
      no se cambió la regla): el nuevo dispositivo queda `is_host = true` y el anterior pierde el rol
      (`NOT_ACTIVE_MEMBER`). **Validado con Playwright (Chromium+WebKit) e integración, en local y en
      remoto** (lobby por navegador; active por integración remota). **Pendiente de revalidación manual
      por el responsable.**

**Pendiente de validación manual** (NO validado todavía):
- [ ] **Escanear QR** con cámara física en condiciones límite: cámara denegada / sin cámara / QR de otra app.
- [ ] **Accesibilidad por teclado en dispositivo real** tras la corrección (revalidación del responsable).
- [ ] **Recuperación de anfitrión por la nueva acción visible en dispositivo real** (revalidación del responsable).
- [ ] **Android + botón Atrás**: PENDIENTE por falta de dispositivo Android (no es fallo ni validado).
- [ ] **Recuperación de jugador** en otro dispositivo y reentrada tras expulsión (en dispositivo real).
- (Sin secretos: no se anotan `HOST_PIN_PEPPER`, service-role key, JWT ni `project-ref`.)
