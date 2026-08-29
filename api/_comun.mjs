// Utilidades compartidas por las funciones serverless del álbum familiar.
// (Los archivos de api/ que empiezan por "_" no se exponen como rutas.)

import crypto from 'node:crypto';

export function json(res, status, datos) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  if (!res.getHeader('Cache-Control')) res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(datos));
}

/** Lee el cuerpo JSON venga como venga (objeto ya parseado, string, Buffer o stream). */
export async function leerJsonBody(req, maxBytes = 256 * 1024) {
  const previo = req.body;
  if (previo !== undefined && previo !== null) {
    if (typeof previo === 'object' && !Buffer.isBuffer(previo)) return previo;
    const texto = Buffer.isBuffer(previo) ? previo.toString('utf8') : String(previo);
    return JSON.parse(texto);
  }
  const trozos = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > maxBytes) throw new Error('Cuerpo demasiado grande');
    trozos.push(chunk);
  }
  const texto = Buffer.concat(trozos).toString('utf8');
  return texto ? JSON.parse(texto) : {};
}

export function pinCorrecto(pin) {
  const esperado = process.env.ADMIN_PIN || '';
  if (!esperado) return false;
  const a = Buffer.from(String(pin || ''));
  const b = Buffer.from(esperado);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export function soloMetodo(req, res, metodo) {
  if (req.method === metodo) return true;
  json(res, 405, { error: 'Método no permitido' });
  return false;
}
