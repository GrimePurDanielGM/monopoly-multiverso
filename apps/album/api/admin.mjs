// POST /api/admin — acciones del anfitrión (PIN): comprobar, marcar una subida
// como «ya en iCloud» (o volver a pendiente) o borrarla del todo.

import { json, leerJsonBody, pinCorrecto, soloMetodo } from './_comun.mjs';
import {
  borrarObjetos,
  configDesdeEnv,
  guardarJson,
  idValido,
  leerJson,
  rutaMeta,
} from '../lib/supabase.mjs';

export default async function handler(req, res) {
  if (!soloMetodo(req, res, 'POST')) return;
  let datos;
  try {
    datos = await leerJsonBody(req);
  } catch {
    return json(res, 400, { error: 'Cuerpo JSON no válido' });
  }

  if (!process.env.ADMIN_PIN) {
    return json(res, 403, {
      error: 'El modo anfitrión no está activado: configura la variable ADMIN_PIN en Vercel',
    });
  }
  if (!pinCorrecto(datos.pin)) return json(res, 403, { error: 'PIN incorrecto' });

  const accion = String(datos.accion || '');
  if (accion === 'comprobar') return json(res, 200, { ok: true });

  const cfg = configDesdeEnv();
  if (!cfg.disponible) return json(res, 503, { error: 'Las subidas no están configuradas' });
  const id = String(datos.id || '');
  if (!idValido(id)) return json(res, 400, { error: 'Identificador no válido' });

  try {
    const meta = await leerJson(cfg, rutaMeta(id));
    if (!meta) return json(res, 404, { error: 'No existe esa foto' });

    if (accion === 'en_icloud' || accion === 'pendiente') {
      meta.estado = accion;
      await guardarJson(cfg, rutaMeta(id), meta);
      return json(res, 200, { ok: true, item: meta });
    }
    if (accion === 'borrar') {
      await borrarObjetos(cfg, [meta.archivo, meta.originalArchivo, rutaMeta(id)].filter(Boolean));
      return json(res, 200, { ok: true });
    }
    json(res, 400, { error: 'Acción desconocida' });
  } catch (err) {
    json(res, 502, { error: `No se pudo completar la acción: ${String((err && err.message) || err)}` });
  }
}
