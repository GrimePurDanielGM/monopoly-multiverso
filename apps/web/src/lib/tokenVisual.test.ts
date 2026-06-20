import { describe, it, expect } from 'vitest';
import { tokenEmoji } from './tokenVisual';

describe('tokenEmoji (item 1 — nunca se muestra el slug en inglés)', () => {
  it('mapea slugs conocidos a emoji', () => {
    expect(tokenEmoji('car')).toBe('🚗');
    expect(tokenEmoji('cat')).toBe('🐱');
    expect(tokenEmoji('penguin')).toBe('🐧');
    expect(tokenEmoji('hat-cowboy')).toBe('🤠');
  });
  it('un slug desconocido cae a 🎲 (nunca devuelve el slug)', () => {
    expect(tokenEmoji('algo-raro')).toBe('🎲');
    expect(tokenEmoji('')).toBe('🎲');
  });
});
