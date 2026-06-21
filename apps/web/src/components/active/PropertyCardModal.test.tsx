import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { ActiveProperty, ActiveSnapshot } from '../../lib/activeSnapshot';
import { PropertyCardModal } from './PropertyCardModal';

function snap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false, allow_trade_built_properties: false, parking_mode: 'pot' } },
    me: { public_ref: 'P-1', is_host: false, balance: 3000, is_current: true, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-1', order: ['P-1', 'P-2'] },
    players: [
      { public_ref: 'P-1', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true, status: 'active' },
      { public_ref: 'P-2', display_name: 'Beto', token_id: 'boot', balance: 3000, is_current: false, status: 'active' },
    ],
    ledger_recent: [], properties: [], auctions: [], purchase_requests: [],
    leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [], spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null, card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null, last_global_event: null, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running', current_landing_rent_resolved: false, building_stock: { houses_available: 32, hotels_available: 12 }, building_requests: [], my_building_requests: [], incoming_trades: [], outgoing_trades: [], trade_reviews: [], recent_trades: [], control: { paused_by_ref: null, finished_by_ref: null, reason: null }, runtime_version: 1,
    ...over,
  };
}

const street: ActiveProperty = {
  property_ref: 'cl-ronda-valencia', board_key: 'classic', group_key: 'marron', name: 'Ronda de Valencia',
  kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 1, owner_ref: null, in_auction: false,
  rent_1: 10, rent_2: 30, rent_3: 90, rent_4: 160, rent_hotel: 250, house_cost: 50, hotel_cost: 50,
  mortgage_value: 30, unmortgage_cost: 33,
};

describe('PropertyCardModal', () => {
  it('muestra precio, alquileres, construcción e hipoteca', () => {
    render(<PropertyCardModal property={street} snap={snap()} onClose={vi.fn()} />);
    const dialog = screen.getByRole('dialog', { name: 'Ficha de Ronda de Valencia' });
    expect(dialog).toHaveTextContent('Ronda de Valencia');
    expect(dialog).toHaveTextContent('Con 1 casa');
    expect(dialog).toHaveTextContent('Con hotel');
    expect(dialog).toHaveTextContent('250 €');   // alquiler con hotel
    expect(dialog).toHaveTextContent('Coste por casa');
    expect(dialog).toHaveTextContent('Valor de hipoteca');
    expect(dialog).toHaveTextContent('Deshipotecar');
  });

  it('NO muestra acciones de construir/hipotecar (solo consulta)', () => {
    render(<PropertyCardModal property={street} snap={snap()} onClose={vi.fn()} />);
    expect(screen.queryByRole('button', { name: /construir|edificar|hipotecar/i })).toBeNull();
  });

  it('campos ausentes (en una calle) se muestran como "Pendiente de confirmar"', () => {
    const incomplete: ActiveProperty = {
      ...street, rent_1: null, rent_2: null, rent_3: null, rent_4: null, rent_hotel: null, house_cost: null, hotel_cost: null,
    };
    render(<PropertyCardModal property={incomplete} snap={snap()} onClose={vi.fn()} />);
    expect(screen.getAllByText('Pendiente de confirmar').length).toBeGreaterThan(0);
  });

  it('una utility (servicio) NO muestra casas/hotel/construcción; muestra la escala ×4..×20', () => {
    const utility: ActiveProperty = {
      ...street, property_ref: 'cl-cia-aguas', name: 'Compañía de Aguas', kind: 'utility', group_key: 'servicios',
      base_rent: 0, rent_1: null, rent_2: null, rent_3: null, rent_4: null, rent_hotel: null, house_cost: null, hotel_cost: null,
      mortgage_value: 75, unmortgage_cost: 83,
    };
    const dialog = render(<PropertyCardModal property={utility} snap={snap()} onClose={vi.fn()} />).container;
    expect(dialog).not.toHaveTextContent('Con 1 casa');
    expect(dialog).not.toHaveTextContent('Coste por casa');
    expect(dialog).toHaveTextContent('2 servicios: tirada ×10');
    expect(dialog).toHaveTextContent('Los servicios se combinan entre ambos tableros');
    expect(dialog).toHaveTextContent('Valor de hipoteca'); // hipoteca se mantiene
  });

  it('una estación NO muestra casas/hotel; muestra la escala 1→25..8→600', () => {
    const station: ActiveProperty = {
      ...street, property_ref: 'cl-estacion-norte', name: 'Estación del Norte', kind: 'station', group_key: 'estaciones',
      rent_1: null, rent_2: null, rent_3: null, rent_4: null, rent_hotel: null, house_cost: null, hotel_cost: null,
    };
    const dialog = render(<PropertyCardModal property={station} snap={snap()} onClose={vi.fn()} />).container;
    expect(dialog).not.toHaveTextContent('Con 1 casa');
    expect(dialog).not.toHaveTextContent('Coste por casa');
    expect(dialog).toHaveTextContent('4 → 200 €');
    expect(dialog).toHaveTextContent('Las estaciones y transportes se combinan entre ambos tableros');
  });

  it('estado refleja al propietario', () => {
    const owned: ActiveProperty = { ...street, owner_ref: 'P-2' };
    render(<PropertyCardModal property={owned} snap={snap()} onClose={vi.fn()} />);
    expect(screen.getByRole('dialog')).toHaveTextContent('De otro jugador (Beto)');
  });

  it('"Cerrar" llama onClose', () => {
    const onClose = vi.fn();
    render(<PropertyCardModal property={street} snap={snap()} onClose={onClose} />);
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('el backdrop es el ÚNICO scroller; la tarjeta y su cuerpo crecen con el contenido (NADA se comprime)', () => {
    const { container } = render(<PropertyCardModal property={street} snap={snap()} onClose={vi.fn()} />);
    // El backdrop scrollea (patrón robusto iOS/iPadOS).
    const backdrop = container.querySelector('[data-testid="property-card-backdrop"]') as HTMLElement;
    expect(backdrop).not.toBeNull();
    expect(backdrop.className).toMatch(/overflow-y-(auto|scroll)/);
    expect(backdrop.className).toContain('touch-pan-y');
    expect(backdrop.className).toContain('overscroll-contain');
    // El cuerpo NO comprime ni recorta: sin overflow propio, sin altura máxima, sin flex-shrink (min-h-0).
    const body = container.querySelector('[data-testid="property-card-body"]') as HTMLElement;
    expect(body).not.toBeNull();
    expect(body.className).not.toMatch(/overflow-y-(scroll|auto)/); // no scroll interno
    expect(body.className).not.toMatch(/max-h-/);                   // no altura máxima que recorte
    expect(body.className).not.toContain('min-h-0');               // no se encoge
    // Ningún apartado tiene scroll anidado propio (causa de los fallos en iPad).
    expect(container.querySelectorAll('[data-testid="property-card-body"] .overscroll-contain').length).toBe(0);
  });

  it('las tres secciones existen con su testid y TODO su contenido (incl. botones) vive dentro de cada apartado', () => {
    const mineStreet: ActiveProperty = { ...street, owner_ref: 'P-1', monopoly: true, houses: 0, mortgaged: false };
    const s = snap({ properties: [mineStreet], me: { public_ref: 'P-1', is_host: false, balance: 99999, is_current: true, is_spectator: false } });
    const { container } = render(<PropertyCardModal property={mineStreet} snap={s} onClose={vi.fn()} actions={{ onBuildHouse: vi.fn(), onMortgage: vi.fn() }} />);
    expect(container.querySelector('[data-testid="property-card-section-rents"]')).not.toBeNull();
    const construction = container.querySelector('[data-testid="property-card-section-construction"]')!;
    expect(construction.textContent).toContain('Solicitar construir casa'); // botón dentro del apartado
    const mortgage = container.querySelector('[data-testid="property-card-section-mortgage"]')!;
    expect(mortgage.textContent).toContain('Hipotecar');                    // botón dentro del apartado
  });
});
