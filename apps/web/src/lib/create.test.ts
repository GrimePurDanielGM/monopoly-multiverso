import { describe, it, expect } from 'vitest';
import { isCreateReady } from './create';

const base = {
  gameName: 'Sábado noche',
  hostName: 'Daniel',
  pin: '482915',
  tokenIds: ['delorean', 'hoverboard'] as const,
};

describe('isCreateReady', () => {
  it('true cuando todo es válido, incluida una ficha del catálogo', () => {
    expect(isCreateReady({ ...base, tokenId: 'delorean' })).toBe(true);
  });
  it('false sin ficha (null o cadena vacía)', () => {
    expect(isCreateReady({ ...base, tokenId: null })).toBe(false);
    expect(isCreateReady({ ...base, tokenId: '' })).toBe(false);
  });
  it('false con ficha desconocida (no está en el catálogo)', () => {
    expect(isCreateReady({ ...base, tokenId: 'ficha_fantasma' })).toBe(false);
  });
  it('false con nombre/anfitrión/PIN inválidos', () => {
    expect(isCreateReady({ ...base, tokenId: 'delorean', gameName: 'ab' })).toBe(false);
    expect(isCreateReady({ ...base, tokenId: 'delorean', hostName: 'a' })).toBe(false);
    expect(isCreateReady({ ...base, tokenId: 'delorean', pin: '111111' })).toBe(false);
  });
});
