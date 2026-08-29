// GET /api/uploads — lista las fotos subidas por la familia (Supabase Storage).

import { json, soloMetodo } from './_comun.mjs';
import { configDesdeEnv, listarMetas } from '../lib/supabase.mjs';

export default async function handler(req, res) {
  if (!soloMetodo(req, res, 'GET')) return;
  const cfg = configDesdeEnv();
  if (!cfg.disponible) return json(res, 200, { uploads: [] });

  try {
    const metas = await listarMetas(cfg);
    const uploads = metas
      // 'subiendo' = quedó a medias (p. ej. el navegador se cerró): no se muestra
      .filter((m) => m.estado === 'pendiente' || m.estado === 'en_icloud')
      .sort((a, b) => String(b.uploadedAt).localeCompare(String(a.uploadedAt)))
      // lista blanca: los campos internos (hashes, ruta) no van al navegador
      .map((m) => ({
        id: m.id,
        url: m.url,
        originalName: m.originalName,
        contentType: m.contentType,
        isVideo: m.isVideo,
        size: m.size,
        uploader: m.uploader,
        caption: m.caption,
        uploadedAt: m.uploadedAt,
        estado: m.estado,
        originalUrl: m.originalUrl,
        originalSize: m.originalSize,
      }));
    json(res, 200, { uploads });
  } catch (err) {
    json(res, 502, { error: `No se pudieron listar las subidas: ${String((err && err.message) || err)}` });
  }
}
