import { describe, it, expect } from 'vitest';
import {
  parseAmount, parseBalance, canAfford, isValidReason, isNoopAdjust, isRevertible,
  isMyTurn, isHost, currentPlayerName, kindLabel, refLabel, formatMoney, newRequestId, MAX_AMOUNT,
} from './activeSelectors';
import type { ActiveSnapshot, LedgerEntry, ActivePlayer } from './activeSnapshot';

const players: ActivePlayer[] = [
  { public_ref: 'P-AAAA', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true },
  { public_ref: 'P-BBBB', display_name: 'Beto', token_id: 'boot', balance: 1000, is_current: false },
];
const snap: ActiveSnapshot = {
  game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16 } },
  me: { public_ref: 'P-BBBB', is_host: true, balance: 1000, is_current: false },
  turn: { turn_number: 5, current_player_ref: 'P-AAAA', order: ['P-AAAA', 'P-BBBB'] },
  players,
  ledger_recent: [],
  runtime_version: 7,
};

describe('parseAmount', () => {
  it('acepta enteros positivos', () => expect(parseAmount('250')).toEqual({ ok: true, value: 250 }));
  it('rechaza vacío', () => expect(parseAmount('  ').ok).toBe(false));
  it('rechaza cero', () => expect(parseAmount('0').ok).toBe(false));
  it('rechaza decimales', () => expect(parseAmount('10.5').ok).toBe(false));
  it('rechaza negativos', () => expect(parseAmount('-3').ok).toBe(false));
  it('rechaza por encima del tope', () => expect(parseAmount(String(MAX_AMOUNT + 1)).ok).toBe(false));
});

describe('parseBalance', () => {
  it('acepta 0', () => expect(parseBalance('0')).toEqual({ ok: true, value: 0 }));
  it('rechaza negativo', () => expect(parseBalance('-1').ok).toBe(false));
});

describe('permisos y turnos', () => {
  it('canAfford', () => { expect(canAfford(1000, 500)).toBe(true); expect(canAfford(100, 500)).toBe(false); });
  it('isValidReason', () => { expect(isValidReason('ok motivo')).toBe(true); expect(isValidReason('ab')).toBe(false); });
  it('isNoopAdjust', () => { expect(isNoopAdjust(3000, 3000)).toBe(true); expect(isNoopAdjust(3000, 1)).toBe(false); });
  it('isMyTurn / isHost', () => { expect(isMyTurn(snap)).toBe(false); expect(isHost(snap)).toBe(true); });
  it('currentPlayerName', () => expect(currentPlayerName(snap)).toBe('Ana'));
});

describe('ledger helpers', () => {
  const seed: LedgerEntry = { ledger_ref: 'L-1', seq: 1, kind: 'seed', from_ref: null, to_ref: 'P-AAAA', amount: 3000, before_balance: null, after_balance: null, reason: null, actor_ref: null, reverts_ref: null, created_at: 't' };
  const pay: LedgerEntry = { ...seed, ledger_ref: 'L-2', kind: 'bank_to_player', amount: 100 };
  const reverted: LedgerEntry = { ...pay, ledger_ref: 'L-3', reverts_ref: 'L-9' };
  it('isRevertible', () => {
    expect(isRevertible(seed)).toBe(false);     // seed no
    expect(isRevertible(pay)).toBe(true);       // pago sí
    expect(isRevertible(reverted)).toBe(false); // ya revertido no
  });
  it('kindLabel / refLabel / formatMoney', () => {
    expect(kindLabel('player_to_player')).toMatch(/Transferencia/);
    expect(refLabel(null, players)).toBe('Banco');
    expect(refLabel('P-AAAA', players)).toBe('Ana');
    expect(formatMoney(1500)).toMatch(/1\.500/);
  });
});

describe('newRequestId', () => {
  it('genera uuid distinto', () => {
    const a = newRequestId(); const b = newRequestId();
    expect(a).toMatch(/^[0-9a-f-]{36}$/i);
    expect(a).not.toBe(b);
  });
});
