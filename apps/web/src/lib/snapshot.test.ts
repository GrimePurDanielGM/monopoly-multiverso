import { describe, it, expect } from 'vitest';
import { parseSnapshot, hasForbiddenKey } from './snapshot';

const FK = ['auth', 'uid'].join('_'); // clave interna prohibida, sin literal en el archivo

const valid = {
  game: {
    id: 'g1', code: 'ABC234', name: 'Demo', status: 'lobby', version: 0,
    started_at: null, cancelled_at: null, host_public_ref: 'P-1',
    config: { min_players: 6, max_players: 16, initial_money: 3000, token_catalog_version: 0, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false, allow_trade_built_properties: false, parking_mode: 'pot' },
  },
  players: [{ public_ref: 'P-1', name: 'Host', token_id: 'delorean', status: 'joined', last_seen_at: '2026-06-17T00:00:00Z' }],
  me: { public_ref: 'P-1', is_host: true, join_status: 'joined', token_id: 'delorean', membership: 'active' },
  requests: [],
  counts: { player_count: 1, ready_count: 0, min_players: 6, max_players: 16 },
};

describe('parseSnapshot', () => {
  it('acepta un snapshot válido y lo tipa', () => {
    const r = parseSnapshot(valid);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.data.game.code).toBe('ABC234');
      expect(r.data.players).toHaveLength(1);
      expect(r.data.me.is_host).toBe(true);
    }
  });
  it('rechaza un snapshot incompleto (sin me)', () => {
    const sinMe: Record<string, unknown> = { ...valid };
    delete sinMe.me;
    expect(parseSnapshot(sinMe).ok).toBe(false);
  });
  it('rechaza tipos incorrectos (counts string)', () => {
    const malo = { ...valid, counts: { ...valid.counts, player_count: '1' } };
    expect(parseSnapshot(malo).ok).toBe(false);
  });
  it('rechaza status de partida desconocido', () => {
    const malo = { ...valid, game: { ...valid.game, status: 'paused' } };
    expect(parseSnapshot(malo).ok).toBe(false);
  });
  it('rechaza un snapshot con la clave interna prohibida', () => {
    const malo = { ...valid, players: [{ ...valid.players[0], [FK]: 'x' }] };
    const r = parseSnapshot(malo);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toMatch(/prohibida/);
  });
});

describe('hasForbiddenKey', () => {
  it('detecta la clave prohibida anidada', () => {
    expect(hasForbiddenKey({ a: { b: [{ [FK]: 1 }] } })).toBe(true);
  });
  it('no marca objetos limpios', () => {
    expect(hasForbiddenKey(valid)).toBe(false);
  });
});
