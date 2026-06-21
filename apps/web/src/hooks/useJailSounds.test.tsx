import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import type { ActiveSnapshot, MyJail } from '../lib/activeSnapshot';

const playMock = vi.hoisted(() => vi.fn());
vi.mock('../lib/sfx', () => ({ playSfx: playMock, primeSfx: vi.fn() }));

import { useJailSounds } from './useJailSounds';

function snap(myJail: MyJail | null, version: number): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false } },
    me: { public_ref: 'P-1', is_host: false, balance: 3000, is_current: true, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-1', order: ['P-1'] },
    players: [], ledger_recent: [], properties: [], auctions: [], purchase_requests: [], leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [], spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: myJail,
    card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null,
    last_global_event: null, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running', current_landing_rent_resolved: false, building_stock: { houses_available: 32, hotels_available: 12 }, building_requests: [], my_building_requests: [], incoming_trades: [], outgoing_trades: [], trade_reviews: [], recent_trades: [], control: { paused_by_ref: null, finished_by_ref: null, reason: null }, runtime_version: version,
  };
}
const JAIL: MyJail = { board_key: 'classic', jail_turns: 0, fine: 50, action_taken_this_turn: false };

describe('useJailSounds', () => {
  beforeEach(() => playMock.mockClear());

  it('no suena en el primer snapshot (línea base)', () => {
    renderHook(({ s }) => useJailSounds(s), { initialProps: { s: snap(JAIL, 1) } });
    expect(playMock).not.toHaveBeenCalled();
  });

  it('sirena al ENTRAR en la cárcel (no preso → preso)', () => {
    const { rerender } = renderHook(({ s }) => useJailSounds(s), { initialProps: { s: snap(null, 1) } });
    rerender({ s: snap(JAIL, 2) });
    expect(playMock).toHaveBeenCalledWith('siren');
  });

  it('sonido de liberación al SALIR de la cárcel (preso → no preso)', () => {
    const { rerender } = renderHook(({ s }) => useJailSounds(s), { initialProps: { s: snap(JAIL, 1) } });
    rerender({ s: snap(null, 2) });
    expect(playMock).toHaveBeenCalledWith('release');
  });

  it('no suena dos veces por el mismo runtime_version', () => {
    const { rerender } = renderHook(({ s }) => useJailSounds(s), { initialProps: { s: snap(null, 1) } });
    rerender({ s: snap(JAIL, 2) });
    rerender({ s: snap(JAIL, 2) });
    expect(playMock).toHaveBeenCalledTimes(1);
  });
});
