import { describe, it, expect } from 'vitest';
import type { ActiveSnapshot, BoardSpace, PlayerPosition } from './activeSnapshot';
import {
  nextSpaceIndex, passesStart, ringSize, positionOf, playersAtSpace, spacesByBoard,
  currentSpaceProperty, canRoll, canHostSetPosition,
} from './activeSelectors';

function space(over: Partial<BoardSpace>): BoardSpace {
  return { space_ref: 'cl-space-00', board_key: 'classic', space_index: 0, name: 'Salida', space_type: 'start', property_ref: null, is_start: true, ...over };
}
function snap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  const spaces: BoardSpace[] = [
    space({ space_ref: 'cl-0', board_key: 'classic', space_index: 0, name: 'Salida', space_type: 'start', is_start: true }),
    space({ space_ref: 'cl-1', board_key: 'classic', space_index: 1, name: 'Mediterráneo', space_type: 'property', property_ref: 'cl-1', is_start: false }),
    space({ space_ref: 'cl-2', board_key: 'classic', space_index: 2, name: 'Báltico', space_type: 'property', property_ref: 'cl-2', is_start: false }),
    space({ space_ref: 'bf-0', board_key: 'back_to_the_future', space_index: 0, name: 'Salida', space_type: 'start', is_start: true }),
    space({ space_ref: 'bf-1', board_key: 'back_to_the_future', space_index: 1, name: 'Hill Valley', space_type: 'property', property_ref: 'bf-1', is_start: false }),
  ];
  const positions: PlayerPosition[] = [
    { player_ref: 'P-1', board_key: 'classic', space_index: 1 },
    { player_ref: 'P-2', board_key: 'classic', space_index: 1 },
  ];
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only' } },
    me: { public_ref: 'P-1', is_host: false, balance: 3000, is_current: true, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-1', order: ['P-1', 'P-2'] },
    players: [
      { public_ref: 'P-1', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true, status: 'active' },
      { public_ref: 'P-2', display_name: 'Beto', token_id: 'boot', balance: 3000, is_current: false, status: 'active' },
    ],
    ledger_recent: [],
    properties: [
      { property_ref: 'cl-1', board_key: 'classic', group_key: 'marron', name: 'Mediterráneo', kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 1, owner_ref: null, in_auction: false },
    ],
    auctions: [], purchase_requests: [], leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [
      { board_key: 'classic', ring_size: 3, start_bonus: 200, provisional: false },
      { board_key: 'back_to_the_future', ring_size: 2, start_bonus: 200, provisional: false },
    ],
    spaces, board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null, card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null, last_global_event: null, positions,
    my_position: { board_key: 'classic', space_index: 1 },
    current_space: { space_ref: 'cl-1', board_key: 'classic', space_index: 1, name: 'Mediterráneo', space_type: 'property', property_ref: 'cl-1', is_start: false },
    last_roll: null, last_move: null,
    runtime_status: 'running',
    current_landing_rent_resolved: false, control: { paused_by_ref: null, finished_by_ref: null, reason: null },
    runtime_version: 1,
    ...over,
  };
}

describe('movimiento — matemática del anillo (espejo del backend)', () => {
  it('nextSpaceIndex avanza y da la vuelta', () => {
    expect(nextSpaceIndex(0, 5, 29)).toBe(5);
    expect(nextSpaceIndex(27, 5, 29)).toBe(3);   // 32 % 29
    expect(nextSpaceIndex(27, 2, 29)).toBe(0);   // cae justo en salida
  });
  it('passesStart detecta cruzar o caer en salida', () => {
    expect(passesStart(0, 5, 29)).toBe(false);
    expect(passesStart(27, 5, 29)).toBe(true);
    expect(passesStart(27, 2, 29)).toBe(true);   // cae en 0
    expect(passesStart(5, 0, 29)).toBe(false);   // sin pasos no pasa
  });
});

describe('movimiento — selectores de tablero/posición', () => {
  it('ringSize lee el tamaño del anillo', () => {
    expect(ringSize(snap(), 'classic')).toBe(3);
    expect(ringSize(snap(), 'back_to_the_future')).toBe(2);
  });
  it('positionOf y playersAtSpace agrupan jugadores por casilla', () => {
    expect(positionOf(snap(), 'P-1')?.space_index).toBe(1);
    expect(playersAtSpace(snap(), 'classic', 1).sort()).toEqual(['P-1', 'P-2']);
    expect(playersAtSpace(snap(), 'classic', 0)).toEqual([]);
  });
  it('spacesByBoard agrupa por tablero en orden de anillo', () => {
    const g = spacesByBoard(snap());
    expect(g.map((b) => b.board)).toEqual(['classic', 'back_to_the_future']);
    expect(g[0]!.items.map((s) => s.space_index)).toEqual([0, 1, 2]);
  });
  it('currentSpaceProperty devuelve la propiedad de la casilla actual', () => {
    expect(currentSpaceProperty(snap())?.property_ref).toBe('cl-1');
    expect(currentSpaceProperty(snap({ current_space: { space_ref: 'cl-0', board_key: 'classic', space_index: 0, name: 'Salida', space_type: 'start', property_ref: null, is_start: true } }))).toBeNull();
  });
});

describe('movimiento — permisos', () => {
  it('canRoll: solo en curso, mi turno y no espectador', () => {
    expect(canRoll(snap())).toBe(true);
    expect(canRoll(snap({ me: { public_ref: 'P-1', is_host: false, balance: 1, is_current: false, is_spectator: false } }))).toBe(false);
    expect(canRoll(snap({ runtime_status: 'paused' }))).toBe(false);
    expect(canRoll(snap({ me: { public_ref: 'P-1', is_host: false, balance: 1, is_current: true, is_spectator: true } }))).toBe(false);
  });
  it('canHostSetPosition: solo anfitrión en curso', () => {
    expect(canHostSetPosition(snap({ me: { public_ref: 'P-1', is_host: true, balance: 1, is_current: true, is_spectator: false } }))).toBe(true);
    expect(canHostSetPosition(snap())).toBe(false); // no host
    expect(canHostSetPosition(snap({ me: { public_ref: 'P-1', is_host: true, balance: 1, is_current: true, is_spectator: false }, runtime_status: 'paused' }))).toBe(false);
  });
});
