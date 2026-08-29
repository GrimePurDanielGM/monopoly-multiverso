// POST /api/subida-confirmar — tras subir el archivo a Supabase, comprueba que
// existe de verdad y marca la subida como pendiente (visible para la familia).

import { json, leerJsonBody, soloMetodo } from './_comun.mjs';
import {
  configDesdeEnv,
  guardarJson,
  idValido,
  leerJson,
  rutaMeta,
  tamanoObjeto,
} from '../lib/supabase.mjs';

export default async function handler(req, res) {
  if (!soloMetodo(req, res, 'POST')) return;
  const cfg = configDesdeEnv();
  if (!cfg.disponible) return json(res, 503, { error: 'Las subidas no están configuradas' });

  let datos;
  try {
    datos = await leerJsonBody(req);
  } catch {
    return json(res, 400, { error: 'Cuerpo JSON no válido' });
  }
  const id = String(datos.id || '');
  if (!idValido(id)) return json(res, 400, { error: 'Identificador no válido' });

  try {
    const meta = await leerJson(cfg, rutaMeta(id));
    if (!meta) return json(res, 404, { error: 'No existe esa subida' });
    const bytes = await tamanoObjeto(cfg, meta.archivo);
    if (bytes === null) return json(res, 409, { error: 'El archivo aún no ha llegado a Supabase' });
    meta.size = bytes || meta.size;
    meta.estado = meta.estado === 'en_icloud' ? 'en_icloud' : 'pendiente';
    await guardarJson(cfg, rutaMeta(id), meta);
    json(res, 200, { ok: true, item: meta });
  } catch (err) {
    json(res, 502, { error: `No se pudo confirmar la subida: ${String((err && err.message) || err)}` });
  }
}
