// GET /api/estado — capacidades del despliegue serverless del álbum.

import { json, soloMetodo } from './_comun.mjs';
import { tokenFromUrl } from '../lib/icloud.mjs';
import { configDesdeEnv } from '../lib/supabase.mjs';

const ALBUM_URL_DEFECTO = 'https://www.icloud.com/sharedalbum/#B2PGgZLKuKkNJ1h';

export default function handler(req, res) {
  if (!soloMetodo(req, res, 'GET')) return;
  const token = tokenFromUrl(process.env.ALBUM_URL || process.env.ALBUM_TOKEN || ALBUM_URL_DEFECTO);
  const cfg = configDesdeEnv();
  const faltan = [
    !cfg.url && 'SUPABASE_URL (o VITE_SUPABASE_URL)',
    !cfg.serviceKey && 'SUPABASE_SERVICE_ROLE_KEY',
  ].filter(Boolean);
  json(res, 200, {
    ok: true,
    modo: 'vercel',
    subidasDisponibles: cfg.disponible,
    maxSubidaMB: Number(process.env.MAX_UPLOAD_MB) || 100,
    adminDisponible: Boolean(process.env.ADMIN_PIN),
    albumUrl: `https://www.icloud.com/sharedalbum/#${token}`,
    avisoConfiguracion: cfg.disponible
      ? null
      : `Para activar las subidas falta configurar en Vercel: ${faltan.join(' y ')}.`,
  });
}
