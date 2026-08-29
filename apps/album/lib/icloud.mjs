// Cliente del API público de los álbumes compartidos de iCloud.
// No es un API documentado oficialmente, pero es el que usa la propia web
// pública de Apple (icloud.com/sharedalbum) y lleva años estable:
//
//   POST https://pXX-sharedstreams.icloud.com/{token}/sharedstreams/webstream
//        body: {"streamCtag": null}            → metadatos del álbum y sus fotos
//   POST https://pXX-sharedstreams.icloud.com/{token}/sharedstreams/webasseturls
//        body: {"photoGuids": [...]}           → URLs firmadas (caducan en ~3 h)
//
// La partición pXX se deriva del token; si no coincide, iCloud responde
// con estado 330 e indica el host correcto en la cabecera X-Apple-MMe-Host.

const BASE62 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

function base62ToInt(str) {
  let n = 0;
  for (const ch of str) {
    const v = BASE62.indexOf(ch);
    if (v < 0) return NaN;
    n = n * 62 + v;
  }
  return n;
}

/** Extrae el token de un enlace tipo https://www.icloud.com/sharedalbum/#B2PGg… */
export function tokenFromUrl(urlOrToken) {
  const s = String(urlOrToken || '').trim();
  const m = s.match(/#!?([A-Za-z0-9]+)/) || s.match(/sharedalbum\/([A-Za-z0-9]+)/);
  return m ? m[1] : s;
}

export function partitionFromToken(token) {
  const n = token[0] === 'A' ? base62ToInt(token[1]) : base62ToInt(token.slice(1, 3));
  return Number.isFinite(n) && n > 0 ? n : 1;
}

export class SharedAlbum {
  constructor(token, { fetchImpl, timeoutMs = 25000 } = {}) {
    this.token = token;
    this.fetchImpl = fetchImpl || globalThis.fetch;
    this.timeoutMs = timeoutMs;
    this.host = `p${String(partitionFromToken(token)).padStart(2, '0')}-sharedstreams.icloud.com`;
  }

  async apiPost(path, body, redirected = false) {
    const url = `https://${this.host}/${this.token}/sharedstreams/${path}`;
    const res = await this.fetchImpl(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'text/plain',
        Origin: 'https://www.icloud.com',
        'User-Agent': 'Mozilla/5.0',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (res.status === 330 && !redirected) {
      // El álbum vive en otra partición: iCloud nos dice cuál.
      let next = res.headers.get('x-apple-mme-host');
      if (!next) {
        const data = await res.json().catch(() => ({}));
        next = data['X-Apple-MMe-Host'];
      }
      if (next) {
        this.host = next;
        return this.apiPost(path, body, true);
      }
    }
    if (!res.ok) throw new Error(`iCloud respondió ${res.status} en ${path}`);
    return res.json();
  }

  getStream() {
    return this.apiPost('webstream', { streamCtag: null });
  }

  /** Devuelve Map(checksum → {url, filename, expiry}) para los GUID pedidos. */
  async getAssetUrls(photoGuids) {
    const map = new Map();
    for (let i = 0; i < photoGuids.length; i += 40) {
      const chunk = photoGuids.slice(i, i + 40);
      const data = await this.apiPost('webasseturls', { photoGuids: chunk });
      for (const [checksum, item] of Object.entries(data.items || {})) {
        if (!item || !item.url_location || !item.url_path) continue;
        const rawName = String(item.url_path).split('?')[0].split('/').pop() || '';
        let filename = rawName;
        try {
          filename = decodeURIComponent(rawName);
        } catch {
          // nombre con escapes raros: lo dejamos tal cual
        }
        map.set(checksum, {
          url: `https://${item.url_location}${item.url_path}`,
          filename,
          expiry: item.url_expiry || null,
        });
      }
    }
    return map;
  }
}

/**
 * Normaliza una foto del webstream a lo que necesita la interfaz.
 * Las derivadas con clave numérica son versiones de la imagen (clave ≈ ancho);
 * los vídeos añaden derivadas no numéricas (p. ej. "PosterFrame", "360p", "720p").
 */
export function buildPhoto(raw, urlFor) {
  const entries = Object.entries(raw.derivatives || {});
  const images = entries
    .filter(([k]) => /^\d+$/.test(k))
    .map(([k, d]) => ({ size: Number(k), checksum: d.checksum, url: urlFor(d.checksum) }))
    .filter((d) => d.url)
    .sort((a, b) => a.size - b.size);

  const isVideo = String(raw.mediaAssetType || '').toLowerCase() === 'video';
  let posterUrl = null;
  let video = null;
  if (isVideo) {
    const extra = entries.filter(([k]) => !/^\d+$/.test(k));
    const poster = extra.find(([k]) => /poster/i.test(k));
    if (poster) posterUrl = urlFor(poster[1].checksum);
    const candidates = extra
      .filter(([k]) => !/poster/i.test(k))
      .map(([, d]) => ({ bytes: Number(d.fileSize) || 0, checksum: d.checksum, url: urlFor(d.checksum) }))
      .filter((d) => d.url)
      .sort((a, b) => a.bytes - b.bytes);
    if (candidates.length) video = candidates[candidates.length - 1];
  }

  const thumb = images.find((d) => d.size >= 320) || images[images.length - 1] || null;
  const full = images[images.length - 1] || null;
  if (!thumb && !posterUrl && !video) return null;

  const downloadChecksum = isVideo && video ? video.checksum : full ? full.checksum : thumb ? thumb.checksum : null;
  return {
    guid: raw.photoGuid,
    caption: raw.caption || '',
    contributor:
      raw.contributorFullName ||
      [raw.contributorFirstName, raw.contributorLastName].filter(Boolean).join(' ') ||
      '',
    dateCreated: raw.dateCreated || raw.batchDateCreated || null,
    width: Number(raw.width) || null,
    height: Number(raw.height) || null,
    isVideo,
    thumbUrl: thumb ? thumb.url : posterUrl,
    fullUrl: full ? full.url : posterUrl,
    posterUrl: posterUrl || (thumb ? thumb.url : null),
    videoUrl: video ? video.url : null,
    downloadChecksum,
  };
}

/** Lee el álbum completo: metadatos + fotos con sus URLs firmadas. */
export async function fetchAlbum(album) {
  const stream = await album.getStream();
  const rawPhotos = stream.photos || [];
  const assetMap = await album.getAssetUrls(rawPhotos.map((p) => p.photoGuid));
  const urlFor = (checksum) => assetMap.get(checksum)?.url || null;
  const photos = rawPhotos.map((p) => buildPhoto(p, urlFor)).filter(Boolean);
  for (const photo of photos) {
    photo.filename = assetMap.get(photo.downloadChecksum)?.filename || null;
  }
  // Más recientes primero: es lo que la familia quiere ver al abrir la web.
  photos.sort((a, b) => String(b.dateCreated || '').localeCompare(String(a.dateCreated || '')));
  return {
    streamName: stream.streamName || 'Álbum compartido',
    owner: [stream.userFirstName, stream.userLastName].filter(Boolean).join(' '),
    streamCtag: stream.streamCtag || null,
    photos,
    assetMap,
  };
}
