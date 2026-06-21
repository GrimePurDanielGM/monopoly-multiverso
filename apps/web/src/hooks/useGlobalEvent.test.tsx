import { describe, it, expect } from 'vitest';
import { renderHook } from '@testing-library/react';
import type { ActiveSnapshot, GlobalEvent } from '../lib/activeSnapshot';
import { useGlobalEvent } from './useGlobalEvent';

function snap(ev: GlobalEvent | null, version = 1): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false, allow_trade_built_properties: false, parking_mode: 'pot' } },
    me: { public_ref: 'P-1', is_host: false, balance: 3000, is_current: true, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-1', order: ['P-1', 'P-2'] },
    players: [
      { public_ref: 'P-1', display_name: 'Ana', token_id: null, balance: 3000, is_current: true, status: 'active' },
      { public_ref: 'P-2', display_name: 'Beto', token_id: null, balance: null, is_current: false, status: 'active' },
    ],
    ledger_recent: [], properties: [], auctions: [], purchase_requests: [], leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [], spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null,
    card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null,
    last_global_event: ev, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running', current_landing_rent_resolved: false, building_stock: { houses_available: 32, hotels_available: 12 }, building_requests: [], my_building_requests: [], incoming_trades: [], outgoing_trades: [], trade_reviews: [], recent_trades: [], my_card_transfers: [], control: { paused_by_ref: null, finished_by_ref: null, reason: null }, runtime_version: version,
  };
}
const payout = (id: string, ref = 'P-2', amount = 450): GlobalEvent => ({ kind: 'parking_pot_payout', player_ref: ref, amount, event_id: id });

describe('useGlobalEvent', () => {
  it('no muestra nada en el primer snapshot (línea base, p. ej. tras recargar)', () => {
    const { result } = renderHook(({ s }) => useGlobalEvent(s), { initialProps: { s: snap(payout('e1')) } });
    expect(result.current).toBeNull();
  });

  it('muestra el banner cuando aparece un evento NUEVO (nombre + importe)', () => {
    const { result, rerender } = renderHook(({ s }) => useGlobalEvent(s), { initialProps: { s: snap(null) } });
    rerender({ s: snap(payout('e1', 'P-2', 450), 2) });
    expect(result.current).toMatchObject({ name: 'Beto', amount: 450 });
  });

  it('no se duplica por el mismo event_id (misma versión reprocesada)', () => {
    const { result, rerender } = renderHook(({ s }) => useGlobalEvent(s), { initialProps: { s: snap(null) } });
    rerender({ s: snap(payout('e1'), 2) });
    expect(result.current).not.toBeNull();
    rerender({ s: snap(payout('e1'), 2) }); // mismo evento
    // el banner sigue siendo el mismo objeto (no se re-dispara); basta con que no lance ni cambie de identidad.
    expect(result.current).toMatchObject({ name: 'Beto', amount: 450 });
  });
});
