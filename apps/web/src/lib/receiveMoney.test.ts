import { describe, it, expect, beforeEach } from 'vitest';
import { computeReceive, describeReceive, initialReceiveTracker, type ReceiveTracker } from './receiveMoney';
import { isCashSoundEnabled, setCashSoundEnabled, playCashSound } from './cashSound';
import type { ActiveSnapshot, LedgerEntry, ActivePlayer } from './activeSnapshot';

// Snapshot mínimo: solo importan me.balance, me.is_spectator y runtime_version.
function snap(balance: number, version: number, spectator = false): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200 } },
    me: { public_ref: 'P-1', is_host: false, balance, is_current: false, is_spectator: spectator },
    turn: { turn_number: 1, current_player_ref: 'P-2', order: ['P-1', 'P-2'] },
    players: [], ledger_recent: [], properties: [], auctions: [], purchase_requests: [],
    leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [], spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null, card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null, last_global_event: null, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
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

describe('describeReceive — mensaje del banner derivado del ledger', () => {
  const led = (over: Partial<LedgerEntry>): LedgerEntry => ({
    ledger_ref: 'L-1', seq: 1, kind: 'bank_to_player', from_ref: null, to_ref: 'P-1', amount: 200,
    before_balance: null, after_balance: null, reason: null, actor_ref: null, reverts_ref: null,
    created_at: '2026-06-19T00:00:00Z', ...over,
  });
  const withLedger = (entries: LedgerEntry[], players: ActivePlayer[] = []): ActiveSnapshot => ({
    ...snap(3500, 6), ledger_recent: entries, players,
  });
  const beto: ActivePlayer = { public_ref: 'P-2', display_name: 'Beto', token_id: null, balance: 0, is_current: false, status: 'active' };

  it('paso por salida → "al pasar por salida"', () => {
    const m = describeReceive(withLedger([led({ kind: 'pass_start_bonus', from_ref: null, to_ref: 'P-1', amount: 200 })]), 200);
    expect(m).toMatch(/al pasar por salida/i);
    expect(m).toContain('200');
  });

  it('alquiler de otro jugador → "{nombre} te ha pagado … de alquiler"', () => {
    const m = describeReceive(withLedger([led({ kind: 'rent_payment', from_ref: 'P-2', to_ref: 'P-1', amount: 50 })], [beto]), 50);
    expect(m).toMatch(/Beto te ha pagado .*alquiler/i);
  });

  it('transferencia entre jugadores → "{nombre} te ha pagado"', () => {
    const m = describeReceive(withLedger([led({ kind: 'player_to_player', from_ref: 'P-2', to_ref: 'P-1', amount: 50 })], [beto]), 50);
    expect(m).toMatch(/Beto te ha pagado/i);
  });

  it('pago de la banca → "de la banca"', () => {
    const m = describeReceive(withLedger([led({ kind: 'bank_to_player', from_ref: null, to_ref: 'P-1', amount: 200 })]), 200);
    expect(m).toMatch(/de la banca/i);
  });

  it('sin asiento que me abone → texto genérico con el importe', () => {
    const m = describeReceive(withLedger([]), 200);
    expect(m).toMatch(/Has recibido/i);
    expect(m).toContain('200');
  });

  it('elige el asiento más reciente (mayor seq) que me abona', () => {
    const m = describeReceive(withLedger([
      led({ seq: 1, kind: 'bank_to_player', to_ref: 'P-1', amount: 100 }),
      led({ seq: 2, kind: 'pass_start_bonus', to_ref: 'P-1', amount: 200 }),
    ]), 200);
    expect(m).toMatch(/al pasar por salida/i);
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
