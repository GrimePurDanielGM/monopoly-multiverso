import { describe, it, expect } from 'vitest';
import { normalizeCode, isValidCode } from './codes';

describe('codes', () => {
  it('normaliza a mayúsculas y sin espacios', () => {
    expect(normalizeCode('  ab c12 ')).toBe('ABC12');
  });
  it('valida longitud y alfabeto', () => {
    expect(isValidCode('ABC234')).toBe(true);
    expect(isValidCode('abc234')).toBe(true); // se normaliza antes
    expect(isValidCode('ABC23')).toBe(false); // demasiado corto
    expect(isValidCode('ABC23O')).toBe(false); // O no pertenece al alfabeto
    expect(isValidCode('ABC231')).toBe(false); // 1 no pertenece al alfabeto
  });
});
