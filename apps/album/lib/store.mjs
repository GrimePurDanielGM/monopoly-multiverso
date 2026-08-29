// Almacén de las fotos subidas desde la web: archivos en DATA_DIR/uploads/
// y metadatos en DATA_DIR/uploads.json (escritura atómica y en serie).

import { promises as fsp } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const EXT_POR_MIME = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/gif': '.gif',
  'image/webp': '.webp',
  'image/avif': '.avif',
  'image/heic': '.heic',
  'image/heif': '.heif',
  'video/mp4': '.mp4',
  'video/quicktime': '.mov',
  'video/webm': '.webm',
  'video/x-m4v': '.m4v',
  'video/3gpp': '.3gp',
};

const EXTENSIONES_OK = new Set(Object.values(EXT_POR_MIME).concat(['.jpeg']));

export function safeExt(filename, contentType) {
  const ext = path.extname(String(filename || '')).toLowerCase();
  if (EXTENSIONES_OK.has(ext)) return ext === '.jpeg' ? '.jpg' : ext;
  return EXT_POR_MIME[String(contentType || '').toLowerCase()] || '.bin';
}

export function sanitizeName(name) {
  return String(name || '')
    .replace(/[/\\]/g, ' ')
    .replace(/[^\wÀ-ɏ .()-]/g, '_')
    .trim()
    .slice(0, 120);
}

/** Clave secreta que se lleva quien sube la foto: le permite borrarla sin PIN. */
export function generarClaveBorrado() {
  return crypto.randomBytes(16).toString('hex');
}

/** En los metadatos solo se guarda el hash de la clave (los metadatos pueden ser públicos). */
export function hashClave(clave) {
  return crypto.createHash('sha256').update(String(clave || '')).digest('hex');
}

export function claveValida(clave, claveBorradoHash) {
  if (!clave || !claveBorradoHash) return false;
  const a = Buffer.from(hashClave(clave));
  const b = Buffer.from(String(claveBorradoHash));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export function hashContenido(data) {
  return crypto.createHash('sha256').update(data).digest('hex');
}

export class UploadStore {
  constructor(dataDir) {
    this.dataDir = dataDir;
    this.uploadsDir = path.join(dataDir, 'uploads');
    this.metaFile = path.join(dataDir, 'uploads.json');
    this.items = [];
    this.queue = Promise.resolve();
  }

  async init() {
    await fsp.mkdir(this.uploadsDir, { recursive: true });
    try {
      const parsed = JSON.parse(await fsp.readFile(this.metaFile, 'utf8'));
      this.items = Array.isArray(parsed) ? parsed : [];
    } catch {
      this.items = [];
    }
  }

  persist() {
    this.queue = this.queue
      .then(async () => {
        const tmp = `${this.metaFile}.tmp`;
        await fsp.writeFile(tmp, JSON.stringify(this.items, null, 2));
        await fsp.rename(tmp, this.metaFile);
      })
      .catch((err) => console.error('No se pudo guardar uploads.json:', err));
    return this.queue;
  }

  list() {
    return this.items
      .slice()
      .sort((a, b) => String(b.uploadedAt).localeCompare(String(a.uploadedAt)));
  }

  get(id) {
    return this.items.find((i) => i.id === id) || null;
  }

  async add({ data, filename, contentType, uploader, caption }) {
    const id = `${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}`;
    const storedName = `${id}${safeExt(filename, contentType)}`;
    const clave = generarClaveBorrado();
    await fsp.writeFile(path.join(this.uploadsDir, storedName), data);
    const item = {
      id,
      storedName,
      originalName: sanitizeName(filename) || storedName,
      contentType: String(contentType || 'application/octet-stream'),
      size: data.length,
      uploader: String(uploader || '').trim().slice(0, 60),
      caption: String(caption || '').trim().slice(0, 300),
      uploadedAt: new Date().toISOString(),
      estado: 'pendiente', // pendiente | en_icloud
      hash: hashContenido(data),
      claveBorradoHash: hashClave(clave),
    };
    this.items.push(item);
    await this.persist();
    return { item, clave };
  }

  findByHash(hash) {
    return (hash && this.items.find((i) => i.hash === hash)) || null;
  }

  async setEstado(id, estado) {
    const item = this.get(id);
    if (!item) return null;
    item.estado = estado;
    await this.persist();
    return item;
  }

  async remove(id) {
    const item = this.get(id);
    if (!item) return false;
    this.items = this.items.filter((i) => i.id !== id);
    await fsp.unlink(path.join(this.uploadsDir, item.storedName)).catch(() => {});
    await this.persist();
    return true;
  }

  /** Ruta absoluta de un archivo subido; null si el nombre no es seguro o no existe. */
  filePath(storedName) {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(storedName) || storedName.includes('..')) return null;
    if (!this.items.some((i) => i.storedName === storedName)) return null;
    return path.join(this.uploadsDir, storedName);
  }
}
