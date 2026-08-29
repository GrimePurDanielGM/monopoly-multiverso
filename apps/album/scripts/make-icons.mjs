// Genera los iconos PNG de la PWA sin dependencias (codificador PNG propio).
// Uso:  node scripts/make-icons.mjs

import zlib from 'node:zlib';
import path from 'node:path';
import { promises as fsp } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SALIDA = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'public', 'icons');

// ------------------------------------------------------------- codificador PNG
let tablaCrc;
function crc32(buf) {
  if (!tablaCrc) {
    tablaCrc = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      tablaCrc[n] = c;
    }
  }
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = tablaCrc[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(tipo, datos) {
  const t = Buffer.from(tipo, 'ascii');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(datos.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([t, datos])));
  return Buffer.concat([len, t, datos, crc]);
}

function png(ancho, alto, rgba) {
  const firma = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(ancho, 0);
  ihdr.writeUInt32BE(alto, 4);
  ihdr[8] = 8; // bits por canal
  ihdr[9] = 6; // RGBA
  const stride = ancho * 4;
  const crudo = Buffer.alloc((stride + 1) * alto);
  for (let y = 0; y < alto; y++) {
    rgba.copy(crudo, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  return Buffer.concat([
    firma,
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(crudo, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ----------------------------------------------------------------- dibujo
const hex = (c) => [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
const AZUL = hex('#4f8ef7');
const VIOLETA = hex('#8b5cf6');
const BLANCO = hex('#ffffff');
const CIELO = hex('#bfdcff');
const SOL = hex('#ffd166');
const MONTE = hex('#2b4d8f');

function dentroRedondeado(x, y, x0, y0, x1, y1, r) {
  if (x < x0 || x > x1 || y < y0 || y > y1) return false;
  const cx = Math.max(x0 + r, Math.min(x1 - r, x));
  const cy = Math.max(y0 + r, Math.min(y1 - r, y));
  return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
}

// Color del icono en coordenadas normalizadas [0,1]; escala = margen del motivo.
function colorPixel(u, v, { esquinas, margen }) {
  // fondo transparente fuera de las esquinas redondeadas (icono normal)
  if (esquinas && !dentroRedondeado(u, v, 0, 0, 1, 1, 0.22)) return [0, 0, 0, 0];

  // degradado diagonal de fondo
  const t = (u + v) / 2;
  let col = [
    AZUL[0] + (VIOLETA[0] - AZUL[0]) * t,
    AZUL[1] + (VIOLETA[1] - AZUL[1]) * t,
    AZUL[2] + (VIOLETA[2] - AZUL[2]) * t,
  ];

  // "foto" blanca con paisaje dentro, centrada, tamaño según el margen
  const a = margen;
  const b = 1 - margen;
  if (dentroRedondeado(u, v, a, a, b, b, 0.06)) col = BLANCO;
  const borde = 0.055 * (b - a);
  const ia = a + borde;
  const ib = b - borde;
  if (u > ia && u < ib && v > ia && v < ib) {
    col = CIELO;
    // sol arriba a la derecha
    const dx = u - (ia + 0.72 * (ib - ia));
    const dy = v - (ia + 0.24 * (ib - ia));
    if (dx * dx + dy * dy < (0.11 * (ib - ia)) ** 2) col = SOL;
    // montañas: dos picos triangulares
    const w = ib - ia;
    const alturaMonte = (cx, half, px) => 1 - Math.abs(px - cx) / half;
    const py = (v - ia) / w;
    const px = (u - ia) / w;
    const m1 = alturaMonte(0.34, 0.36, px); // pico grande
    const m2 = alturaMonte(0.72, 0.3, px); // pico pequeño
    const alto1 = 0.52 * Math.max(0, m1);
    const alto2 = 0.38 * Math.max(0, m2);
    if (py > 1 - Math.max(alto1, alto2)) col = MONTE;
  }
  return [col[0], col[1], col[2], 255];
}

function render(tam, opciones) {
  const ss = 2; // sobremuestreo 2x para suavizar bordes
  const grande = tam * ss;
  const rgba = Buffer.alloc(tam * tam * 4);
  for (let y = 0; y < tam; y++) {
    for (let x = 0; x < tam; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < ss; sy++) {
        for (let sx = 0; sx < ss; sx++) {
          const [pr, pg, pb, pa] = colorPixel(
            (x * ss + sx + 0.5) / grande,
            (y * ss + sy + 0.5) / grande,
            opciones,
          );
          r += pr * (pa / 255);
          g += pg * (pa / 255);
          b += pb * (pa / 255);
          a += pa;
        }
      }
      const n = ss * ss;
      const alfa = a / n;
      const i = (y * tam + x) * 4;
      const factor = alfa > 0 ? 255 / alfa : 0;
      rgba[i] = Math.round((r / n) * factor);
      rgba[i + 1] = Math.round((g / n) * factor);
      rgba[i + 2] = Math.round((b / n) * factor);
      rgba[i + 3] = Math.round(alfa);
    }
  }
  return png(tam, tam, rgba);
}

await fsp.mkdir(SALIDA, { recursive: true });
await fsp.writeFile(path.join(SALIDA, 'icon-192.png'), render(192, { esquinas: true, margen: 0.2 }));
await fsp.writeFile(path.join(SALIDA, 'icon-512.png'), render(512, { esquinas: true, margen: 0.2 }));
// El icono "maskable" ocupa todo el lienzo y deja el motivo en la zona segura central
await fsp.writeFile(path.join(SALIDA, 'maskable-512.png'), render(512, { esquinas: false, margen: 0.28 }));
console.log(`Iconos generados en ${SALIDA}`);
