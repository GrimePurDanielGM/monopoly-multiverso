import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { ActiveProperty, ActiveSnapshot } from '../../lib/activeSnapshot';
import { PropertyCardModal } from './PropertyCardModal';

function prop(over: Partial<ActiveProperty>): ActiveProperty {
  return {
    property_ref: 'x', board_key: 'classic', group_key: 'marron', name: 'X', kind: 'street',
    price: 60, base_rent: 2, is_buyable: true, sort_order: 1, owner_ref: null, in_auction: false,
    rent_1: 10, rent_4: 160, rent_hotel: 250, house_cost: 50, hotel_cost: 50, mortgage_value: 30, unmortgage_cost: 33,
    houses: 0, has_hotel: false, mortgaged: false, monopoly: false, ...over,
  };
}
function snap(properties: ActiveProperty[], over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false } },
    me: { public_ref: 'P-1', is_host: false, balance: 3000, is_current: true, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-1', order: ['P-1'] },
    players: [{ public_ref: 'P-1', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true, status: 'active' }],
    ledger_recent: [], properties, auctions: [], purchase_requests: [], leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [], spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null,
    card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null,
    last_global_event: null, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running', current_landing_rent_resolved: false,
    building_stock: { houses_available: 32, hotels_available: 12 }, building_requests: [], my_building_requests: [],
    control: { paused_by_ref: null, finished_by_ref: null, reason: null }, runtime_version: 1, ...over,
  };
}

const A = prop({ property_ref: 'a', name: 'Alfa', sort_order: 1 });
const B = prop({ property_ref: 'b', name: 'Bravo', sort_order: 2 });
const C = prop({ property_ref: 'c', name: 'Charlie', sort_order: 3 });

describe('PropertyCardModal — navegación entre propiedades (item 5)', () => {
  it('Siguiente/Anterior recorren el contexto en orden (tablero + sort_order) y ciclan', () => {
    render(<PropertyCardModal property={A} snap={snap([A, B, C])} navScope="all" onClose={vi.fn()} />);
    expect(screen.getByRole('dialog', { name: 'Ficha de Alfa' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Propiedad siguiente' }));
    expect(screen.getByRole('dialog', { name: 'Ficha de Bravo' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Propiedad siguiente' }));
    expect(screen.getByRole('dialog', { name: 'Ficha de Charlie' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Propiedad siguiente' })); // cicla al principio
    expect(screen.getByRole('dialog', { name: 'Ficha de Alfa' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Propiedad anterior' }));
    expect(screen.getByRole('dialog', { name: 'Ficha de Charlie' })).toBeInTheDocument();
  });

  it('navScope="mine" recorre solo mis propiedades', () => {
    const mine1 = prop({ property_ref: 'm1', name: 'MíaUno', sort_order: 1, owner_ref: 'P-1' });
    const other = prop({ property_ref: 'o1', name: 'Ajena', sort_order: 2, owner_ref: 'P-2' });
    const mine2 = prop({ property_ref: 'm2', name: 'MíaDos', sort_order: 3, owner_ref: 'P-1' });
    render(<PropertyCardModal property={mine1} snap={snap([mine1, other, mine2])} navScope="mine" onClose={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Propiedad siguiente' }));
    expect(screen.getByRole('dialog', { name: 'Ficha de MíaDos' })).toBeInTheDocument(); // saltó la ajena
  });

  it('sin navScope no muestra navegación', () => {
    render(<PropertyCardModal property={A} snap={snap([A, B, C])} onClose={vi.fn()} />);
    expect(screen.queryByRole('button', { name: 'Propiedad siguiente' })).toBeNull();
  });

  it('al navegar muestra datos FRESCOS del snapshot (no la referencia con la que se abrió)', () => {
    // Se abre con A obsoleta (0 casas) pero el snapshot tiene A con 2 casas.
    const staleA = prop({ property_ref: 'a', name: 'Alfa', sort_order: 1, houses: 0 });
    const freshA = prop({ property_ref: 'a', name: 'Alfa', sort_order: 1, houses: 2, owner_ref: 'P-1' });
    render(<PropertyCardModal property={staleA} snap={snap([freshA, B])} navScope="all" onClose={vi.fn()} />);
    expect(screen.getByRole('dialog', { name: 'Ficha de Alfa' })).toHaveTextContent('2 casas');
  });
});

describe('PropertyCardModal — construir sin monopolio (item 2)', () => {
  const mineNoMono = prop({ property_ref: 'a', name: 'Alfa', owner_ref: 'P-1', monopoly: false });

  it('con la regla DESACTIVADA, sin monopolio explica que falta el grupo y no ofrece construir', () => {
    render(<PropertyCardModal property={mineNoMono} snap={snap([mineNoMono])} actions={{ onBuildHouse: vi.fn() }} onClose={vi.fn()} />);
    expect(screen.getByText(/Necesitas tener el grupo de color completo/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Solicitar construir casa/ })).toBeNull();
  });

  it('con la regla ACTIVADA, sin monopolio SÍ ofrece solicitar construir', () => {
    const s = snap([mineNoMono], { game: { ...snap([mineNoMono]).game, config: { ...snap([mineNoMono]).game.config, allow_build_without_monopoly: true } } });
    render(<PropertyCardModal property={mineNoMono} snap={s} actions={{ onBuildHouse: vi.fn() }} onClose={vi.fn()} />);
    expect(screen.queryByText(/Necesitas tener el grupo de color completo/)).toBeNull();
    expect(screen.getByRole('button', { name: /Solicitar construir casa/ })).toBeInTheDocument();
  });
});
