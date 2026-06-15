# Monopoly: El Multiverso — Esqueleto (Fase 0)

PWA (React + Vite + TS estricto) + Supabase (Postgres, Realtime, Edge Functions),
monorepo con **un único motor de reglas** compartido por web y servidor.
**Fase 0 = solo andamiaje.** Sin reglas de juego, sin tablas de partida.

## Requisitos en tu Mac
- Node 20+ y **pnpm** (`corepack enable && corepack prepare pnpm@latest --activate`)
- **Docker Desktop** (para Supabase local)
- **Supabase CLI**: `brew install supabase/tap/supabase`
- (E2E) navegadores Playwright: `pnpm exec playwright install`

## Instalación
```bash
pnpm install
cp .env.example .env        # rellena los valores (ver más abajo)
```

## Comandos
```bash
pnpm dev            # servidor de desarrollo de la web (http://localhost:5173)
pnpm build          # typecheck + build de producción + PWA
pnpm preview        # sirve el build (http://localhost:4173)
pnpm lint           # ESLint
pnpm typecheck      # tsc --noEmit en todos los paquetes
pnpm test           # tests unit/componente (Vitest)
pnpm verify:engine  # evidencia: web y Edge usan el MISMO motor (sin copia)
pnpm e2e            # Playwright (requiere navegadores instalados + pnpm preview)
```

## Variables de entorno
Cliente (públicas, prefijo VITE_): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`.
Servidor (SECRETAS, nunca en el navegador ni con prefijo VITE_):
`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, `HOST_PIN_PEPPER`.
En producción los secretos del servidor se cargan con `supabase secrets set ...`.

## Supabase local (entorno de pruebas reproducible desde cero)
```bash
supabase start                 # levanta Postgres+Realtime+Studio en Docker
supabase db reset              # aplica migrations/ desde cero (incluye seed)
supabase functions serve healthcheck --no-verify-jwt
curl http://localhost:54321/functions/v1/healthcheck
```
`supabase start` imprime la `API URL` y la `anon key` para tu `.env` local.
**No uses el proyecto de producción como entorno de pruebas.**

## Despliegue
- **Web → Vercel**: importar el repo. Vercel lee `vercel.json`
  (build `pnpm --filter @multiverso/web build`, salida `apps/web/dist`).
  Configurar en Vercel `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.
- **Backend/Edge → Supabase**:
  `supabase functions deploy healthcheck` y `supabase db push` (migraciones).

## Probar instalación PWA en móvil real (necesita HTTPS = URL de Vercel)
- **iPhone (Safari)**: abrir la URL → Compartir → *Añadir a pantalla de inicio* →
  abrir el icono → debe arrancar en modo app (standalone).
- **Android (Chrome)**: abrir la URL → menú → *Instalar app / Añadir a pantalla* →
  abrir → modo app.
- Offline: con la app abierta, activar modo avión y recargar → la **pantalla básica
  sigue disponible** (no se exige juego offline en Fase 0).
- Actualización: al desplegar una versión nueva, la app **pregunta** antes de recargar.

## Motor compartido — riesgo de despliegue a verificar (IMPORTANTE)
El motor vive **una sola vez** en `packages/engine/src/index.ts`. Lo consumen:
- Web: alias de Vite + `paths` de tsconfig.
- Edge (Deno): `supabase/functions/import_map.json` (alias `@multiverso/engine`).
`pnpm verify:engine` confirma fuente única, sin copia, referenciada por ambos.
**Pendiente de validar en tu Mac:** que `supabase functions deploy healthcheck`
empaquete correctamente el import que sale de `supabase/functions/`. Si fallara,
ver alternativas en `STATUS.md` (sin duplicar el motor).
