import { describe, it, expect } from 'vitest';
import {
  parseAmount, parseBalance, canAfford, isValidReason, isNoopAdjust, isRevertible,
  isMyTurn, isHost, currentPlayerName, kindLabel, refLabel, formatMoney, newRequestId, MAX_AMOUNT,
  propertyStatus, canBuyProperty, canPayRent, myProperties, propertyCountByPlayer, ownerName, propertiesByBoard,
} from './activeSelectors';
import type { ActiveSnapshot, LedgerEntry, ActivePlayer, ActiveProperty } from './activeSnapshot';

const prop = (over: Partial<ActiveProperty> = {}): ActiveProperty => ({
  property_ref: 'cl-marron-1', board_key: 'classic', group_key: 'marron', name: 'Mediterráneo',
  kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 10, owner_ref: null, ...over,
});

const players: ActivePlayer[] = [
  { public_ref: 'P-AAAA', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true },
  { public_ref: 'P-BBBB', display_name: 'Beto', token_id: 'boot', balance: 1000, is_current: false },
];
const snap: ActiveSnapshot = {
  game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16, allow_late_join: false } },
  me: { public_ref: 'P-BBBB', is_host: true, balance: 1000, is_current: false },
  turn: { turn_number: 5, current_player_ref: 'P-AAAA', order: ['P-AAAA', 'P-BBBB'] },
  players,
  ledger_recent: [],
  properties: [],
  late_join_requests: [],
  runtime_status: 'running',
  control: { paused_by_ref: null, finished_by_ref: null, reason: null },
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

describe('propiedades (Fase 3)', () => {
  // me = P-BBBB (saldo 1000); P-AAAA es otro jugador.
  const withProps = (props: ActiveProperty[], over: Partial<ActiveSnapshot> = {}): ActiveSnapshot => ({ ...snap, properties: props, ...over });

  it('propertyStatus distingue mía / disponible / de otro / no comprable', () => {
    const s = withProps([
      prop({ property_ref: 'a', owner_ref: 'P-BBBB' }),
      prop({ property_ref: 'b', owner_ref: null }),
      prop({ property_ref: 'c', owner_ref: 'P-AAAA' }),
      prop({ property_ref: 'd', owner_ref: null, is_buyable: false, kind: 'special', price: 0, base_rent: 0 }),
    ]);
    expect(propertyStatus(s.properties[0]!, s)).toBe('mine');
    expect(propertyStatus(s.properties[1]!, s)).toBe('available');
    expect(propertyStatus(s.properties[2]!, s)).toBe('owned');
    expect(propertyStatus(s.properties[3]!, s)).toBe('not_buyable');
  });

  it('canBuyProperty: solo libre, comprable, con saldo y en curso', () => {
    const ok = withProps([prop({ price: 60 })]);
    expect(canBuyProperty(ok.properties[0]!, ok)).toBe(true);
    const caro = withProps([prop({ price: 5000 })]);                      // saldo 1000 < 5000
    expect(canBuyProperty(caro.properties[0]!, caro)).toBe(false);
    const ocupada = withProps([prop({ owner_ref: 'P-AAAA' })]);
    expect(canBuyProperty(ocupada.properties[0]!, ocupada)).toBe(false);
    const pausada = withProps([prop({ price: 60 })], { runtime_status: 'paused' });
    expect(canBuyProperty(pausada.properties[0]!, pausada)).toBe(false);
  });

  it('canPayRent: de otro jugador, con alquiler y saldo, en curso (nunca a uno mismo)', () => {
    const ajeno = withProps([prop({ owner_ref: 'P-AAAA', base_rent: 25 })]);
    expect(canPayRent(ajeno.properties[0]!, ajeno)).toBe(true);
    const mia = withProps([prop({ owner_ref: 'P-BBBB', base_rent: 25 })]);
    expect(canPayRent(mia.properties[0]!, mia)).toBe(false);
    const libre = withProps([prop({ owner_ref: null })]);
    expect(canPayRent(libre.properties[0]!, libre)).toBe(false);
    const finalizada = withProps([prop({ owner_ref: 'P-AAAA', base_rent: 25 })], { runtime_status: 'finished' });
    expect(canPayRent(finalizada.properties[0]!, finalizada)).toBe(false);
  });

  it('myProperties / propertyCountByPlayer / ownerName', () => {
    const s = withProps([
      prop({ property_ref: 'a', owner_ref: 'P-BBBB' }),
      prop({ property_ref: 'b', owner_ref: 'P-AAAA' }),
      prop({ property_ref: 'c', owner_ref: 'P-AAAA' }),
      prop({ property_ref: 'd', owner_ref: null }),
    ]);
    expect(myProperties(s).map((p) => p.property_ref)).toEqual(['a']);
    expect(propertyCountByPlayer(s)).toEqual({ 'P-BBBB': 1, 'P-AAAA': 2 });
    expect(ownerName(s.properties[1]!, s)).toBe('Ana');
    expect(ownerName(s.properties[3]!, s)).toBe('Banca');
  });

  it('propertiesByBoard agrupa por tablero', () => {
    const s = withProps([
      prop({ property_ref: 'a', board_key: 'classic' }),
      prop({ property_ref: 'b', board_key: 'back_to_the_future' }),
      prop({ property_ref: 'c', board_key: 'classic' }),
    ]);
    const g = propertiesByBoard(s);
    expect(g.map((x) => x.board)).toEqual(['classic', 'back_to_the_future']);
    expect(g[0]!.items).toHaveLength(2);
    expect(g[0]!.label).toBe('Clásico');
  });
});
