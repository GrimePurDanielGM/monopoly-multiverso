import { describe, it, expect } from 'vitest';
import { isValidGameCode, normalizeName, isValidPlayerName, isWeakPin, evaluateStart } from './index';

describe('isValidGameCode', () => {
  it('acepta 6 caracteres del alfabeto', () => expect(isValidGameCode('ABC234')).toBe(true));
  it('normaliza mayúsculas y espacios', () => expect(isValidGameCode(' abc234 ')).toBe(true));
  it('rechaza caracteres ambiguos', () => expect(isValidGameCode('ABCI23')).toBe(false));
  it('rechaza longitud incorrecta', () => expect(isValidGameCode('ABC23')).toBe(false));
});

describe('normalizeName (espejo del SQL)', () => {
  it('trim + colapsa espacios + minúsculas', () => expect(normalizeName('  Da  niel ')).toBe('da niel'));
  it('DANIEL y Daniel colisionan', () => expect(normalizeName('DANIEL')).toBe(normalizeName('daniel')));
});

describe('isValidPlayerName', () => {
  it('2..24', () => { expect(isValidPlayerName('Al')).toBe(true); expect(isValidPlayerName('A')).toBe(false); });
});

describe('isWeakPin', () => {
  it('rechaza no-6-dígitos', () => expect(isWeakPin('12a45')).toBe(true));
  it('rechaza seis iguales y 123456', () => { expect(isWeakPin('000000')).toBe(true); expect(isWeakPin('111111')).toBe(true); expect(isWeakPin('123456')).toBe(true); });
  it('acepta uno razonable', () => expect(isWeakPin('482915')).toBe(false));
});

describe('evaluateStart', () => {
  const ok = Array.from({ length: 6 }, (_, i) => ({ tokenId: `t${i}`, ready: true, name: `Jug ${i}`, kicked: false }));
  it('6 listos => canStart', () => expect(evaluateStart(ok, 6).canStart).toBe(true));
  it('<min => NOT_ENOUGH_PLAYERS', () => expect(evaluateStart(ok.slice(0, 5), 6).reasons).toContain('NOT_ENOUGH_PLAYERS'));
  it('ignora expulsados en el recuento', () => {
    const withKicked = [...ok, { tokenId: null, ready: false, name: 'X', kicked: true }];
    expect(evaluateStart(withKicked, 6).canStart).toBe(true);
  });
  it('sin ficha => PLAYER_WITHOUT_TOKEN', () => {
    const bad = [{ ...ok[0]!, tokenId: null }, ...ok.slice(1)];
    expect(evaluateStart(bad, 6).reasons).toContain('PLAYER_WITHOUT_TOKEN');
  });
});
