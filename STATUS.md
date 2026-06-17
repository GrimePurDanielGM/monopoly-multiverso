# Estado del proyecto — lista viva

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

## Fase 1 — Sala, jugadores y anfitrión
- **Backend: COMPLETADO Y VALIDADO** (detalle más abajo).
- **Frontend (lobby): COMPLETADO** (Bloques 1–6, detalle más abajo).
- **Fase 1 en conjunto: `PENDIENTE ÚNICAMENTE DE VALIDACIÓN MANUAL EN DISPOSITIVOS REALES`**
  (iPhone/Safari, Android/Chrome y Mac). Código, pruebas automáticas (unitarias, de
  componente, de integración local real y E2E multiusuario) y build: en verde. **No se
  declara validada en dispositivos hasta que el responsable complete la checklist manual
  de más abajo.**

## Pendiente para fases siguientes (no en Fase 0/1)
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

## Fase 1 — Frontend (lobby) · **COMPLETADO** (pendiente de validación manual)
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

### Checklist de validación manual en dispositivos reales (PENDIENTE — la rellena el responsable)
> Requisito: nada de esto se marca como validado sin pruebas físicas. iPhone (Safari), Android (Chrome) y Mac.
- [ ] **Crear partida** en cada dispositivo: nombre, ficha, PIN de 6 dígitos → entra a la sala.
- [ ] **Compartir**: copiar código, copiar enlace, botón Compartir (hoja nativa) en iOS y Android.
- [ ] **QR**: se ve con buen contraste/margen; ampliarlo; alt presente para lector de pantalla.
- [ ] **Escanear QR** con cámara física (iPhone y Android): permiso explícito, lectura, normalización,
      y **la luz/indicador de cámara se apaga** al detectar/cancelar/cerrar/cambiar de app.
- [ ] **Cámara denegada / sin cámara / QR de otra app**: mensajes claros y *fallback* manual operativo.
- [ ] **Unión multiusuario real** (6–16 personas o varios navegadores): todos aparecen, presencia en vivo,
      todos "preparados", el anfitrión inicia y **todos** ven "La partida ha comenzado".
- [ ] **Responsive**: 320–360 px sin scroll horizontal; objetivos táctiles cómodos; sin zoom al enfocar inputs (iOS);
      dos columnas en iPad/Mac.
- [ ] **Accesibilidad**: navegación con teclado, foco visible, diálogos atrapan el foco y cierran con Escape;
      `prefers-reduced-motion` desactiva animaciones.
- [ ] **PWA**: instalar en iOS y Android; abrir en *standalone*; recibir aviso de actualización; abrir enlace
      `/j/{CODE}` directo desde fuera de la app.
- [ ] **Conexión**: cortar red → aviso discreto; recuperar → reconexión y resync sin pantalla en blanco.
- [ ] **Recuperación**: jugador en otro dispositivo; anfitrión con PIN; reentrada tras expulsión.
- (Sin secretos: no se anotan `HOST_PIN_PEPPER`, service-role key, JWT ni `project-ref`.)
