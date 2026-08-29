// Empaquetador ZIP sin compresión (método STORE) y sin dependencias.
// Para fotos JPEG es lo ideal: no re-comprime (no ganaría nada) y es rapidísimo.
// Límites clásicos de ZIP (sin ZIP64): < 4 GB y < 65535 entradas — de sobra.

let tablaCrc = null;

export function crc32(datos) {
  if (!tablaCrc) {
    tablaCrc = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      tablaCrc[n] = c;
    }
  }
  let c = -1;
  for (let i = 0; i < datos.length; i++) c = tablaCrc[(c ^ datos[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function fechaDos(fecha = new Date()) {
  const f = ((fecha.getFullYear() - 1980) << 9) | ((fecha.getMonth() + 1) << 5) | fecha.getDate();
  const h = (fecha.getHours() << 11) | (fecha.getMinutes() << 5) | (fecha.getSeconds() >> 1);
  return { f, h };
}

/**
 * @param {Array<{nombre: string, datos: Uint8Array}>} entradas
 * @returns {Uint8Array} archivo .zip completo
 */
export function crearZip(entradas) {
  const codificador = new TextEncoder();
  const { f, h } = fechaDos();
  const partes = [];
  const centrales = [];
  let offset = 0;

  for (const entrada of entradas) {
    const nombre = codificador.encode(entrada.nombre);
    const datos = entrada.datos;
    const crc = crc32(datos);

    const local = new DataView(new ArrayBuffer(30));
    local.setUint32(0, 0x04034b50, true); // firma de cabecera local
    local.setUint16(4, 20, true); // versión necesaria
    local.setUint16(6, 0x0800, true); // nombres en UTF-8
    local.setUint16(8, 0, true); // método STORE
    local.setUint16(10, h, true);
    local.setUint16(12, f, true);
    local.setUint32(14, crc, true);
    local.setUint32(18, datos.length, true);
    local.setUint32(22, datos.length, true);
    local.setUint16(26, nombre.length, true);
    local.setUint16(28, 0, true);
    partes.push(new Uint8Array(local.buffer), nombre, datos);

    const central = new DataView(new ArrayBuffer(46));
    central.setUint32(0, 0x02014b50, true); // firma del directorio central
    central.setUint16(4, 20, true);
    central.setUint16(6, 20, true);
    central.setUint16(8, 0x0800, true);
    central.setUint16(10, 0, true);
    central.setUint16(12, h, true);
    central.setUint16(14, f, true);
    central.setUint32(16, crc, true);
    central.setUint32(20, datos.length, true);
    central.setUint32(24, datos.length, true);
    central.setUint16(28, nombre.length, true);
    central.setUint32(42, offset, true); // offset de la cabecera local
    centrales.push(new Uint8Array(central.buffer), nombre);

    offset += 30 + nombre.length + datos.length;
  }

  let lenCentral = 0;
  for (const c of centrales) lenCentral += c.length;

  const fin = new DataView(new ArrayBuffer(22));
  fin.setUint32(0, 0x06054b50, true); // fin del directorio central
  fin.setUint16(8, entradas.length, true);
  fin.setUint16(10, entradas.length, true);
  fin.setUint32(12, lenCentral, true);
  fin.setUint32(16, offset, true);

  const salida = new Uint8Array(offset + lenCentral + 22);
  let p = 0;
  for (const parte of partes) { salida.set(parte, p); p += parte.length; }
  for (const parte of centrales) { salida.set(parte, p); p += parte.length; }
  salida.set(new Uint8Array(fin.buffer), p);
  return salida;
}
