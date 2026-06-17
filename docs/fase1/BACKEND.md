# Fase 1 — Backend (sala, jugadores, anfitrión)

Backend autoritativo. El cliente solo propone; el servidor valida economía, reglas,
pertenencia, permisos y RNG. Sin UI de lobby todavía y sin Fase 2.

## Migraciones (orden)
1. `0000_init_meta.sql` — Fase 0 (no se toca).
2. `0001_phase1_enums_and_funcs.sql` — enums, `normalize_name`, `gen_public_ref`.
3. `0002_phase1_tables.sql` — tablas, índices parciales, ciclo de FK, auditoría append-only.
4. `0003_phase1_tokens_seed.sql` — 20 fichas provisionales (catalog_version 0).
5. `0004_phase1_rls.sql` — `is_game_member`, RLS y grants.
6. `0005_phase1_rpcs.sql` — RPC autoritativas + grants por función.
7. `0006_phase1_host_recovery_rpcs.sql` — RPC de recuperación de host (solo `service_role`).

## Modelo de jugador expulsado (decisión aprobada)
- Se **conserva** `auth_uid` en la fila histórica + `kicked_at`; la fila **no** se borra.
- Índices únicos de sesión/nombre/ficha solo sobre activos (`where kicked_at is null`).
- Las filas expulsadas **no son legibles por clientes** (RLS solo activos).
- Ninguna RPC trata como miembro a una fila con `kicked_at is not null`.
- La sesión expulsada pierde capacidad inmediata (no coincide con ningún activo).

## Recuperación vs. Reentrada (flujos separados)
- **Recuperación**: reclamar fila ACTIVA existente → `request_recovery`/`resolve_recovery` → reasigna `auth_uid`.
- **Reentrada**: sesión expulsada → `request_reentry`/`resolve_reentry` → crea fila NUEVA (nunca reactiva la histórica).
- El `auth_uid` del solicitante vive en `request_secrets` (deny-all); jamás se expone.
- Conflicto comprobado en ambos: una sesión no puede controlar dos jugadores activos.

## Seguridad PIN del host
PBKDF2-HMAC-SHA256, 600.000 iteraciones (fijas), salt por partida, **pepper** solo en Edge.
Defensa: pepper + 5 intentos + bloqueo 15 min + rate-limit + auditoría. Comparación en tiempo constante.

## Secretos de Edge
- `HOST_PIN_PEPPER` (nuevo, obligatorio).
- `SUPABASE_SERVICE_ROLE_KEY` (lo usa `recover_host`; ya existe en el proyecto).
