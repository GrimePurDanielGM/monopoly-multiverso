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
    spaces, board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null, card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null, last_global_event: null, positions,
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
  const cbs = () => ({ onRoll: vi.fn(), onMoveManual: vi.fn(), onOpenBoard: vi.fn(), onRequestPurchase: vi.fn(), onPayRent: vi.fn(), onResolveJunction: vi.fn(), onPayJailRelease: vi.fn(), onUseJailCard: vi.fn(), onPayPending: vi.fn() });

  it('mi turno: "Tirar dados" llama onRoll y muestra la última tirada', () => {
    const c = cbs();
    render(<MovementPanel snap={snap()} busy={false} {...c} />);
    expect(screen.getByText(/Última tirada/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Tirar dados/ }));
    expect(c.onRoll).toHaveBeenCalledTimes(1);
  });

  it('mover manualmente: elegir 1–12 con botones y Mover llama onMoveManual', () => {
    const c = cbs();
    render(<MovementPanel snap={snap()} busy={false} {...c} />);
    // Mover está deshabilitado hasta elegir un valor válido (no se puede mover con 0).
    expect(screen.getByRole('button', { name: 'Mover' })).toBeDisabled();
    fireEvent.click(screen.getByRole('button', { name: '7 casillas' }));
    fireEvent.click(screen.getByRole('button', { name: 'Mover 7' }));
    expect(c.onMoveManual).toHaveBeenCalledWith(7);
  });

  it('mover manualmente: 1 casilla (singular) y dígitos 8–12 disponibles', () => {
    const c = cbs();
    render(<MovementPanel snap={snap()} busy={false} {...c} />);
    expect(screen.getByRole('button', { name: '1 casilla' })).toBeInTheDocument();
    [8, 9, 10, 11, 12].forEach((n) => expect(screen.getByRole('button', { name: `${n} casillas` })).toBeInTheDocument());
    fireEvent.click(screen.getByRole('button', { name: '11 casillas' }));
    fireEvent.click(screen.getByRole('button', { name: 'Mover 11' }));
    expect(c.onMoveManual).toHaveBeenCalledWith(11);
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

  it('decisión de cruce: muestra los dos destinos (libre/peaje) y no deja tirar; elegir llama onResolveJunction', () => {
    const c = cbs();
    const s = snap({
      spaces: [
        { space_ref: 'cl-10', board_key: 'classic', space_index: 10, name: 'Cárcel / Solo visitas', space_type: 'jail', property_ref: null, is_start: false, guardian: true, links_to_board: 'back_to_the_future', links_to_index: 20, guardian_toll: 100 },
        { space_ref: 'cl-11', board_key: 'classic', space_index: 11, name: 'Glorieta de Bilbao', space_type: 'property', property_ref: 'cl-bilbao', is_start: false },
        { space_ref: 'bf-20', board_key: 'back_to_the_future', space_index: 20, name: 'Parking gratuito', space_type: 'parking', property_ref: null, is_start: false },
      ],
      guardians: [{ board_key: 'classic', guards: 'cross' }],
      pending_junction: { player_ref: 'P-1', board_key: 'classic', junction_index: 10, remaining: 2 },
    });
    render(<MovementPanel snap={s} busy={false} {...c} />);
    expect(screen.queryByRole('button', { name: /Tirar dados/ })).toBeNull();           // no se puede tirar
    expect(screen.getByText(/Has llegado a la cárcel/)).toBeInTheDocument();
    const seguir = screen.getByRole('button', { name: /Seguir.*Glorieta de Bilbao.*gratis/ });
    expect(screen.getByRole('button', { name: /Cruzar.*Parking gratuito.*peaje/ })).toBeInTheDocument();
    fireEvent.click(seguir);
    expect(c.onResolveJunction).toHaveBeenCalledWith('own');
  });

  it('en la cárcel: estado + "Intento 1/3", intentar dobles (onRoll), pagar la multa y NO mover manual', () => {
    const c = cbs();
    const s = snap({ my_jail: { board_key: 'classic', jail_turns: 0, fine: 50 } });
    render(<MovementPanel snap={s} busy={false} {...c} />);
    expect(screen.getByText(/Estás en la cárcel/)).toBeInTheDocument();
    expect(screen.getByText(/Intento 1\/3/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Tirar dados/ })).toBeNull();     // no es tirada normal
    expect(screen.queryByRole('button', { name: '1 casilla' })).toBeNull();        // no se mueve manualmente
    fireEvent.click(screen.getByRole('button', { name: /Intentar sacar dobles/ }));
    expect(c.onRoll).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole('button', { name: /Pagar 50 ₥ para salir/ }));
    expect(c.onPayJailRelease).toHaveBeenCalledTimes(1);
  });

  it('cárcel: el contador de intentos avanza (jail_turns=2 → "Intento 3/3")', () => {
    const c = cbs();
    render(<MovementPanel snap={snap({ my_jail: { board_key: 'classic', jail_turns: 2, fine: 50 } })} busy={false} {...c} />);
    expect(screen.getByText(/Intento 3\/3/)).toBeInTheDocument();
  });

  it('cárcel: mensajes del intento de dobles (fallo / dobles / 3er forzado)', () => {
    const c = cbs();
    const base = snap().last_roll!;
    const failed = snap({ my_jail: { board_key: 'classic', jail_turns: 1, fine: 50 }, last_roll: { ...base, d1: 2, d2: 5, jail: 'failed' } });
    const { rerender } = render(<MovementPanel snap={failed} busy={false} {...c} />);
    expect(screen.getByText(/No has sacado dobles\. Sigues en la cárcel/)).toBeInTheDocument();
    const doubles = snap({ my_jail: null, last_roll: { ...base, d1: 4, d2: 4, jail: 'doubles' } });
    rerender(<MovementPanel snap={doubles} busy={false} {...c} />);
    expect(screen.getByText(/Has sacado dobles y sales de la cárcel/)).toBeInTheDocument();
    const forced = snap({ my_jail: null, last_roll: { ...base, d1: 2, d2: 3, jail: 'forced_paid' } });
    rerender(<MovementPanel snap={forced} busy={false} {...c} />);
    expect(screen.getByText(/Tercer intento fallido\. Pagas 50 ₥ y sales/)).toBeInTheDocument();
  });

  it('en la cárcel con carta: ofrece usar la carta «Sal de la cárcel gratis»', () => {
    const c = cbs();
    const s = snap({
      my_jail: { board_key: 'classic', jail_turns: 0, fine: 50 },
      my_held_cards: [{ card_ref: 'chance-jail-free', title: 'Sal de la cárcel gratis', description: '', deck_key: 'chance', effect_type: 'jail_free' }],
    });
    render(<MovementPanel snap={s} busy={false} {...c} />);
    fireEvent.click(screen.getByRole('button', { name: /Usar carta/ }));
    expect(c.onUseJailCard).toHaveBeenCalledTimes(1);
  });

  it('pago pendiente (impuesto sin saldo): ofrece pagar y NO deja tirar', () => {
    const c = cbs();
    const s = snap({ pending_payment: { kind: 'tax', player_ref: 'P-1', amount: 100, board: 'classic', space_index: 38, space_name: 'Impuesto de lujo' } });
    render(<MovementPanel snap={s} busy={false} {...c} />);
    expect(screen.getByText(/Debes pagar/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Tirar dados/ })).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: /Pagar 100 ₥/ }));
    expect(c.onPayPending).toHaveBeenCalledTimes(1);
  });

  it('muestra el bote de Parking y el inventario de cartas', () => {
    const c = cbs();
    const s = snap({
      parking_pot: 250,
      my_held_cards: [{ card_ref: 'chance-jail-free', title: 'Sal de la cárcel gratis', description: '', deck_key: 'chance', effect_type: 'jail_free' }],
    });
    render(<MovementPanel snap={s} busy={false} {...c} />);
    expect(screen.getByText('Bote Parking')).toBeInTheDocument();
    expect(screen.getByText('250 ₥')).toBeInTheDocument();
    expect(screen.getByText(/Sal de la cárcel gratis/)).toBeInTheDocument();
  });

  it('nota del efecto de casilla: impuesto pagado y bote cobrado', () => {
    const c = cbs();
    const base = snap().last_move!;
    const taxS = snap({ last_move: { ...base, effect: { type: 'tax', name: 'Impuesto de lujo', amount: 100, paid: true } } });
    const { rerender } = render(<MovementPanel snap={taxS} busy={false} {...c} />);
    expect(screen.getByText(/Has pagado 100 ₥ de impuesto/)).toBeInTheDocument();
    const parkS = snap({ last_move: { ...base, effect: { type: 'parking', payout: 300 } } });
    rerender(<MovementPanel snap={parkS} busy={false} {...c} />);
    expect(screen.getByText(/Has cobrado el bote de Parking: 300 ₥/)).toBeInTheDocument();
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
