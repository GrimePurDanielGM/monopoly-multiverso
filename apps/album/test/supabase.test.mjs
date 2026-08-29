import test from 'node:test';
import assert from 'node:assert/strict';
import {
  asegurarBucket,
  configDesdeEnv,
  firmarSubida,
  idValido,
  nuevoId,
  rutaArchivo,
  rutaMeta,
  rutaOriginal,
  urlPublica,
} from '../lib/supabase.mjs';

test('configDesdeEnv: variables, alternativa VITE_ y barra final', () => {
  const sin = configDesdeEnv({});
  assert.equal(sin.disponible, false);

  const cfg = configDesdeEnv({
    VITE_SUPABASE_URL: 'https://abc.supabase.co/',
    SUPABASE_SERVICE_ROLE_KEY: 'clave',
  });
  assert.equal(cfg.url, 'https://abc.supabase.co');
  assert.equal(cfg.disponible, true);
  assert.equal(cfg.bucket, 'album-familiar');

  const propia = configDesdeEnv({
    SUPABASE_URL: 'https://otra.supabase.co',
    VITE_SUPABASE_URL: 'https://abc.supabase.co',
    SUPABASE_SERVICE_ROLE_KEY: 'clave',
    ALBUM_BUCKET: 'mi-bucket',
  });
  assert.equal(propia.url, 'https://otra.supabase.co');
  assert.equal(propia.bucket, 'mi-bucket');
});

test('ids y rutas de objetos', () => {
  const id = nuevoId();
  assert.ok(idValido(id), `id generado válido: ${id}`);
  assert.ok(!idValido('../meta/otro'));
  assert.ok(!idValido(''));
  assert.equal(rutaArchivo('abc-12345678', '.jpg'), 'fotos/abc-12345678.jpg');
  assert.equal(rutaOriginal('abc-12345678', '.heic'), 'originales/abc-12345678.heic');
  assert.equal(rutaMeta('abc-12345678'), 'meta/abc-12345678.json');
  const cfg = configDesdeEnv({ SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k' });
  assert.equal(
    urlPublica(cfg, 'fotos/a.jpg'),
    'https://x.supabase.co/storage/v1/object/public/album-familiar/fotos/a.jpg',
  );
});

function conFetchFalso(respuestas, fn) {
  const original = globalThis.fetch;
  const llamadas = [];
  globalThis.fetch = async (url, opts = {}) => {
    llamadas.push({ url: String(url), method: opts.method || 'GET' });
    const r = respuestas.shift();
    if (!r) throw new Error('fetch inesperado: ' + url);
    return {
      ok: r.status >= 200 && r.status < 300,
      status: r.status,
      headers: { get: (k) => (r.headers || {})[k.toLowerCase()] || null },
      json: async () => r.json ?? {},
    };
  };
  return Promise.resolve()
    .then(() => fn(llamadas))
    .finally(() => {
      globalThis.fetch = original;
    });
}

const cfg = configDesdeEnv({ SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k' });

test('asegurarBucket: lo crea si no existe y tolera la carrera', async () => {
  await conFetchFalso([{ status: 404 }, { status: 200 }], async (llamadas) => {
    assert.equal(await asegurarBucket(cfg), true);
    assert.equal(llamadas[0].method, 'GET');
    assert.equal(llamadas[1].method, 'POST');
  });
  // otro proceso lo creó entre el GET y el POST
  await conFetchFalso([{ status: 404 }, { status: 409 }, { status: 200 }], async () => {
    assert.equal(await asegurarBucket(cfg), true);
  });
  await conFetchFalso([{ status: 404 }, { status: 500 }, { status: 500 }], async () => {
    await assert.rejects(() => asegurarBucket(cfg));
  });
});

test('firmarSubida devuelve la URL absoluta con el token', async () => {
  await conFetchFalso(
    [{ status: 200, json: { url: '/object/upload/sign/album-familiar/fotos/a.jpg?token=T' } }],
    async () => {
      const url = await firmarSubida(cfg, 'fotos/a.jpg');
      assert.equal(url, 'https://x.supabase.co/storage/v1/object/upload/sign/album-familiar/fotos/a.jpg?token=T');
    },
  );
});
