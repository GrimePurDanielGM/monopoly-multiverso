// Copia la web estática del álbum familiar dentro del build de la web del juego,
// para servirla en /album desde el mismo proyecto de Vercel.
// Se ejecuta tras `vite build` (ver buildCommand en vercel.json), de modo que el
// service worker del juego NO precachea estos archivos (su manifest ya está generado).

import { promises as fsp } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const origen = path.join(raiz, 'apps', 'album', 'public');
const destino = path.join(raiz, 'apps', 'web', 'dist', 'album');

await fsp.rm(destino, { recursive: true, force: true });
await fsp.cp(origen, destino, { recursive: true });
console.log(`Álbum copiado a ${path.relative(raiz, destino)}`);
