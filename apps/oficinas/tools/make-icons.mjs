/* Genera los iconos PNG de la app dibujando la silueta de la planta.
   Uso: node apps/oficinas/tools/make-icons.mjs
   Sin dependencias: rasteriza a mano y codifica PNG con zlib de Node. */
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'icons');
mkdirSync(OUT, { recursive: true });

/* ---------- codificador PNG (RGBA 8 bits) ---------- */
let crcTable;
function crc32(buf) {
  if (!crcTable) {
    crcTable = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      crcTable[n] = c >>> 0;
    }
  }
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) crc = crcTable[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(w, h, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;  // profundidad
  ihdr[9] = 6;  // color RGBA
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0; // filtro none
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  return Buffer.concat([
    sig,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

/* ---------- geometría de la planta (mismas cotas que la app) ---------- */
const POLY = [[0, 0], [5.974, 0], [5.974, 6.106], [-0.796, 6.106]];
const MINX = -0.796, MAXY = 6.106;
const BW = 5.974 - MINX, BH = MAXY;
const STUDIO = { x0: 2.70, y0: 3.10, x1: 5.974, y1: 6.106 };
const hex = c => [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
const BG = hex('#10130f'), FLOOR = hex('#7fb069'), STUD = hex('#f2ecd9'),
      WALL = hex('#d8d2c4'), WIN = hex('#7fc8e8'), VOID = hex('#d99a4e');

function inPoly(x, y, pts) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const xi = pts[i][0], yi = pts[i][1], xj = pts[j][0], yj = pts[j][1];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function dSeg(px, py, ax, ay, bx, by) {
  const vx = bx - ax, vy = by - ay, wx = px - ax, wy = py - ay;
  const t = Math.max(0, Math.min(1, (wx * vx + wy * vy) / (vx * vx + vy * vy)));
  return Math.hypot(px - (ax + vx * t), py - (ay + vy * t));
}
function shade(x, y) {
  let c = BG;
  if (inPoly(x, y, POLY)) {
    c = FLOOR;
    if (x >= STUDIO.x0 && x <= STUDIO.x1 && y >= STUDIO.y0 && y <= STUDIO.y1) c = STUD;
  }
  if (dSeg(x, y, 0, 0, 5.974, 0) <= 0.17) c = WALL;               // muro sur
  if (dSeg(x, y, 5.974, 0, 5.974, 6.106) <= 0.17) c = WALL;       // muro este
  if (dSeg(x, y, 5.974, 6.106, -0.796, 6.106) <= 0.17) c = WALL;  // muro norte
  if (dSeg(x, y, 0.879, 0, 5.095, 0) <= 0.17) c = WIN;            // ventanal sur
  if (dSeg(x, y, 0, 0, -0.796, 6.106) <= 0.21) c = VOID;          // borde del vacío
  return c;
}

/* ---------- render con sobremuestreo 4×4 ---------- */
function render(size, frac, name) {
  const SS = 4;
  const sc = (size * frac) / Math.max(BW, BH);
  const ox = (size - BW * sc) / 2, oy = (size - BH * sc) / 2;
  const buf = Buffer.alloc(size * size * 4);
  for (let j = 0; j < size; j++) {
    for (let i = 0; i < size; i++) {
      let r = 0, g = 0, b = 0;
      for (let sj = 0; sj < SS; sj++) {
        for (let si = 0; si < SS; si++) {
          const px = i + (si + 0.5) / SS, py = j + (sj + 0.5) / SS;
          const x = MINX + (px - ox) / sc;
          const y = MAXY - (py - oy) / sc;  // norte arriba
          const c = shade(x, y);
          r += c[0]; g += c[1]; b += c[2];
        }
      }
      const k = (j * size + i) * 4, n = SS * SS;
      buf[k] = r / n; buf[k + 1] = g / n; buf[k + 2] = b / n; buf[k + 3] = 255;
    }
  }
  writeFileSync(join(OUT, name), png(size, size, buf));
  console.log('·', name);
}

render(180, 0.72, 'icon-180.png');
render(192, 0.72, 'icon-192.png');
render(512, 0.72, 'icon-512.png');
render(512, 0.54, 'icon-mask-512.png');  // zona segura maskable
console.log('Iconos generados en', OUT);
