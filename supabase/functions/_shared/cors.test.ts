// Ejecutar: deno test --allow-none supabase/functions/_shared/cors.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { corsHeaders, preflight, jsonCors, isAllowedOrigin } from './cors.ts';

const VERCEL = 'https://monopoly-multiverso-web.vercel.app';

Deno.test('origen Vercel permitido: refleja Allow-Origin', () => {
  const h = corsHeaders(VERCEL);
  assertEquals(h['Access-Control-Allow-Origin'], VERCEL);
});

Deno.test('orígenes locales permitidos (5173)', () => {
  for (const o of ['http://localhost:5173', 'http://127.0.0.1:5173']) {
    assertEquals(corsHeaders(o)['Access-Control-Allow-Origin'], o);
    assert(isAllowedOrigin(o));
  }
});

Deno.test('origen no autorizado: SIN Allow-Origin', () => {
  const h = corsHeaders('https://evil.example.com');
  assertEquals(h['Access-Control-Allow-Origin'], undefined);
  assert(!isAllowedOrigin('https://evil.example.com'));
});

Deno.test('sin Origin (no-navegador): SIN Allow-Origin, pero con metadatos CORS', () => {
  const h = corsHeaders(null);
  assertEquals(h['Access-Control-Allow-Origin'], undefined);
  assertEquals(h['Vary'], 'Origin');
});

Deno.test('cabeceras CORS necesarias presentes (headers/métodos/Vary)', () => {
  const h = corsHeaders(VERCEL);
  assert(h['Access-Control-Allow-Headers'].includes('authorization'));
  assert(h['Access-Control-Allow-Headers'].includes('x-client-info'));
  assert(h['Access-Control-Allow-Headers'].includes('apikey'));
  assert(h['Access-Control-Allow-Headers'].includes('content-type'));
  assert(h['Access-Control-Allow-Methods'].includes('POST'));
  assert(h['Access-Control-Allow-Methods'].includes('OPTIONS'));
  assertEquals(h['Vary'], 'Origin');
});

Deno.test('no se emite Allow-Credentials (auth por bearer, sin cookies)', () => {
  assertEquals(corsHeaders(VERCEL)['Access-Control-Allow-Credentials'], undefined);
});

Deno.test('preflight: 200 con cabeceras CORS', () => {
  const r = preflight(VERCEL);
  assertEquals(r.status, 200);
  assertEquals(r.headers.get('Access-Control-Allow-Origin'), VERCEL);
  assert((r.headers.get('Access-Control-Allow-Methods') ?? '').includes('OPTIONS'));
});

Deno.test('jsonCors: error con CORS y content-type JSON', () => {
  const r = jsonCors({ error: 'NOT_AUTHENTICATED' }, 401, VERCEL);
  assertEquals(r.status, 401);
  assertEquals(r.headers.get('content-type'), 'application/json');
  assertEquals(r.headers.get('Access-Control-Allow-Origin'), VERCEL);
});
