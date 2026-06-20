import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { PropertyCardModal } from './PropertyCardModal';
import { PropertiesSummary } from './PropertiesSummary';
import { canBuildHouse, canBuildHotel, canMortgage, canUnmortgage, canSellHouse } from '../../lib/activeSelectors';

// Grupo marron (2 calles) en Classic; "me" = P-1 posee ambas (monopolio).
function snap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only' } },
    me: { public_ref: 'P-1', is_host: false, balance: 3000, is_current: true, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-1', order: ['P-1', 'P-2'] },
    players: [
      { public_ref: 'P-1', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true, status: 'active' },
      { public_ref: 'P-2', display_name: 'Beto', token_id: 'boot', balance: null, is_current: false, status: 'active' },
    ],
    ledger_recent: [],
    properties: [
      { property_ref: 'cl-m1', board_key: 'classic', group_key: 'marron', name: 'Mediterráneo', kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 1, owner_ref: 'P-1', in_auction: false, rent_1: 10, rent_4: 160, rent_hotel: 250, house_cost: 50, hotel_cost: 50, mortgage_value: 30, unmortgage_cost: 33, houses: 0, has_hotel: false, mortgaged: false, monopoly: true, rent_due: 4 },
      { property_ref: 'cl-m2', board_key: 'classic', group_key: 'marron', name: 'Báltico', kind: 'street', price: 60, base_rent: 4, is_buyable: true, sort_order: 2, owner_ref: 'P-1', in_auction: false, house_cost: 50, hotel_cost: 50, mortgage_value: 30, unmortgage_cost: 33, houses: 0, has_hotel: false, mortgaged: false, monopoly: true, rent_due: 8 },
    ],
    auctions: [], purchase_requests: [], leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [{ board_key: 'classic', ring_size: 40, start_bonus: 200, provisional: false }],
    spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null, card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null, last_global_event: null, positions: [],
    my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running', current_landing_rent_resolved: false,
    building_stock: { houses_available: 32, hotels_available: 12 },
    control: { paused_by_ref: null, finished_by_ref: null, reason: null }, runtime_version: 1,
    ...over,
  };
}
const prop = (s: ActiveSnapshot, ref: string) => s.properties.find((p) => p.property_ref === ref)!;
const actions = () => ({ onBuildHouse: vi.fn(), onBuildHotel: vi.fn(), onSellHouse: vi.fn(), onSellHotel: vi.fn(), onMortgage: vi.fn(), onUnmortgage: vi.fn() });

describe('selectores de construcción (Fase 6)', () => {
  it('con monopolio sin casas: puede construir casa e hipotecar; no hotel ni vender', () => {
    const s = snap(); const p = prop(s, 'cl-m1');
    expect(canBuildHouse(p, s)).toBe(true);
    expect(canMortgage(p, s)).toBe(true);
    expect(canBuildHotel(p, s)).toBe(false);
    expect(canSellHouse(p, s)).toBe(false);
  });
  it('sin monopolio no puede construir', () => {
    const s = snap({ properties: snap().properties.map((p) => ({ ...p, monopoly: false })) });
    expect(canBuildHouse(prop(s, 'cl-m1'), s)).toBe(false);
  });
  it('con 4 casas puede construir hotel (no casa); con hotel puede deshipotecar tras hipotecar', () => {
    const s = snap({ properties: snap().properties.map((p) => p.property_ref === 'cl-m1' ? { ...p, houses: 4 } : { ...p, houses: 4 }) });
    expect(canBuildHotel(prop(s, 'cl-m1'), s)).toBe(true);
    expect(canBuildHouse(prop(s, 'cl-m1'), s)).toBe(false);
  });
  it('hipotecada: no construir, sí deshipotecar', () => {
    const s = snap({ properties: snap().properties.map((p) => p.property_ref === 'cl-m1' ? { ...p, mortgaged: true } : p) });
    expect(canBuildHouse(prop(s, 'cl-m1'), s)).toBe(false);
    expect(canUnmortgage(prop(s, 'cl-m1'), s)).toBe(true);
  });
});

describe('PropertyCardModal (Fase 6)', () => {
  it('muestra construcción/monopolio y ofrece construir casa e hipotecar; los callbacks se invocan', () => {
    const s = snap(); const a = actions();
    render(<PropertyCardModal property={prop(s, 'cl-m1')} snap={s} onClose={vi.fn()} busy={false} actions={a} />);
    expect(screen.getByText('Sin construir')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Construir casa/ }));
    expect(a.onBuildHouse).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole('button', { name: /Hipotecar/ }));
    expect(a.onMortgage).toHaveBeenCalledTimes(1);
  });

  it('sin monopolio explica que se necesita el grupo completo y no ofrece construir', () => {
    const s = snap({ properties: snap().properties.map((p) => ({ ...p, monopoly: false })) });
    render(<PropertyCardModal property={prop(s, 'cl-m1')} snap={s} onClose={vi.fn()} actions={actions()} />);
    expect(screen.getByText(/Necesitas tener el grupo de color completo/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Construir casa/ })).toBeNull();
  });

  it('propiedad de otro hipotecada avisa "no se debe alquiler"', () => {
    const s = snap({ properties: snap().properties.map((p) => p.property_ref === 'cl-m1' ? { ...p, owner_ref: 'P-2', mortgaged: true, rent_due: 0 } : p) });
    render(<PropertyCardModal property={prop(s, 'cl-m1')} snap={s} onClose={vi.fn()} actions={actions()} />);
    expect(screen.getByText(/Propiedad hipotecada\. No se debe alquiler/)).toBeInTheDocument();
  });
});

describe('PropertiesSummary — stock de banco (Fase 6)', () => {
  it('muestra casas y hoteles disponibles', () => {
    render(<PropertiesSummary snap={snap()} onOpenBoard={vi.fn()} />);
    expect(screen.getByText('Casas disponibles')).toBeInTheDocument();
    expect(screen.getByText('32')).toBeInTheDocument();
    expect(screen.getByText('Hoteles disponibles')).toBeInTheDocument();
    expect(screen.getByText('12')).toBeInTheDocument();
  });
});
