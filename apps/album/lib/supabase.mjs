// Almacén de subidas sobre Supabase Storage (API REST, sin dependencias).
// Se usa en el despliegue serverless (Vercel): los archivos van a un bucket
// público y los metadatos a un JSON "sidecar" por subida (meta/<id>.json).
// La clave service_role solo vive en el servidor; el navegador sube el archivo
// directamente a Supabase con una URL firmada (así evitamos el límite de
// tamaño de las funciones de Vercel).

import crypto from 'node:crypto';

export const BUCKET_DEFECTO = 'album-familiar';

export function configDesdeEnv(env = process.env) {
  const url = (env.SUPABASE_URL || env.VITE_SUPABASE_URL || '').replace(/\/+$/, '');
  const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY || '';
  const bucket = env.ALBUM_BUCKET || BUCKET_DEFECTO;
  return { url, serviceKey, bucket, disponible: Boolean(url && serviceKey) };
}

export function nuevoId() {
  return `${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}`;
}

export function rutaArchivo(id, ext) {
  return `fotos/${id}${ext}`;
}

export function rutaMeta(id) {
  return `meta/${id}.json`;
}

export function idValido(id) {
  return /^[a-z0-9]+-[a-f0-9]{8}$/.test(String(id || ''));
}

export function urlPublica(cfg, ruta) {
  return `${cfg.url}/storage/v1/object/public/${cfg.bucket}/${ruta}`;
}

function cabeceras(cfg, extra = {}) {
  return {
    Authorization: `Bearer ${cfg.serviceKey}`,
    apikey: cfg.serviceKey,
    ...extra,
  };
}

async function api(cfg, metodo, ruta, { body, json, extraHeaders } = {}) {
  const res = await fetch(`${cfg.url}/storage/v1${ruta}`, {
    method: metodo,
    headers: cabeceras(cfg, {
      ...(json !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...extraHeaders,
    }),
    body: json !== undefined ? JSON.stringify(json) : body,
    signal: AbortSignal.timeout(20000),
  });
  return res;
}

/** Crea el bucket público si no existe todavía (idempotente). */
export async function asegurarBucket(cfg) {
  const existe = await api(cfg, 'GET', `/bucket/${cfg.bucket}`);
  if (existe.ok) return true;
  const creado = await api(cfg, 'POST', '/bucket', {
    json: { id: cfg.bucket, name: cfg.bucket, public: true, file_size_limit: 104857600 },
  });
  if (creado.ok) return true;
  // Carrera entre dos peticiones simultáneas: si ya existe, vale igual.
  const otra = await api(cfg, 'GET', `/bucket/${cfg.bucket}`);
  if (otra.ok) return true;
  throw new Error(`No se pudo crear el bucket «${cfg.bucket}» (${creado.status})`);
}

/** URL firmada para que el navegador suba el archivo directamente a Supabase. */
export async function firmarSubida(cfg, ruta) {
  const res = await api(cfg, 'POST', `/object/upload/sign/${cfg.bucket}/${ruta}`, { json: {} });
  if (!res.ok) throw new Error(`No se pudo firmar la subida (${res.status})`);
  const datos = await res.json();
  // La respuesta trae una ruta relativa tipo /object/upload/sign/...?token=…
  const relativa = String(datos.url || '');
  if (!relativa) throw new Error('Supabase no devolvió la URL firmada');
  return `${cfg.url}/storage/v1${relativa.startsWith('/') ? '' : '/'}${relativa}`;
}

/** Comprueba que un objeto existe (bucket público) y devuelve su tamaño o null. */
export async function tamanoObjeto(cfg, ruta) {
  const res = await fetch(urlPublica(cfg, ruta), {
    method: 'HEAD',
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) return null;
  const len = Number(res.headers.get('content-length'));
  return Number.isFinite(len) ? len : 0;
}

export async function guardarJson(cfg, ruta, datos) {
  const res = await api(cfg, 'POST', `/object/${cfg.bucket}/${ruta}`, {
    body: JSON.stringify(datos),
    extraHeaders: { 'Content-Type': 'application/json', 'x-upsert': 'true' },
  });
  if (!res.ok) throw new Error(`No se pudo guardar ${ruta} (${res.status})`);
}

export async function leerJson(cfg, ruta) {
  const res = await fetch(`${urlPublica(cfg, ruta)}?t=${Date.now()}`, {
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) return null;
  try {
    return await res.json();
  } catch {
    return null;
  }
}

export async function borrarObjetos(cfg, rutas) {
  const res = await api(cfg, 'DELETE', `/object/${cfg.bucket}`, { json: { prefixes: rutas } });
  return res.ok;
}

/** Lista los metadatos de todas las subidas (los sidecars de meta/). */
export async function listarMetas(cfg) {
  const res = await api(cfg, 'POST', `/object/list/${cfg.bucket}`, {
    json: {
      prefix: 'meta/',
      limit: 500,
      sortBy: { column: 'name', order: 'desc' },
    },
  });
  if (!res.ok) throw new Error(`No se pudo listar las subidas (${res.status})`);
  const entradas = await res.json();
  const nombres = (Array.isArray(entradas) ? entradas : [])
    .map((e) => e.name)
    .filter((n) => typeof n === 'string' && n.endsWith('.json'));

  const items = [];
  const LOTE = 8;
  for (let i = 0; i < nombres.length; i += LOTE) {
    const lote = await Promise.all(nombres.slice(i, i + LOTE).map((n) => leerJson(cfg, `meta/${n}`)));
    for (const meta of lote) if (meta && meta.id) items.push(meta);
  }
  return items;
}
