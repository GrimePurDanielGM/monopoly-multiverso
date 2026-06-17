// Validación del contenido escaneado: acepta una URL del dominio permitido con ruta
// /j/{CODE}, o un código de 6 caracteres suelto. Normaliza (trim+upper). Rechaza el resto
// (QR de otras apps, dominios ajenos, formatos inválidos).
import { isValidCode, normalizeCode } from './codes';

export function parseScannedCode(raw: string, baseUrl: string): string | null {
  const text = raw.trim();
  if (!text) return null;

  // ¿Es una URL?
  let url: URL | null = null;
  try {
    url = new URL(text);
  } catch {
    url = null;
  }

  if (url) {
    let allowedHost = '';
    try {
      allowedHost = new URL(baseUrl).hostname;
    } catch {
      allowedHost = '';
    }
    if (allowedHost && url.hostname !== allowedHost) return null; // dominio no permitido
    const m = /^\/j\/([^/]+)\/?$/.exec(url.pathname);
    const seg = m?.[1];
    if (!seg) return null;
    const code = normalizeCode(decodeURIComponent(seg));
    return isValidCode(code) ? code : null;
  }

  // Código suelto
  const code = normalizeCode(text);
  return isValidCode(code) ? code : null;
}
