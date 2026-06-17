// Integración HTTP contra las funciones (local o remoto).
//
// LOCAL (no estricto): el runtime local intercepta OPTIONS y fuerza
//   `Access-Control-Allow-Origin: *` en todas las respuestas, por lo que aquí
//   solo se valida la AUTENTICACIÓN y que verify_jwt=false surte efecto (el POST
//   sin JWT llega al código y responde 401). El allowlist exacto NO es observable.
//   Vars: EDGE_BASE, SB_URL, SB_ANON.
//
// REMOTO/ESTRICTO (STRICT_CORS=1): contra el despliegue real, donde mandan MIS
//   cabeceras (origen reflejado, sin `*`, preflight servido por mi handler).
//   Vars: EDGE_BASE (remoto), SB_URL/SB_ANON (remoto), STRICT_CORS=1.
//
//   deno test --allow-net --allow-env supabase/functions/tests/cors_auth.http.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createClient } from 'npm:@supabase/supabase-js@2';

const EDGE = Deno.env.get('EDGE_BASE');
const SB_URL = Deno.env.get('SB_URL');
const SB_ANON = Deno.env.get('SB_ANON');
const STRICT = Deno.env.get('STRICT_CORS') === '1';
const enabled = Boolean(EDGE && SB_URL && SB_ANON);

const VERCEL = 'https://monopoly-multiverso-web.vercel.app';
const SECRET_RE = /service_role|sb_secret_|HOST_PIN_PEPPER|pepper|pin_hash|pin_salt|eyJhbGciOiJ/i;

function allowOriginOk(value: string | null, expected: string) {
  if (STRICT) assertEquals(value, expected, 'origen reflejado exacto');
  else assert(value === expected || value === '*', `Allow-Origin presente (fue ${value})`);
}

async function anonJwt(): Promise<string> {
  const c = createClient(SB_URL!, SB_ANON!, { auth: { persistSession: false, autoRefreshToken: false } });
  await c.auth.signInAnonymously();
  const { data } = await c.auth.getSession();
  const t = data.session?.access_token;
  if (!t) throw new Error('no se obtuvo JWT anónimo');
  return t;
}

const body = (fn: string) =>
  fn === 'create_game'
    ? { name: 'CORS test', host_name: 'Host', host_token: 'delorean', config: {}, request_id: crypto.randomUUID(), pin: '246813' }
    : { code: 'ZZZZZZ', pin: '000000' };

for (const fn of ['create_game', 'recover_host']) {
  // 1) OPTIONS sin JWT -> 2xx con CORS
  Deno.test({ name: `[${fn}] OPTIONS sin JWT -> 2xx con CORS`, ignore: !enabled }, async () => {
    const r = await fetch(`${EDGE}/${fn}`, {
      method: 'OPTIONS',
      headers: { Origin: VERCEL, 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'authorization, content-type, apikey' },
    });
    await r.body?.cancel();
    assert(r.status === 200 || r.status === 204, `status ${r.status}`);
    allowOriginOk(r.headers.get('access-control-allow-origin'), VERCEL);
    assert((r.headers.get('access-control-allow-methods') ?? '').toUpperCase().includes('POST'));
    if (STRICT) assert((r.headers.get('access-control-allow-headers') ?? '').toLowerCase().includes('authorization'));
  });

  // 3) POST sin JWT -> 401 NOT_AUTHENTICATED (+ CORS en error, + sin secretos)
  Deno.test({ name: `[${fn}] POST sin JWT -> 401 NOT_AUTHENTICATED con CORS`, ignore: !enabled }, async () => {
    const r = await fetch(`${EDGE}/${fn}`, {
      method: 'POST',
      headers: { Origin: VERCEL, 'content-type': 'application/json' },
      body: JSON.stringify(body(fn)),
    });
    const text = await r.text();
    assertEquals(r.status, 401);
    assertEquals(JSON.parse(text).error, 'NOT_AUTHENTICATED');
    allowOriginOk(r.headers.get('access-control-allow-origin'), VERCEL);
    assert(!SECRET_RE.test(text), 'sin secretos en el cuerpo');
  });

  // 4) POST con JWT inválido -> 401
  Deno.test({ name: `[${fn}] POST con JWT inválido -> 401`, ignore: !enabled }, async () => {
    const r = await fetch(`${EDGE}/${fn}`, {
      method: 'POST',
      headers: { Origin: VERCEL, 'content-type': 'application/json', Authorization: 'Bearer not-a-real-jwt' },
      body: JSON.stringify(body(fn)),
    });
    const text = await r.text();
    assertEquals(r.status, 401);
    assert(!SECRET_RE.test(text), 'sin secretos en el cuerpo');
  });

  // 5) POST con JWT válido sigue funcionando (pasa la auth; no 401)
  Deno.test({ name: `[${fn}] POST con JWT válido pasa la auth`, ignore: !enabled }, async () => {
    const jwt = await anonJwt();
    const r = await fetch(`${EDGE}/${fn}`, {
      method: 'POST',
      headers: { Origin: VERCEL, 'content-type': 'application/json', Authorization: `Bearer ${jwt}` },
      body: JSON.stringify(body(fn)),
    });
    const text = await r.text();
    assert(r.status !== 401, `no debería ser 401, fue ${r.status}: ${text}`);
    if (fn === 'create_game') assert(JSON.parse(text).code, 'create_game devuelve code');
    else assertEquals(JSON.parse(text).error, 'GAME_NOT_FOUND'); // auth OK, code inexistente
    allowOriginOk(r.headers.get('access-control-allow-origin'), VERCEL);
    assert(!SECRET_RE.test(text), 'sin secretos en el cuerpo');
  });

  // 6+7) Orígenes permitidos reflejados (solo verificable de forma estricta en remoto).
  Deno.test({ name: `[${fn}] orígenes permitidos reflejados (estricto)`, ignore: !enabled || !STRICT }, async () => {
    for (const o of [VERCEL, 'http://localhost:5173', 'http://127.0.0.1:5173']) {
      const r = await fetch(`${EDGE}/${fn}`, { method: 'OPTIONS', headers: { Origin: o, 'Access-Control-Request-Method': 'POST' } });
      await r.body?.cancel();
      assertEquals(r.headers.get('access-control-allow-origin'), o);
    }
  });

  // 8) Origen no autorizado -> sin Allow-Origin (solo estricto/remoto)
  Deno.test({ name: `[${fn}] origen no autorizado sin Allow-Origin (estricto)`, ignore: !enabled || !STRICT }, async () => {
    const r = await fetch(`${EDGE}/${fn}`, { method: 'OPTIONS', headers: { Origin: 'https://evil.example.com', 'Access-Control-Request-Method': 'POST' } });
    await r.body?.cancel();
    assertEquals(r.headers.get('access-control-allow-origin'), null);
  });
}
