import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Guard: el código del cliente no contiene claves de servidor ni secretos conocidos.
// Patrones construidos dinámicamente para no detectarse a sí mismo; se excluyen los tests.
const NEEDLES = [['SERVICE', 'ROLE'].join('_'), ['HOST', 'PIN', 'PEPPER'].join('_'), ['sb', 'secret', ''].join('_')];

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (/\.(ts|tsx)$/.test(name) && !/\.test\./.test(name)) out.push(p);
  }
  return out;
}

describe('seguridad: sin secretos en el código cliente', () => {
  it('no aparecen claves de servidor ni secretos conocidos en apps/web/src', () => {
    const files = walk(join(process.cwd(), 'src'));
    const offenders: string[] = [];
    for (const f of files) {
      const content = readFileSync(f, 'utf8');
      for (const n of NEEDLES) if (content.includes(n)) offenders.push(`${f}: ${n}`);
    }
    expect(offenders).toEqual([]);
  });
});
