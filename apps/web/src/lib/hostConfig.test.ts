import { describe, it, expect } from 'vitest';
import { configErrors, isConfigValid } from './hostConfig';

const base = { name: 'Mi sala', minPlayers: 6, maxPlayers: 16, initialMoney: 3000 };

describe('configErrors', () => {
  it('válida por defecto', () => expect(isConfigValid(base, 6)).toBe(true));
  it('permite mínimo 2 (configurable para pruebas)', () =>
    expect(isConfigValid({ ...base, minPlayers: 2 }, 2)).toBe(true));
  it('rechaza mínimo inferior a 2', () =>
    expect(configErrors({ ...base, minPlayers: 1 }, 6).length).toBeGreaterThan(0));
  it('rechaza máximo superior a 16', () =>
    expect(configErrors({ ...base, maxPlayers: 17 }, 6).length).toBeGreaterThan(0));
  it('rechaza mínimo mayor que máximo', () =>
    expect(configErrors({ ...base, minPlayers: 10, maxPlayers: 8 }, 6).length).toBeGreaterThan(0));
  it('rechaza máximo inferior al número actual de jugadores', () =>
    expect(configErrors({ ...base, maxPlayers: 8 }, 10).length).toBeGreaterThan(0));
  it('rechaza nombre fuera de 3–40', () => expect(configErrors({ ...base, name: 'ab' }, 6).length).toBeGreaterThan(0));
  it('rechaza dinero inicial no positivo', () => expect(configErrors({ ...base, initialMoney: 0 }, 6).length).toBeGreaterThan(0));
});
