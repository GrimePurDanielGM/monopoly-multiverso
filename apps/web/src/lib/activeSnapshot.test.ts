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
  current_landing_rent_resolved: false, building_stock: { houses_available: 32, hotels_available: 12 }, building_requests: [], my_building_requests: [], control: { paused_by_ref: null, finished_by_ref: null, reason: null },
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

  it('acepta el ledger guardian_toll (peaje del guardián al cruzar)', () => {
    const ok = { ...valid, ledger_recent: [{ ...valid.ledger_recent[0], kind: 'guardian_toll', from_ref: 'P-AAAA', to_ref: null }] };
    expect(parseActiveSnapshot(ok).ok).toBe(true);
  });

  it('acepta los ledgers de Fase 5 (impuesto, bote, cárcel, cartas)', () => {
    for (const [kind, from_ref, to_ref] of [
      ['tax_payment', 'P-AAAA', null], ['parking_pot_payout', null, 'P-AAAA'], ['jail_release_payment', 'P-AAAA', null],
      ['card_bank_payment', null, 'P-AAAA'], ['card_bank_charge', 'P-AAAA', null],
      ['card_player_payment', 'P-AAAA', 'P-BBBB'], ['card_player_charge', 'P-BBBB', 'P-AAAA'],
    ] as const) {
      const ok = { ...valid, ledger_recent: [{ ...valid.ledger_recent[0], kind, from_ref, to_ref }] };
      expect(parseActiveSnapshot(ok).ok, kind).toBe(true);
    }
  });

  it('parsea last_global_event y last_roll.jail (Fase 5 corrección)', () => {
    const raw = {
      ...valid,
      last_roll: { d1: 4, d2: 4, total: 8, player_ref: 'P-AAAA', jail: 'doubles' },
      last_global_event: { kind: 'parking_pot_payout', player_ref: 'P-AAAA', amount: 450, event_id: 'ev-1' },
    };
    const r = parseActiveSnapshot(raw);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.data.last_roll?.jail).toBe('doubles');
      expect(r.data.last_global_event).toEqual({ kind: 'parking_pot_payout', player_ref: 'P-AAAA', amount: 450, event_id: 'ev-1' });
    }
  });

  it('parsea los campos de casillas especiales (Fase 5): bote, cárcel, mazos, carta e inventario', () => {
    const raw = {
      ...valid, parking_pot: 250,
      jail: [{ player_ref: 'P-AAAA', board_key: 'classic', jail_turns: 1 }],
      my_jail: { board_key: 'classic', jail_turns: 1, fine: 50 },
      card_decks: [{ deck_key: 'chance', board_key: 'classic', draw_count: 8, discard_count: 1 }],
      last_card_draw: { draw_id: 'd1', player_ref: 'P-AAAA', deck_key: 'chance', board_key: 'classic', card_ref: 'chance-credit-200',
        title: 'Cobras', description: 'Cobra 200', effect_type: 'bank_credit', amount: 200, keepable: false, temporary: true, manual: false },
      held_cards: [{ player_ref: 'P-AAAA', count: 1 }],
      my_held_cards: [{ card_ref: 'chance-jail-free', title: 'Sal de la cárcel', description: '', deck_key: 'chance', effect_type: 'jail_free' }],
      pending_card: null,
      pending_payment: { kind: 'tax', player_ref: 'P-AAAA', amount: 100, board: 'classic', space_index: 38, space_name: 'Impuesto de lujo' },
    };
    const r = parseActiveSnapshot(raw);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.data.parking_pot).toBe(250);
      expect(r.data.my_jail?.fine).toBe(50);
      expect(r.data.card_decks[0]?.draw_count).toBe(8);
      expect(r.data.last_card_draw?.card_ref).toBe('chance-credit-200');
      expect(r.data.my_held_cards[0]?.effect_type).toBe('jail_free');
      expect(r.data.pending_payment?.amount).toBe(100);
    }
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
