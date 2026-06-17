import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Guard de seguridad: el identificador interno de sesión (la columna privada de players)
// no debe aparecer en NINGÚN archivo del cliente. Construimos el patrón dinámicamente
// para que este propio test no se detecte a sí mismo como infractor.
const NEEDLE = ['auth', 'uid'].join('_');

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (/\.(ts|tsx)$/.test(name)) out.push(p);
  }
  return out;
}

describe('seguridad del cliente', () => {
  it('ningún archivo de apps/web/src expone el identificador interno de sesión', () => {
    const files = walk(join(process.cwd(), 'src'));
    const offenders = files.filter((f) => readFileSync(f, 'utf8').includes(NEEDLE));
    expect(offenders).toEqual([]);
  });
});
