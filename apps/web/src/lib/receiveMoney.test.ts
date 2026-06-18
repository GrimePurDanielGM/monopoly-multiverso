import { describe, it, expect, beforeEach } from 'vitest';
import { computeReceive, initialReceiveTracker, type ReceiveTracker } from './receiveMoney';
import { isCashSoundEnabled, setCashSoundEnabled, playCashSound } from './cashSound';
import type { ActiveSnapshot } from './activeSnapshot';

// Snapshot mínimo: solo importan me.balance, me.is_spectator y runtime_version.
function snap(balance: number, version: number, spectator = false): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200 } },
    me: { public_ref: 'P-1', is_host: false, balance, is_current: false, is_spectator: spectator },
    turn: { turn_number: 1, current_player_ref: 'P-2', order: ['P-1', 'P-2'] },
    players: [], ledger_recent: [], properties: [], auctions: [], purchase_requests: [],
    leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [], spaces: [], positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running', control: { paused_by_ref: null, finished_by_ref: null, reason: null },
    runtime_version: version,
  };
}

describe('computeReceive', () => {
  it('1) no suena en el primer snapshot (solo fija la línea base)', () => {
    const r = computeReceive(initialReceiveTracker, snap(3000, 5));
    expect(r.play).toBe(false);
    expect(r.next).toEqual({ lastBalance: 3000, lastVersion: 5 });
  });

  it('2) suena si mi saldo aumenta, con el delta', () => {
    const prev: ReceiveTracker = { lastBalance: 3000, lastVersion: 5 };
    const r = computeReceive(prev, snap(3500, 6));
    expect(r.play).toBe(true);
    expect(r.delta).toBe(500);
  });

  it('3) no suena si mi saldo baja', () => {
    const prev: ReceiveTracker = { lastBalance: 3000, lastVersion: 5 };
    const r = computeReceive(prev, snap(2800, 6));
    expect(r.play).toBe(false);
    expect(r.delta).toBe(0);
  });

  it('4) no suena si mi saldo no cambia (p. ej. aumenta el de otro jugador)', () => {
    const prev: ReceiveTracker = { lastBalance: 3000, lastVersion: 5 };
    const r = computeReceive(prev, snap(3000, 6));
    expect(r.play).toBe(false);
  });

  it('5) no suena dos veces por el mismo runtime_version', () => {
    const prev: ReceiveTracker = { lastBalance: 3000, lastVersion: 6 };
    const r = computeReceive(prev, snap(3500, 6)); // misma versión ya procesada
    expect(r.play).toBe(false);
    expect(r.next).toBe(prev); // no altera la línea base
  });

  it('no suena para un espectador (en bancarrota)', () => {
    const prev: ReceiveTracker = { lastBalance: 0, lastVersion: 5 };
    const r = computeReceive(prev, snap(100, 6, true));
    expect(r.play).toBe(false);
  });
});

describe('cashSound — preferencia y robustez', () => {
  beforeEach(() => { try { window.localStorage.clear(); } catch { /* */ } });

  it('por defecto activado; se puede desactivar (localStorage)', () => {
    expect(isCashSoundEnabled()).toBe(true);
    setCashSoundEnabled(false);
    expect(isCashSoundEnabled()).toBe(false);
    setCashSoundEnabled(true);
    expect(isCashSoundEnabled()).toBe(true);
  });

  it('7) no rompe si no hay Web Audio / play es rechazado (falla en silencio)', () => {
    expect(() => playCashSound()).not.toThrow();
  });
});
