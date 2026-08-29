// GET /api/descargar?checksum=… — sirve una FOTO del álbum de iCloud a través
// del servidor. Hace falta porque los servidores de imágenes de Apple no
// permiten peticiones del navegador desde otros dominios (CORS), y sin esto no
// se podría montar el ZIP de descarga en lote ni forzar la descarga individual.
// Solo fotos: las respuestas de las funciones de Vercel están limitadas a
// ~4,5 MB y las fotos de un álbum compartido (máx. 2048 px) caben de sobra;
// los vídeos se descargan con su URL directa.

import { json, soloMetodo } from './_comun.mjs';
import { SharedAlbum, fetchAlbum, tokenFromUrl } from '../lib/icloud.mjs';

const ALBUM_URL_DEFECTO = 'https://www.icloud.com/sharedalbum/#B2PGgZLKuKkNJ1h';
const TOKEN = tokenFromUrl(process.env.ALBUM_URL || process.env.ALBUM_TOKEN || ALBUM_URL_DEFECTO);
const CACHE_MS = 60 * 1000;
const LIMITE_BYTES = 4 * 1024 * 1024;

const cache = { at: 0, mapa: null };

async function mapaAssets(checksum) {
  const caducado = Date.now() - cache.at > CACHE_MS;
  if (!cache.mapa || caducado || !cache.mapa.has(checksum)) {
    const album = new SharedAlbum(TOKEN);
    const r = await fetchAlbum(album);
    cache.mapa = r.assetMap;
    cache.at = Date.now();
  }
  return cache.mapa;
}

export default async function handler(req, res) {
  if (!soloMetodo(req, res, 'GET')) return;
  const url = new URL(req.url, 'http://localhost');
  const checksum = String(url.searchParams.get('checksum') || '');
  if (!/^[0-9a-f]{6,}$/i.test(checksum)) return json(res, 400, { error: 'Checksum no válido' });

  try {
    const mapa = await mapaAssets(checksum);
    const entrada = mapa.get(checksum);
    if (!entrada) return json(res, 404, { error: 'Foto no encontrada en el álbum' });

    const upstream = await fetch(entrada.url, { signal: AbortSignal.timeout(25000) });
    if (!upstream.ok) return json(res, 502, { error: `iCloud respondió ${upstream.status}` });
    const datos = Buffer.from(await upstream.arrayBuffer());
    if (datos.length > LIMITE_BYTES) {
      // Demasiado grande para responder desde la función: que el navegador
      // vaya directo al original de iCloud.
      res.statusCode = 302;
      res.setHeader('Location', entrada.url);
      return res.end();
    }
    const nombre = (entrada.filename || `foto-${checksum.slice(0, 8)}.jpg`).replace(/[^\wÀ-ſ .()-]/g, '_');
    res.statusCode = 200;
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/octet-stream');
    res.setHeader('Content-Disposition', `attachment; filename="${nombre}"`);
    // Las URL firmadas de iCloud rotan, pero el contenido de un checksum es
    // inmutable: la caché del CDN ahorra vueltas en descargas en lote.
    res.setHeader('Cache-Control', 'public, s-maxage=1800');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.end(datos);
  } catch (err) {
    json(res, 502, { error: `No se pudo descargar: ${String((err && err.message) || err)}` });
  }
}
