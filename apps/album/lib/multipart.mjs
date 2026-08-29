// Analizador mínimo de multipart/form-data, suficiente para el FormData
// que envían los navegadores (y curl -F). Sin dependencias.

export function boundaryFromContentType(contentType) {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType || '');
  return m ? (m[1] || m[2]).trim() : null;
}

/**
 * @param {Buffer} body cuerpo completo de la petición
 * @param {string} boundary delimitador (sin los "--" iniciales)
 * @returns {{fields: Record<string,string>, files: Array<{field:string|null, filename:string, contentType:string, data:Buffer}>}}
 */
export function parseMultipart(body, boundary) {
  const delim = Buffer.from(`--${boundary}`);
  const headerSep = Buffer.from('\r\n\r\n');
  const fields = {};
  const files = [];

  let pos = body.indexOf(delim);
  if (pos === -1) throw new Error('multipart: no se encontró el delimitador');
  pos += delim.length;

  for (;;) {
    // "--" tras el delimitador marca el final del cuerpo
    if (body[pos] === 0x2d && body[pos + 1] === 0x2d) break;
    if (body[pos] === 0x0d && body[pos + 1] === 0x0a) pos += 2;

    const headersEnd = body.indexOf(headerSep, pos);
    if (headersEnd === -1) break;
    const rawHeaders = body.slice(pos, headersEnd).toString('utf8');

    const next = body.indexOf(delim, headersEnd + headerSep.length);
    if (next === -1) break;
    // El contenido termina justo antes del CRLF que precede al siguiente delimitador
    const content = body.slice(headersEnd + headerSep.length, Math.max(headersEnd + headerSep.length, next - 2));

    const disposition = /content-disposition:[^\r\n]*/i.exec(rawHeaders)?.[0] || '';
    const name = /\bname="([^"]*)"/i.exec(disposition)?.[1] ?? null;
    const filename = /\bfilename="([^"]*)"/i.exec(disposition)?.[1] ?? null;
    const contentType = /content-type:\s*([^\r\n;]+)/i.exec(rawHeaders)?.[1]?.trim() || null;

    if (filename !== null && filename !== '') {
      files.push({
        field: name,
        filename,
        contentType: contentType || 'application/octet-stream',
        data: content,
      });
    } else if (name) {
      fields[name] = content.toString('utf8');
    }
    pos = next + delim.length;
  }

  return { fields, files };
}
