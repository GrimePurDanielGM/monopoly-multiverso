// POST /api/borrar-mia — quien subió una foto puede borrarla sin PIN: su
// navegador guarda la clave que le dimos al subirla; aquí se compara su hash
// con el guardado en los metadatos (el metadato es público, la clave no).

import { json, leerJsonBody, soloMetodo } from './_comun.mjs';
import { claveValida } from '../lib/store.mjs';
import {
  borrarObjetos,
  configDesdeEnv,
  idValido,
  leerJson,
  rutaMeta,
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
    if (!meta) return json(res, 404, { error: 'No existe esa foto' });
    if (!claveValida(String(datos.clave || ''), meta.claveBorradoHash)) {
      return json(res, 403, { error: 'Solo quien subió la foto (desde su mismo dispositivo) puede borrarla' });
    }
    await borrarObjetos(cfg, [meta.archivo, rutaMeta(id)]);
    json(res, 200, { ok: true });
  } catch (err) {
    json(res, 502, { error: `No se pudo borrar: ${String((err && err.message) || err)}` });
  }
}
