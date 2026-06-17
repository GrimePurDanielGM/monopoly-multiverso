import { describe, it, expect } from 'vitest';
import { isValidPin } from './pin';

describe('isValidPin', () => {
  it('acepta 6 dígitos no triviales', () => {
    expect(isValidPin('482915')).toBe(true);
  });
  it('rechaza longitud incorrecta o no numérico', () => {
    expect(isValidPin('12345')).toBe(false);
    expect(isValidPin('1234567')).toBe(false);
    expect(isValidPin('48a915')).toBe(false);
  });
  it('rechaza PIN triviales', () => {
    expect(isValidPin('111111')).toBe(false);
    expect(isValidPin('123456')).toBe(false);
  });
});
