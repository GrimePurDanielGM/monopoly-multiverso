import { describe, it, expect } from 'vitest';
import { parseActiveSnapshot } from './activeSnapshot';

const valid = {
  game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16, allow_late_join: false } },
  me: { public_ref: 'P-AAAA', is_host: true, balance: 3000, is_current: true, is_spectator: false },
  turn: { turn_number: 1, current_player_ref: 'P-AAAA', order: ['P-AAAA', 'P-BBBB'] },
  players: [
    { public_ref: 'P-AAAA', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true, status: 'active' },
    { public_ref: 'P-BBBB', display_name: 'Beto', token_id: null, balance: 3000, is_current: false, status: 'bankrupt' },
  ],
  ledger_recent: [
    { ledger_ref: 'L-AAAA', seq: 2, kind: 'bank_to_player', from_ref: null, to_ref: 'P-AAAA', amount: 100, before_balance: null, after_balance: null, reason: null, actor_ref: 'P-AAAA', reverts_ref: null, created_at: '2026-06-18T00:00:00Z' },
  ],
  properties: [
    { property_ref: 'cl-ronda-valencia', board_key: 'classic', group_key: 'marron', name: 'Ronda de Valencia', kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 10, owner_ref: null, in_auction: false },
    { property_ref: 'cl-estacion-norte', board_key: 'classic', group_key: 'estaciones', name: 'Estación del Norte', kind: 'station', price: 200, base_rent: 25, is_buyable: true, sort_order: 30, owner_ref: 'P-AAAA', in_auction: false },
  ],
  auctions: [
    { auction_ref: 'A-1', property_ref: 'cl-prado', property_name: 'Paseo del Prado', high_bid: 100, high_bidder_ref: 'P-AAAA', started_by_ref: 'P-AAAA' },
  ],
  purchase_requests: [
    { request_ref: 'PR-1', property_ref: 'cl-bailen', property_name: 'Calle Bailén', requester_ref: 'P-BBBB', requester_name: 'Beto' },
  ],
  leave_requests: [],
  bankruptcy_requests: [
    { request_ref: 'BR-1', requester_ref: 'P-BBBB', requester_name: 'Beto', kind: 'to_player', creditor_ref: 'P-AAAA', creditor_name: 'Ana', reason: 'sin fondos' },
  ],
  late_join_requests: [],
  runtime_status: 'running',
  control: { paused_by_ref: null, finished_by_ref: null, reason: null },
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

  it('parsea properties con owner_ref (null = disponible)', () => {
    const r = parseActiveSnapshot(valid);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.data.properties).toHaveLength(2);
      expect(r.data.properties[0]!.owner_ref).toBeNull();
      expect(r.data.properties[1]!.owner_ref).toBe('P-AAAA');
      expect(r.data.properties[1]!.base_rent).toBe(25);
    }
  });

  it('rechaza properties ausente o board_key inválido', () => {
    const { properties, ...sinProps } = valid;
    void properties;
    expect(parseActiveSnapshot(sinProps).ok).toBe(false);
    const badBoard = { ...valid, properties: [{ ...valid.properties[0], board_key: 'marte' }] };
    expect(parseActiveSnapshot(badBoard).ok).toBe(false);
  });
});
