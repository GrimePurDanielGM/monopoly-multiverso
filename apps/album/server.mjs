// Servidor del álbum familiar: sirve la web, lee el álbum compartido de iCloud
// en directo y guarda las fotos que sube la familia desde cualquier móvil.
// Sin dependencias: solo Node >= 20.  Arranque:  node server.mjs

import http from 'node:http';
import path from 'node:path';
import crypto from 'node:crypto';
import { promises as fsp, createReadStream } from 'node:fs';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';

import { SharedAlbum, fetchAlbum, tokenFromUrl } from './lib/icloud.mjs';
import { boundaryFromContentType, parseMultipart } from './lib/multipart.mjs';
import { UploadStore, claveValida, hashContenido } from './lib/store.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, 'public');

// ---------------------------------------------------------------- configuración
const ALBUM_URL_DEFECTO = 'https://www.icloud.com/sharedalbum/#B2PGgZLKuKkNJ1h';
const TOKEN = tokenFromUrl(process.env.ALBUM_URL || process.env.ALBUM_TOKEN || ALBUM_URL_DEFECTO);
const PORT = Number(process.env.PORT) || 8787;
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const ADMIN_PIN = process.env.ADMIN_PIN || '';
const MAX_UPLOAD_MB = Number(process.env.MAX_UPLOAD_MB) || 100;
const CACHE_SEGUNDOS = Number(process.env.CACHE_SEGUNDOS) || 60;

const album = new SharedAlbum(TOKEN);
const store = new UploadStore(DATA_DIR);

// ------------------------------------------------------------- caché del álbum
const cache = { at: 0, data: null, assetMap: new Map(), error: null, fetching: null };

async function albumCacheado(forzar = false) {
  const fresco = Date.now() - cache.at < CACHE_SEGUNDOS * 1000;
  if (cache.data && fresco && !forzar) return cache;
  if (!cache.fetching) {
    cache.fetching = (async () => {
      try {
        const res = await fetchAlbum(album);
        cache.data = { streamName: res.streamName, owner: res.owner, photos: res.photos };
        cache.assetMap = res.assetMap;
        cache.at = Date.now();
        cache.error = null;
      } catch (err) {
        cache.error = String((err && err.message) || err);
        console.error('Error al leer el álbum de iCloud:', cache.error);
      } finally {
        cache.fetching = null;
      }
    })();
  }
  await cache.fetching;
  return cache;
}

// ------------------------------------------------------------------- utilidades
function jsonRes(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function leerCuerpo(req, maxBytes) {
  return new Promise((resolve, reject) => {
    const declarado = Number(req.headers['content-length']);
    if (Number.isFinite(declarado) && declarado > maxBytes) {
      reject(Object.assign(new Error('demasiado grande'), { code: 'E2BIG' }));
      req.destroy();
      return;
    }
    const chunks = [];
    let total = 0;
    req.on('data', (chunk) => {
      total += chunk.length;
      if (total > maxBytes) {
        reject(Object.assign(new Error('demasiado grande'), { code: 'E2BIG' }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function pinCorrecto(pin) {
  if (!ADMIN_PIN) return false;
  const a = Buffer.from(String(pin || ''));
  const b = Buffer.from(ADMIN_PIN);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function uploadParaCliente(item) {
  return {
    id: item.id,
    url: `/uploads/${item.storedName}`,
    originalName: item.originalName,
    contentType: item.contentType,
    isVideo: item.contentType.startsWith('video/'),
    size: item.size,
    uploader: item.uploader,
    caption: item.caption,
    uploadedAt: item.uploadedAt,
    estado: item.estado,
  };
}

// ------------------------------------------------------------------ rutas /api
async function rutaAlbum(req, res, url) {
  const forzar = url.searchParams.get('refrescar') === '1';
  await albumCacheado(forzar);
  if (!cache.data) {
    return jsonRes(res, 503, {
      error: 'No se pudo conectar con iCloud. Inténtalo en un momento.',
      detalle: cache.error,
    });
  }
  jsonRes(res, 200, {
    streamName: cache.data.streamName,
    owner: cache.data.owner,
    fetchedAt: cache.at,
    stale: Boolean(cache.error),
    error: cache.error,
    photos: cache.data.photos,
  });
}

async function rutaSubir(req, res) {
  const ct = String(req.headers['content-type'] || '');
  const boundary = boundaryFromContentType(ct);
  if (!ct.startsWith('multipart/form-data') || !boundary) {
    return jsonRes(res, 400, { error: 'Se esperaba multipart/form-data' });
  }
  let body;
  try {
    body = await leerCuerpo(req, MAX_UPLOAD_MB * 1024 * 1024);
  } catch {
    return jsonRes(res, 413, { error: `Archivo demasiado grande (máximo ${MAX_UPLOAD_MB} MB)` });
  }
  let parsed;
  try {
    parsed = parseMultipart(body, boundary);
  } catch {
    return jsonRes(res, 400, { error: 'No se pudo leer la subida' });
  }
  const uploader = String(parsed.fields.nombre || '').trim();
  const caption = String(parsed.fields.comentario || '').trim();
  if (!uploader) return jsonRes(res, 400, { error: 'Dinos tu nombre para saber quién sube la foto' });

  const archivos = parsed.files.filter((f) => f.field === 'fotos' || f.field === 'foto');
  if (!archivos.length) return jsonRes(res, 400, { error: 'No llegó ningún archivo' });
  if (archivos.length > 20) return jsonRes(res, 400, { error: 'Máximo 20 archivos por subida' });

  const subidas = [];
  let duplicados = 0;
  for (const f of archivos) {
    const tipo = String(f.contentType || '').toLowerCase();
    if (!tipo.startsWith('image/') && !tipo.startsWith('video/')) {
      return jsonRes(res, 400, { error: `"${f.filename}" no es una foto ni un vídeo` });
    }
    if (!f.data.length) continue;
    // La misma foto subida dos veces (reintentos por lentitud) no se duplica
    if (store.findByHash(hashContenido(f.data))) {
      duplicados += 1;
      continue;
    }
    const { item, clave } = await store.add({
      data: f.data,
      filename: f.filename,
      contentType: tipo,
      uploader,
      caption,
    });
    subidas.push({ ...uploadParaCliente(item), clave });
  }
  if (!subidas.length && !duplicados) return jsonRes(res, 400, { error: 'Los archivos llegaron vacíos' });
  jsonRes(res, 201, { ok: true, subidas, duplicados });
}

// Quien subió una foto puede borrarla sin PIN: su navegador guarda la clave
// que le dimos al subirla y aquí solo comparamos su hash.
async function rutaBorrarMia(req, res) {
  let datos;
  try {
    datos = JSON.parse((await leerCuerpo(req, 64 * 1024)).toString('utf8'));
  } catch {
    return jsonRes(res, 400, { error: 'Cuerpo JSON no válido' });
  }
  const item = store.get(String(datos.id || ''));
  if (!item) return jsonRes(res, 404, { error: 'No existe esa foto' });
  if (!claveValida(String(datos.clave || ''), item.claveBorradoHash)) {
    return jsonRes(res, 403, { error: 'Solo quien subió la foto (desde su mismo dispositivo) puede borrarla' });
  }
  await store.remove(item.id);
  jsonRes(res, 200, { ok: true });
}

async function rutaAdmin(req, res) {
  let datos;
  try {
    datos = JSON.parse((await leerCuerpo(req, 64 * 1024)).toString('utf8'));
  } catch {
    return jsonRes(res, 400, { error: 'Cuerpo JSON no válido' });
  }
  if (!ADMIN_PIN) {
    return jsonRes(res, 403, {
      error: 'El modo anfitrión no está activado: configura la variable ADMIN_PIN en el servidor',
    });
  }
  if (!pinCorrecto(datos.pin)) return jsonRes(res, 403, { error: 'PIN incorrecto' });

  const accion = String(datos.accion || '');
  if (accion === 'comprobar') return jsonRes(res, 200, { ok: true });

  const id = String(datos.id || '');
  if (accion === 'en_icloud' || accion === 'pendiente') {
    const item = await store.setEstado(id, accion);
    if (!item) return jsonRes(res, 404, { error: 'No existe esa foto' });
    return jsonRes(res, 200, { ok: true, item: uploadParaCliente(item) });
  }
  if (accion === 'borrar') {
    const ok = await store.remove(id);
    if (!ok) return jsonRes(res, 404, { error: 'No existe esa foto' });
    return jsonRes(res, 200, { ok: true });
  }
  jsonRes(res, 400, { error: 'Acción desconocida' });
}

// Descarga de una foto del álbum de iCloud a través del servidor
// (las URLs de iCloud no permiten forzar la descarga desde otro dominio).
async function rutaDescargar(req, res, url) {
  const checksum = String(url.searchParams.get('checksum') || '');
  if (!/^[0-9a-f]{6,}$/i.test(checksum)) return jsonRes(res, 400, { error: 'Checksum no válido' });
  let entry = cache.assetMap.get(checksum);
  const caducada = entry && entry.expiry && Date.parse(entry.expiry) - Date.now() < 60_000;
  if (!entry || caducada) {
    await albumCacheado(true);
    entry = cache.assetMap.get(checksum);
  }
  if (!entry) return jsonRes(res, 404, { error: 'Foto no encontrada en el álbum' });

  const upstream = await fetch(entry.url, { signal: AbortSignal.timeout(120_000) });
  if (!upstream.ok || !upstream.body) {
    return jsonRes(res, 502, { error: 'iCloud no devolvió el archivo' });
  }
  const nombre = (entry.filename || `foto-${checksum.slice(0, 8)}.jpg`).replace(/[^\wÀ-ſ .()-]/g, '_');
  const cabeceras = {
    'Content-Type': upstream.headers.get('content-type') || 'application/octet-stream',
    'Content-Disposition': `attachment; filename="${nombre}"`,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  };
  const len = upstream.headers.get('content-length');
  if (len) cabeceras['Content-Length'] = len;
  res.writeHead(200, cabeceras);
  Readable.fromWeb(upstream.body).pipe(res);
}

function rutaUploadsArchivo(req, res, nombre, descargar) {
  const abs = store.filePath(nombre);
  if (!abs) return jsonRes(res, 404, { error: 'Archivo no encontrado' });
  const item = store.items.find((i) => i.storedName === nombre);
  fsp.stat(abs).then(
    (st) => {
      const cabeceras = {
        'Content-Type': item?.contentType || 'application/octet-stream',
        'Content-Length': st.size,
        'Cache-Control': 'public, max-age=31536000, immutable',
        'X-Content-Type-Options': 'nosniff',
      };
      if (descargar) {
        cabeceras['Content-Disposition'] = `attachment; filename="${item?.originalName || nombre}"`;
      }
      res.writeHead(200, cabeceras);
      createReadStream(abs).pipe(res);
    },
    () => jsonRes(res, 404, { error: 'Archivo no encontrado' }),
  );
}

// -------------------------------------------------------------------- estáticos
const MIME_ESTATICO = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
};

async function rutaEstatica(res, ruta, esHead = false) {
  const rel = ruta === '/' ? 'index.html' : ruta.replace(/^\/+/, '');
  const abs = path.normalize(path.join(PUBLIC_DIR, rel));
  if (abs !== PUBLIC_DIR && !abs.startsWith(PUBLIC_DIR + path.sep)) {
    res.writeHead(404);
    return res.end('No encontrado');
  }
  const ext = path.extname(abs).toLowerCase();
  try {
    const st = await fsp.stat(abs);
    if (!st.isFile()) throw new Error('no es un archivo');
    const cachePolicy = ['.png', '.svg', '.ico'].includes(ext)
      ? 'public, max-age=86400'
      : 'no-cache';
    res.writeHead(200, {
      'Content-Type': MIME_ESTATICO[ext] || 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': cachePolicy,
      'X-Content-Type-Options': 'nosniff',
    });
    if (esHead) res.end();
    else createReadStream(abs).pipe(res);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('No encontrado');
  }
}

// ---------------------------------------------------------------------- router
const server = http.createServer((req, res) => {
  let url;
  let ruta;
  try {
    url = new URL(req.url, 'http://localhost');
    ruta = decodeURIComponent(url.pathname);
  } catch {
    return jsonRes(res, 400, { error: 'Ruta no válida' });
  }

  Promise.resolve()
    .then(() => {
      if (req.method === 'GET' && ruta === '/api/album') return rutaAlbum(req, res, url);
      if (req.method === 'GET' && ruta === '/api/uploads') {
        return jsonRes(res, 200, { uploads: store.list().map(uploadParaCliente) });
      }
      if (req.method === 'POST' && ruta === '/api/upload') return rutaSubir(req, res);
      if (req.method === 'POST' && ruta === '/api/borrar-mia') return rutaBorrarMia(req, res);
      if (req.method === 'POST' && ruta === '/api/admin') return rutaAdmin(req, res);
      if (req.method === 'GET' && ruta === '/api/descargar') return rutaDescargar(req, res, url);
      if (req.method === 'GET' && ruta === '/api/estado') {
        return jsonRes(res, 200, {
          ok: true,
          modo: 'servidor',
          subidasDisponibles: true,
          adminDisponible: Boolean(ADMIN_PIN),
          albumUrl: `https://www.icloud.com/sharedalbum/#${TOKEN}`,
        });
      }
      if (req.method === 'GET' && ruta.startsWith('/uploads/')) {
        return rutaUploadsArchivo(req, res, ruta.slice('/uploads/'.length), url.searchParams.has('descargar'));
      }
      if (ruta.startsWith('/api/')) return jsonRes(res, 404, { error: 'Ruta no encontrada' });
      if (req.method === 'GET' || req.method === 'HEAD') return rutaEstatica(res, ruta, req.method === 'HEAD');
      jsonRes(res, 405, { error: 'Método no permitido' });
    })
    .catch((err) => {
      console.error(`Error en ${req.method} ${ruta}:`, err);
      if (!res.headersSent) jsonRes(res, 500, { error: 'Error interno del servidor' });
      else res.end();
    });
});

// --------------------------------------------------------------------- arranque
await store.init();
server.listen(PORT, () => {
  console.log('─'.repeat(56));
  console.log('📸 Álbum familiar en marcha');
  console.log(`   Web:            http://localhost:${PORT}`);
  console.log(`   Álbum iCloud:   ${TOKEN}`);
  console.log(`   Datos/subidas:  ${DATA_DIR}`);
  console.log(`   Modo anfitrión: ${ADMIN_PIN ? 'activado (ADMIN_PIN)' : 'desactivado (define ADMIN_PIN)'}`);
  console.log('─'.repeat(56));
  // Primer aviso en el arranque para calentar la caché (sin bloquear).
  albumCacheado().then(() => {
    if (cache.data) {
      console.log(`✔ Álbum «${cache.data.streamName}» leído: ${cache.data.photos.length} elementos`);
    }
  });
});
