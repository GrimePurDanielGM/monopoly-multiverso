// POST /api/subida-firmada — prepara una subida: crea el bucket si hace falta,
// guarda el metadato provisional y devuelve la URL firmada de Supabase a la que
// el navegador sube el archivo DIRECTAMENTE (sin pasar por Vercel, que limita
// el tamaño de las peticiones a ~4,5 MB).

import { json, leerJsonBody, soloMetodo } from './_comun.mjs';
import { generarClaveBorrado, hashClave, safeExt, sanitizeName } from '../lib/store.mjs';
import {
  asegurarBucket,
  configDesdeEnv,
  firmarSubida,
  guardarJson,
  listarMetas,
  nuevoId,
  rutaArchivo,
  rutaMeta,
  rutaOriginal,
  urlPublica,
} from '../lib/supabase.mjs';

const MAX_MB = Number(process.env.MAX_UPLOAD_MB) || 100;
let bucketListo = false;

export default async function handler(req, res) {
  if (!soloMetodo(req, res, 'POST')) return;
  const cfg = configDesdeEnv();
  if (!cfg.disponible) {
    return json(res, 503, {
      error: 'Las subidas aún no están configuradas en el servidor (faltan las variables de Supabase en Vercel).',
    });
  }

  let datos;
  try {
    datos = await leerJsonBody(req);
  } catch {
    return json(res, 400, { error: 'Cuerpo JSON no válido' });
  }

  const uploader = String(datos.nombre || '').trim().slice(0, 60);
  const caption = String(datos.comentario || '').trim().slice(0, 300);
  const filename = String(datos.filename || '');
  const contentType = String(datos.contentType || '').toLowerCase();
  const size = Number(datos.size) || 0;

  if (!uploader) return json(res, 400, { error: 'Dinos tu nombre para saber quién sube la foto' });
  if (!contentType.startsWith('image/') && !contentType.startsWith('video/')) {
    return json(res, 400, { error: `"${filename || 'El archivo'}" no es una foto ni un vídeo` });
  }
  if (size > MAX_MB * 1024 * 1024) {
    return json(res, 413, { error: `Archivo demasiado grande (máximo ${MAX_MB} MB)` });
  }

  // Original opcional: la versión ligera se sube ya y el original en segundo plano
  let original = null;
  if (datos.original && typeof datos.original === 'object') {
    const tipoOrig = String(datos.original.contentType || '').toLowerCase();
    const sizeOrig = Number(datos.original.size) || 0;
    if (!tipoOrig.startsWith('image/') && !tipoOrig.startsWith('video/')) {
      return json(res, 400, { error: 'El original no es una foto ni un vídeo' });
    }
    if (sizeOrig > MAX_MB * 1024 * 1024) {
      return json(res, 413, { error: `El original es demasiado grande (máximo ${MAX_MB} MB)` });
    }
    original = { filename: String(datos.original.filename || filename), contentType: tipoOrig };
  }

  const hash = /^[0-9a-f]{64}$/.test(String(datos.hash || '')) ? String(datos.hash) : null;

  try {
    if (!bucketListo) {
      await asegurarBucket(cfg);
      bucketListo = true;
    }
    // La misma foto subida dos veces (reintentos por lentitud) no se duplica
    if (hash) {
      const repetida = (await listarMetas(cfg)).find((m) => m.hash === hash && m.estado !== 'subiendo');
      if (repetida) return json(res, 200, { duplicado: true, id: repetida.id });
    }
    const id = nuevoId();
    const clave = generarClaveBorrado();
    const archivo = rutaArchivo(id, safeExt(filename, contentType));
    const uploadUrl = await firmarSubida(cfg, archivo);
    const originalArchivo = original ? rutaOriginal(id, safeExt(original.filename, original.contentType)) : null;
    const originalUploadUrl = originalArchivo ? await firmarSubida(cfg, originalArchivo) : null;
    await guardarJson(cfg, rutaMeta(id), {
      id,
      archivo,
      url: urlPublica(cfg, archivo),
      originalName: sanitizeName(filename) || archivo,
      contentType,
      isVideo: contentType.startsWith('video/'),
      size,
      uploader,
      caption,
      uploadedAt: new Date().toISOString(),
      estado: 'subiendo',
      hash,
      claveBorradoHash: hashClave(clave),
      ...(originalArchivo ? { originalArchivo } : {}),
    });
    json(res, 200, { id, uploadUrl, contentType, clave, originalUploadUrl });
  } catch (err) {
    json(res, 502, { error: `No se pudo preparar la subida: ${String((err && err.message) || err)}` });
  }
}
