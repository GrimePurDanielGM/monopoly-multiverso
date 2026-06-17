import { describe, it, expect } from 'vitest';
import { buildJoinLink } from './config';

describe('config.buildJoinLink', () => {
  it('construye el enlace /j/CODE', () => {
    expect(buildJoinLink('https://monopoly-multiverso-web.vercel.app', 'ABC234')).toBe(
      'https://monopoly-multiverso-web.vercel.app/j/ABC234',
    );
  });
  it('elimina barras finales de la base', () => {
    expect(buildJoinLink('https://x.app///', 'ABC234')).toBe('https://x.app/j/ABC234');
  });
});
