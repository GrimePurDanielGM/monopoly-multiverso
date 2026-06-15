# Estado del proyecto — lista viva

## Fase 0 — Esqueleto  (verificado en sandbox salvo lo marcado [Mac])
- [x] Monorepo pnpm + TS estricto (tsconfig.base, noUncheckedIndexedAccess, etc.)
- [x] packages/engine (motor único, puro, isomórfico) + test
- [x] packages/shared (contratos) 
- [x] apps/web: React + Vite + Tailwind + Zustand + router (dep)
- [x] PWA: manifest válido (lang es), service worker (generateSW), update controlada (prompt)
- [x] Edge Function healthcheck (Deno) importando el MISMO motor vía import map
- [x] Migración baseline (solo infra: schema meta + RPC salud) — reconstruible
- [x] Lint, typecheck, tests, build de producción: TODO en verde
- [x] verify:engine: fuente única, sin copia, ambos consumidores apuntan a ella
- [x] Seguridad: ningún secreto en el bundle; solo VITE_* públicas en cliente
- [x] CI (GitHub Actions): install→lint→typecheck→test→verify→build
- [ ] [Mac] supabase start + db reset + functions serve + curl healthcheck
- [ ] [Mac] Deno runtime ejecuta el mismo motor (no disponible en el sandbox)
- [ ] [Mac] Deploy web a Vercel (URL HTTPS)
- [ ] [Mac] Deploy Edge Function + validar empaquetado del import map
- [ ] [Mac] Instalación PWA real en iPhone (Safari) y Android (Chrome)
- [ ] [Mac] e2e Playwright (requiere navegadores instalados)

## Pendiente para fases siguientes (no en Fase 0)
- Datos reales de tableros, títulos, precios, alquileres, hipotecas, stock físico
- Esquema definitivo (games, players, propiedades, cartas, banco, etc.)
- Catálogo de cartas (transcripción de las fotos) + mazo especial de parking

## Decisiones técnicas Fase 0
- React 18.3 / Vite 5 / Tailwind 3.4 / Zustand 4: estabilidad sobre novedad
- Motor consumido como FUENTE TS (sin paso de build) por web y Deno
- PWA registerType 'prompt' para actualización controlada
- Aprobación explícita de build scripts (esbuild) por seguridad de cadena de suministro

## Alternativas si el deploy de Edge Functions no resuelve el import externo
1. (Recomendada) Mantener motor en packages/engine y usar import map — verificar deploy.
2. Reubicar la ÚNICA fuente a supabase/functions/_shared/engine y que la web la
   consuma por alias (sigue habiendo un solo archivo; NO es copia).
3. Publicar el motor como paquete versionado y consumirlo por versión en ambos lados.
   (No se elige sin tu visto bueno; nunca duplicar/copiar el archivo a mano.)
