import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Guard: el cliente NUNCA emite por el canal (ni broadcast oficial ni nada). Los eventos
// oficiales los emite el servidor (triggers). Excluimos los archivos de test.
function walk(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (/\.(ts|tsx)$/.test(name) && !/\.test\./.test(name) && !/integration/.test(name)) out.push(p);
  }
  return out;
}

describe('seguridad Realtime', () => {
  it('el código del cliente no llama a channel.send (no emite Broadcast)', () => {
    const files = walk(join(process.cwd(), 'src'));
    const offenders = files.filter((f) => /\.send\s*\(/.test(readFileSync(f, 'utf8')));
    expect(offenders).toEqual([]);
  });
});
