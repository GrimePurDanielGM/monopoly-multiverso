import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { ActiveSnapshot, ActiveProperty } from '../../lib/activeSnapshot';
import { PropertyCardModal } from './PropertyCardModal';
import { BuildingRequestsTray } from './HostRequestTrays';

// Calle propia (monopolio) del jugador local P-1, base para los flujos de solicitud.
function baseProp(over: Partial<ActiveProperty> = {}): ActiveProperty {
  return {
    property_ref: 'cl-m1', board_key: 'classic', group_key: 'marron', name: 'Mediterráneo', kind: 'street',
    price: 60, base_rent: 2, is_buyable: true, sort_order: 1, owner_ref: 'P-1', in_auction: false,
    rent_1: 10, rent_4: 160, rent_hotel: 250, house_cost: 50, hotel_cost: 50, mortgage_value: 30, unmortgage_cost: 33,
    houses: 0, has_hotel: false, mortgaged: false, monopoly: true, rent_due: 4, ...over,
  };
}
function snap(props: ActiveProperty[], over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false } },
    me: { public_ref: 'P-1', is_host: true, balance: 3000, is_current: true, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-1', order: ['P-1', 'P-2'] },
    players: [
      { public_ref: 'P-1', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true, status: 'active' },
      { public_ref: 'P-2', display_name: 'Beto', token_id: 'boot', balance: null, is_current: false, status: 'active' },
    ],
    ledger_recent: [], properties: props, auctions: [], purchase_requests: [], leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [{ board_key: 'classic', ring_size: 40, start_bonus: 200, provisional: false }],
    spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null,
    card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null,
    last_global_event: null, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running', current_landing_rent_resolved: false,
    building_stock: { houses_available: 32, hotels_available: 12 }, building_requests: [], my_building_requests: [],
    control: { paused_by_ref: null, finished_by_ref: null, reason: null }, runtime_version: 1, ...over,
  };
}

describe('PropertyCardModal — flujo de solicitud (Fase 6 pulido)', () => {
  it('el botón de construir es una SOLICITUD ("Solicitar construir casa")', () => {
    const p = baseProp(); const onBuildHouse = vi.fn();
    render(<PropertyCardModal property={p} snap={snap([p])} onClose={vi.fn()} actions={{ onBuildHouse }} />);
    fireEvent.click(screen.getByRole('button', { name: 'Solicitar construir casa (50 ₥)' }));
    expect(onBuildHouse).toHaveBeenCalledTimes(1);
  });

  it('si ya hay una solicitud pendiente, muestra "pendiente de aprobación" y oculta el botón', () => {
    const p = baseProp();
    render(<PropertyCardModal property={p} snap={snap([p], { my_building_requests: [{ property_ref: 'cl-m1', action: 'build_house' }] })} onClose={vi.fn()} actions={{ onBuildHouse: vi.fn() }} />);
    expect(screen.getByText(/solicitud pendiente de aprobación/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Solicitar construir casa/ })).toBeNull();
  });

  it('se REFRESCA desde el snapshot: con una prop obsoleta (0 casas) pero snap fresco (2 casas) muestra el estado nuevo', () => {
    const stale = baseProp({ houses: 0 });
    const fresh = baseProp({ houses: 2 });
    render(<PropertyCardModal property={stale} snap={snap([fresh])} onClose={vi.fn()} actions={{}} />);
    expect(screen.getByText('2 casas')).toBeInTheDocument();
  });

  it('hipotecar/deshipotecar siguen siendo directas (no solicitud)', () => {
    const p = baseProp({ mortgaged: true, rent_due: 0 });
    const onUnmortgage = vi.fn();
    render(<PropertyCardModal property={p} snap={snap([p])} onClose={vi.fn()} actions={{ onUnmortgage }} />);
    fireEvent.click(screen.getByRole('button', { name: /Deshipotecar/ }));
    expect(onUnmortgage).toHaveBeenCalledTimes(1);
  });
});

describe('BuildingRequestsTray — bandeja del anfitrión (Fase 6 pulido)', () => {
  const req = { request_ref: 'R1', property_ref: 'cl-m1', property_name: 'Mediterráneo', action: 'build_house' as const, requester_ref: 'P-2', requester_name: 'Beto' };

  it('no se renderiza si no hay solicitudes', () => {
    const { container } = render(<BuildingRequestsTray snap={snap([baseProp()])} busy={false} onResolve={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('lista la solicitud y permite aprobar/rechazar', () => {
    const onResolve = vi.fn();
    render(<BuildingRequestsTray snap={snap([baseProp()], { building_requests: [req] })} busy={false} onResolve={onResolve} />);
    expect(screen.getByText(/Beto/)).toBeInTheDocument();
    expect(screen.getByText(/construir una casa en Mediterráneo/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Aprobar' }));
    expect(onResolve).toHaveBeenCalledWith(req, true);
    fireEvent.click(screen.getByRole('button', { name: 'Rechazar' }));
    expect(onResolve).toHaveBeenCalledWith(req, false);
  });
});
