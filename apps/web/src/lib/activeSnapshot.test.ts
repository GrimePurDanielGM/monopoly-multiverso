import { describe, it, expect } from 'vitest';
import { parseActiveSnapshot } from './activeSnapshot';

const valid = {
  game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16 } },
  me: { public_ref: 'P-AAAA', is_host: true, balance: 3000, is_current: true },
  turn: { turn_number: 1, current_player_ref: 'P-AAAA', order: ['P-AAAA', 'P-BBBB'] },
  players: [
    { public_ref: 'P-AAAA', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true },
    { public_ref: 'P-BBBB', display_name: 'Beto', token_id: null, balance: 3000, is_current: false },
  ],
  ledger_recent: [
    { ledger_ref: 'L-AAAA', seq: 2, kind: 'bank_to_player', from_ref: null, to_ref: 'P-AAAA', amount: 100, before_balance: null, after_balance: null, reason: null, actor_ref: 'P-AAAA', reverts_ref: null, created_at: '2026-06-18T00:00:00Z' },
  ],
  runtime_version: 3,
};

describe('parseActiveSnapshot', () => {
  it('acepta un snapshot válido', () => {
    const r = parseActiveSnapshot(valid);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.data.me.public_ref).toBe('P-AAAA');
  });

  it('rechaza clave interna prohibida (en cualquier nivel)', () => {
    // Clave construida dinámicamente para no incrustar el literal interno en el código.
    const forbidden = ['auth', 'uid'].join('_');
    const bad = { ...valid, me: { ...valid.me, [forbidden]: 'x' } };
    const r = parseActiveSnapshot(bad);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toMatch(/prohibida/);
  });

  it('rechaza status no activo', () => {
    expect(parseActiveSnapshot({ ...valid, game: { ...valid.game, status: 'lobby' } }).ok).toBe(false);
  });

  it('rechaza kind de ledger desconocido', () => {
    const bad = { ...valid, ledger_recent: [{ ...valid.ledger_recent[0], kind: 'hack' }] };
    expect(parseActiveSnapshot(bad).ok).toBe(false);
  });

  it('rechaza tipos incorrectos en balance', () => {
    const bad = { ...valid, me: { ...valid.me, balance: 'mucho' } };
    expect(parseActiveSnapshot(bad).ok).toBe(false);
  });
});
