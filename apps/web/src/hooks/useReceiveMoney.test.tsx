import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import type { ActiveSnapshot } from '../lib/activeSnapshot';

const { playMock, enabledMock } = vi.hoisted(() => ({ playMock: vi.fn(), enabledMock: vi.fn(() => true) }));
vi.mock('../lib/cashSound', () => ({
  playCashSound: playMock,
  isCashSoundEnabled: enabledMock,
  setCashSoundEnabled: vi.fn(),
  primeCashSound: vi.fn(),
}));

import { useReceiveMoney } from './useReceiveMoney';

function snap(balance: number, version: number): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false, allow_trade_built_properties: false, parking_mode: 'pot', start_invest_pct: 0 } },
    me: { public_ref: 'P-1', is_host: false, balance, is_current: false, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-2', order: ['P-1', 'P-2'] },
    players: [], ledger_recent: [], properties: [], auctions: [], purchase_requests: [],
    leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [], spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null, card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null, last_global_event: null, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running', current_landing_rent_resolved: false, building_stock: { houses_available: 32, hotels_available: 12 }, building_requests: [], my_building_requests: [], incoming_trades: [], outgoing_trades: [], trade_reviews: [], recent_trades: [], my_card_transfers: [], control: { paused_by_ref: null, finished_by_ref: null, reason: null },
    runtime_version: version,
  };
}

describe('useReceiveMoney', () => {
  beforeEach(() => { playMock.mockClear(); enabledMock.mockReturnValue(true); });

  it('no suena en el primer snapshot', () => {
    renderHook(({ s }) => useReceiveMoney(s), { initialProps: { s: snap(3000, 5) } });
    expect(playMock).not.toHaveBeenCalled();
  });

  it('suena (una vez) y devuelve el delta cuando mi saldo aumenta', () => {
    const { result, rerender } = renderHook(({ s }) => useReceiveMoney(s), { initialProps: { s: snap(3000, 5) } });
    rerender({ s: snap(3500, 6) });
    expect(playMock).toHaveBeenCalledTimes(1);
    expect(result.current?.amount).toBe(500);
    expect(result.current?.message).toMatch(/recibido|pagado|cobrado/i);
  });

  it('no suena si la preferencia está desactivada', () => {
    enabledMock.mockReturnValue(false);
    const { rerender } = renderHook(({ s }) => useReceiveMoney(s), { initialProps: { s: snap(3000, 5) } });
    rerender({ s: snap(3500, 6) });
    expect(playMock).not.toHaveBeenCalled();
  });

  it('no suena dos veces por el mismo runtime_version', () => {
    const { rerender } = renderHook(({ s }) => useReceiveMoney(s), { initialProps: { s: snap(3000, 5) } });
    rerender({ s: snap(3500, 6) });
    rerender({ s: snap(3500, 6) }); // mismo runtime_version reprocesado
    expect(playMock).toHaveBeenCalledTimes(1);
  });

  it('no suena si mi saldo baja', () => {
    const { rerender } = renderHook(({ s }) => useReceiveMoney(s), { initialProps: { s: snap(3000, 5) } });
    rerender({ s: snap(2500, 6) });
    expect(playMock).not.toHaveBeenCalled();
  });
});
