# Tests de Fase 1 (backend) — Supabase local real

Los tests simulan la identidad como Supabase: estableciendo `request.jwt.claims`
(que es lo que lee `auth.uid()`). **Cada escenario ejecuta las RPC como el rol
`authenticated`** (igual que en producción vía la Edge/SDK). No usan shim ni
redefinen funciones de producción.

## Helpers (definidos como funciones `pg_temp`, efímeras de sesión)
- `_as_user(uid)`: fija `request.jwt.claims` (+ `request.jwt.claim.sub`/`.role` por
  compatibilidad), hace `SET LOCAL ROLE authenticated` y **verifica `auth.uid()`**
  (aborta si es NULL o distinto del esperado).
- `_as_admin()`: vuelve al rol privilegiado de la sesión para lecturas/aserciones del
  test (evita que RLS oculte filas durante la verificación).
- `_rec(name, ok)`: registra `PASS`/`FAIL`.

Patrón por bloque: lookup privilegiado → `_as_user(uid)` → RPC(s) como authenticated →
`_as_admin()` → aserción → `_rec`. Todo dentro de la misma transacción (`SET LOCAL`).

## Preflight
Antes de nada, un bloque fija un JWT de prueba y exige que `auth.uid()` devuelva ese
UUID. Si el mecanismo no funciona en ese Supabase, **aborta de inmediato** con mensaje
claro (en vez de 14 errores `NOT_AUTHENTICATED`).

## Deny-all
`host_recovery`, `audit_events`, `request_secrets` se comprueban con subbloque
`BEGIN … EXCEPTION WHEN insufficient_privilege … END` (revierte solo la subtransacción,
no aborta la batería). El error esperado produce `PASS`.

## Exit code
Gate final: `RAISE EXCEPTION` si hay cualquier `FAIL` ⇒ `psql` sale ≠ 0. Si todo pasa:
`RESULTADO: TODOS PASAN` y código 0.

## Orden (requiere `supabase db reset` previo)
```bash
supabase db reset
DB="$(supabase status -o json | jq -r .DB_URL)"
psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/integration_phase1.sql   # crea G1/G2
psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/rls_phase1.sql           # usa esos datos
echo "exit: $?"
```
`integration_phase1.sql` no es reejecutable sin `db reset` (estado determinista).

## Unitarios (motor, puro)
```bash
pnpm -C packages/engine test:run
```
