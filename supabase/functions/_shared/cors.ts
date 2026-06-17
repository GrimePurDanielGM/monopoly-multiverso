// CORS compartido para Edge Functions autenticadas por bearer token.
//
// Diseño: allowlist de orígenes con respuesta DINÁMICA + `Vary: Origin`.
//   - Solo se emite `Access-Control-Allow-Origin` si el Origin está en la allowlist
//     (se refleja el origen exacto, nunca `*`). Un origen no autorizado recibe la
//     respuesta SIN esa cabecera => el navegador la bloquea.
//   - No se usan cookies ni credenciales del navegador (la auth viaja en el header
//     `Authorization: Bearer <JWT>`), por eso NO se emite `Access-Control-Allow-Credentials`.
//   - Las peticiones sin `Origin` (curl, servidor a servidor) no son del navegador:
//     no necesitan cabeceras CORS y se sirven igual (la auth in-function sigue siendo obligatoria).
//
// La validación del JWT NO ocurre aquí: cada función debe exigir y validar el
// `Authorization` con Supabase Auth (verify_jwt=false solo desactiva la verificación
// previa de la plataforma, no convierte la función en pública).

const ALLOWED_ORIGINS = new Set<string>([
  'https://monopoly-multiverso-web.vercel.app',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
]);

const ALLOW_HEADERS = 'authorization, x-client-info, apikey, content-type';
const ALLOW_METHODS = 'POST, OPTIONS';

/** Cabeceras CORS para un Origin dado. Refleja el origen solo si está permitido. */
export function corsHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    'Access-Control-Allow-Headers': ALLOW_HEADERS,
    'Access-Control-Allow-Methods': ALLOW_METHODS,
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return headers;
}

/** Respuesta al preflight `OPTIONS` (antes de cualquier otra lógica). */
export function preflight(origin: string | null): Response {
  return new Response('ok', { status: 200, headers: corsHeaders(origin) });
}

/** Respuesta JSON con cabeceras CORS (también en errores). */
export function jsonCors(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...corsHeaders(origin) },
  });
}

/** true si el origen está explícitamente permitido (para tests/depuración). */
export function isAllowedOrigin(origin: string | null): boolean {
  return !!origin && ALLOWED_ORIGINS.has(origin);
}
