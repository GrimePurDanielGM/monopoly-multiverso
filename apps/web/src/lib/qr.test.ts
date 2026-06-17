import { describe, it, expect } from 'vitest';
import { parseScannedCode } from './qr';

const BASE = 'https://monopoly-multiverso-web.vercel.app';

describe('parseScannedCode', () => {
  it('acepta una URL del dominio permitido con /j/CODE (normaliza)', () => {
    expect(parseScannedCode(`${BASE}/j/ABC234`, BASE)).toBe('ABC234');
    expect(parseScannedCode(`${BASE}/j/abc234`, BASE)).toBe('ABC234');
    expect(parseScannedCode(`  ${BASE}/j/abc234  `, BASE)).toBe('ABC234');
  });
  it('rechaza dominios ajenos', () => {
    expect(parseScannedCode('https://malicioso.example/j/ABC234', BASE)).toBeNull();
  });
  it('acepta un código suelto válido', () => {
    expect(parseScannedCode('  abc234 ', BASE)).toBe('ABC234');
  });
  it('rechaza QR de otras apps / texto cualquiera / vacío', () => {
    expect(parseScannedCode('https://otra.app/foo', BASE)).toBeNull();
    expect(parseScannedCode('hola mundo', BASE)).toBeNull();
    expect(parseScannedCode('', BASE)).toBeNull();
  });
  it('rechaza código inválido dentro de la URL', () => {
    expect(parseScannedCode(`${BASE}/j/ABC23O`, BASE)).toBeNull(); // O no pertenece al alfabeto
    expect(parseScannedCode(`${BASE}/j/AB`, BASE)).toBeNull(); // demasiado corto
  });
});
