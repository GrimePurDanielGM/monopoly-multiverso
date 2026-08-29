// GET /api/album — feed del álbum compartido de iCloud, normalizado.
// La caché del CDN de Vercel (s-maxage) hace de caché compartida; la variable
// de módulo cubre además las invocaciones "calientes" de la misma lambda.

import { json, soloMetodo } from './_comun.mjs';
import { SharedAlbum, fetchAlbum, tokenFromUrl } from '../lib/icloud.mjs';

const ALBUM_URL_DEFECTO = 'https://www.icloud.com/sharedalbum/#B2PGgZLKuKkNJ1h';
const TOKEN = tokenFromUrl(process.env.ALBUM_URL || process.env.ALBUM_TOKEN || ALBUM_URL_DEFECTO);
const CACHE_MS = 60 * 1000;

const cache = { at: 0, data: null };
let album = new SharedAlbum(TOKEN);

export default async function handler(req, res) {
  if (!soloMetodo(req, res, 'GET')) return;
  const forzar = String(req.url || '').includes('refrescar=1');

  if (!cache.data || forzar || Date.now() - cache.at > CACHE_MS) {
    try {
      const r = await fetchAlbum(album);
      cache.data = {
        streamName: r.streamName,
        owner: r.owner,
        photos: r.photos,
      };
      cache.at = Date.now();
    } catch (err) {
      if (!cache.data) {
        return json(res, 503, {
          error: 'No se pudo conectar con iCloud. Inténtalo en un momento.',
          detalle: String((err && err.message) || err),
        });
      }
      // Reintento limpio en la próxima invocación
      album = new SharedAlbum(TOKEN);
    }
  }

  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=240');
  json(res, 200, {
    streamName: cache.data.streamName,
    owner: cache.data.owner,
    fetchedAt: cache.at,
    stale: Date.now() - cache.at > CACHE_MS * 2,
    error: null,
    photos: cache.data.photos,
  });
}
