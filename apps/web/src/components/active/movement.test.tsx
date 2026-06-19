import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { ActiveSnapshot, BoardSpace, PlayerPosition } from '../../lib/activeSnapshot';
import { MovementPanel } from './MovementPanel';
import { BoardView } from './BoardView';

function snap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  const spaces: BoardSpace[] = [
    { space_ref: 'cl-0', board_key: 'classic', space_index: 0, name: 'Salida', space_type: 'start', property_ref: null, is_start: true },
    { space_ref: 'cl-1', board_key: 'classic', space_index: 1, name: 'Mediterráneo', space_type: 'property', property_ref: 'cl-1', is_start: false },
    { space_ref: 'bf-0', board_key: 'back_to_the_future', space_index: 0, name: 'Salida', space_type: 'start', property_ref: null, is_start: true },
  ];
  const positions: PlayerPosition[] = [{ player_ref: 'P-1', board_key: 'classic', space_index: 1 }];
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200 } },
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
    boards: [{ board_key: 'classic', ring_size: 2, start_bonus: 200, provisional: false }, { board_key: 'back_to_the_future', ring_size: 1, start_bonus: 200, provisional: false }],
    spaces, board_links: [], positions,
    my_position: { board_key: 'classic', space_index: 1 },
    current_space: { space_ref: 'cl-1', board_key: 'classic', space_index: 1, name: 'Mediterráneo', space_type: 'property', property_ref: 'cl-1', is_start: false },
    last_roll: { d1: 2, d2: 3, total: 5, player_ref: 'P-1' },
    last_move: { player_ref: 'P-1', board: 'classic', from: 0, to: 1, steps: 1, method: 'roll', passed_start: false, bonus: 0, space_ref: 'cl-1', space_name: 'Mediterráneo', space_type: 'property', property_ref: 'cl-1' },
    runtime_status: 'running',
    control: { paused_by_ref: null, finished_by_ref: null, reason: null },
    runtime_version: 1,
    ...over,
  };
}

describe('MovementPanel', () => {
  const cbs = () => ({ onRoll: vi.fn(), onMoveManual: vi.fn(), onOpenBoard: vi.fn(), onRequestPurchase: vi.fn(), onPayRent: vi.fn() });

  it('mi turno: "Tirar dados" llama onRoll y muestra la última tirada', () => {
    const c = cbs();
    render(<MovementPanel snap={snap()} busy={false} {...c} />);
    expect(screen.getByText(/Última tirada/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Tirar dados/ }));
    expect(c.onRoll).toHaveBeenCalledTimes(1);
  });

  it('mover manualmente llama onMoveManual con el número de casillas', () => {
    const c = cbs();
    render(<MovementPanel snap={snap()} busy={false} {...c} />);
    fireEvent.change(screen.getByLabelText('Casillas a mover'), { target: { value: '4' } });
    fireEvent.click(screen.getByRole('button', { name: 'Mover' }));
    expect(c.onMoveManual).toHaveBeenCalledWith(4);
  });

  it('al caer en propiedad disponible ofrece "Solicitar compra" desde el contexto', () => {
    const c = cbs();
    render(<MovementPanel snap={snap()} busy={false} {...c} />);
    expect(screen.getByText(/Has caído en/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Solicitar compra' }));
    expect(c.onRequestPurchase).toHaveBeenCalledTimes(1);
  });

  it('al caer en propiedad de otro ofrece "Pagar alquiler"', () => {
    const c = cbs();
    const s = snap({
      properties: [{ property_ref: 'cl-1', board_key: 'classic', group_key: 'marron', name: 'Mediterráneo', kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 1, owner_ref: 'P-2', in_auction: false }],
    });
    render(<MovementPanel snap={s} busy={false} {...c} />);
    fireEvent.click(screen.getByRole('button', { name: /Pagar alquiler/ }));
    expect(c.onPayRent).toHaveBeenCalledTimes(1);
  });

  it('si no es mi turno no muestra "Tirar dados" y avisa', () => {
    const c = cbs();
    render(<MovementPanel snap={snap({ me: { public_ref: 'P-1', is_host: false, balance: 1, is_current: false, is_spectator: false }, turn: { turn_number: 1, current_player_ref: 'P-2', order: ['P-1', 'P-2'] } })} busy={false} {...c} />);
    expect(screen.queryByRole('button', { name: /Tirar dados/ })).toBeNull();
    expect(screen.getByText(/No es tu turno/)).toBeInTheDocument();
  });

  it('"Ver tablero" llama onOpenBoard', () => {
    const c = cbs();
    render(<MovementPanel snap={snap()} busy={false} {...c} />);
    fireEvent.click(screen.getByRole('button', { name: 'Ver tablero' }));
    expect(c.onOpenBoard).toHaveBeenCalledTimes(1);
  });
});

describe('BoardView (tablero visual)', () => {
  it('muestra pestañas de ambos tableros y los nombres de los jugadores (no la ficha)', () => {
    render(<BoardView snap={snap()} onClose={vi.fn()} onRequestPurchase={vi.fn()} />);
    expect(screen.getByRole('tab', { name: 'Clásico' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'Regreso al futuro' })).toBeInTheDocument();
    // La leyenda muestra los NOMBRES de los jugadores.
    expect(screen.getByText('Ana')).toBeInTheDocument();
    expect(screen.getByText('Beto')).toBeInTheDocument();
  });

  it('tocar una casilla abre su detalle con los jugadores presentes por nombre', () => {
    render(<BoardView snap={snap()} onClose={vi.fn()} onRequestPurchase={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Casilla 1: Mediterráneo' }));
    expect(screen.getByRole('dialog', { name: 'Detalle de Mediterráneo' })).toBeInTheDocument();
    expect(screen.getByText(/Jugadores aquí: Ana/)).toBeInTheDocument();
  });

  it('puede cambiar al tablero Regreso al futuro y "Cerrar" cierra', () => {
    const onClose = vi.fn();
    render(<BoardView snap={snap()} onClose={onClose} onRequestPurchase={vi.fn()} />);
    fireEvent.click(screen.getByRole('tab', { name: 'Regreso al futuro' }));
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('respeta el safe area superior (iPhone) y mantiene Cerrar y el selector accesibles', () => {
    const { container } = render(<BoardView snap={snap()} onClose={vi.fn()} onRequestPurchase={vi.fn()} />);
    const header = container.querySelector('header');
    expect(header?.className).toContain('safe-area-inset-top'); // padding-top con safe area
    expect(screen.getByRole('button', { name: 'Cerrar' })).toBeVisible();
    expect(screen.getByRole('tab', { name: 'Clásico' })).toBeVisible();
  });

  it('muestra el guardián en la cárcel y la nota de montaje en cruz', () => {
    const s = snap({
      spaces: [
        { space_ref: 'cl-0', board_key: 'classic', space_index: 0, name: 'Salida', space_type: 'start', property_ref: null, is_start: true },
        { space_ref: 'cl-1', board_key: 'classic', space_index: 1, name: 'Cárcel / Solo visitas', space_type: 'jail', property_ref: null, is_start: false, guardian: true, links_to_board: 'back_to_the_future', links_to_index: 20, guardian_toll: 100 },
        { space_ref: 'cl-2', board_key: 'classic', space_index: 2, name: 'Glorieta de Bilbao', space_type: 'property', property_ref: 'cl-bilbao', is_start: false },
        { space_ref: 'bf-20', board_key: 'back_to_the_future', space_index: 20, name: 'Parking gratuito', space_type: 'parking', property_ref: null, is_start: false },
      ],
      board_links: [{ board_key: 'classic', space_index: 1, space_type: 'jail', links_to_board: 'back_to_the_future', links_to_index: 20, guardian: true }],
    });
    render(<BoardView snap={s} onClose={vi.fn()} onRequestPurchase={vi.fn()} />);
    expect(screen.getByText(/montan en cruz/)).toBeInTheDocument();
    // El guardián está en la cárcel; al tocarla, su detalle muestra las dos entradas y el peaje.
    fireEvent.click(screen.getByRole('button', { name: /Cárcel \/ Solo visitas \(guardián\)/ }));
    expect(screen.getByText(/Guardián \(peaje 100\)/)).toBeInTheDocument();
  });
});
