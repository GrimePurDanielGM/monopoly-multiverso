import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { ActiveSnapshot, ActiveProperty, TradeProposal } from '../../lib/activeSnapshot';
import { CreateTradeModal } from './CreateTradeModal';
import { TradesPanel } from './TradesPanel';
import { TradeReviewsTray } from './HostRequestTrays';

function prop(over: Partial<ActiveProperty>): ActiveProperty {
  return {
    property_ref: 'x', board_key: 'classic', group_key: 'marron', name: 'X', kind: 'street',
    price: 60, base_rent: 2, is_buyable: true, sort_order: 1, owner_ref: null, in_auction: false,
    rent_1: 10, rent_4: 160, rent_hotel: 250, house_cost: 50, hotel_cost: 50, mortgage_value: 30, unmortgage_cost: 33,
    houses: 0, has_hotel: false, mortgaged: false, monopoly: false, ...over,
  };
}
function snap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false } },
    me: { public_ref: 'P-1', is_host: false, balance: 3000, is_current: true, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-1', order: ['P-1', 'P-2'] },
    players: [
      { public_ref: 'P-1', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true, status: 'active' },
      { public_ref: 'P-2', display_name: 'Beto', token_id: 'boot', balance: null, is_current: false, status: 'active' },
    ],
    ledger_recent: [], properties: [], auctions: [], purchase_requests: [], leave_requests: [], bankruptcy_requests: [], late_join_requests: [],
    boards: [], spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null,
    card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null,
    last_global_event: null, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running', current_landing_rent_resolved: false,
    building_stock: { houses_available: 32, hotels_available: 12 }, building_requests: [], my_building_requests: [],
    incoming_trades: [], outgoing_trades: [], trade_reviews: [], recent_trades: [],
    control: { paused_by_ref: null, finished_by_ref: null, reason: null }, runtime_version: 1, ...over,
  };
}
function trade(over: Partial<TradeProposal> = {}): TradeProposal {
  return {
    trade_ref: 'TR1', from_ref: 'P-1', from_name: 'Ana', to_ref: 'P-2', to_name: 'Beto',
    from_money: 300, to_money: 0, from_properties: [], to_properties: [], from_cards: [], to_cards: [],
    agreement_text: null, status: 'pending', requires_host: false, pending_party: 'P-2', created_at: '2026-06-21', ...over,
  };
}

describe('CreateTradeModal (Fase 7)', () => {
  it('ofrecer dinero + seleccionar propiedad y enviar llama onSubmit con los términos', () => {
    const onSubmit = vi.fn();
    const mine = prop({ property_ref: 'cl-m1', name: 'Mediterráneo', owner_ref: 'P-1' });
    render(<CreateTradeModal snap={snap({ properties: [mine] })} fixedToRef={undefined} initial={undefined} onClose={vi.fn()} onSubmit={onSubmit} />);
    fireEvent.change(screen.getByLabelText('Dinero que ofrezco'), { target: { value: '250' } });
    fireEvent.click(screen.getAllByRole('checkbox')[0]!); // mi propiedad Mediterráneo
    fireEvent.click(screen.getByRole('button', { name: 'Enviar propuesta' }));
    expect(onSubmit).toHaveBeenCalledTimes(1);
    const [toRef, terms] = onSubmit.mock.calls[0]!;
    expect(toRef).toBe('P-2');
    expect(terms.fromMoney).toBe(250);
    expect(terms.fromProps).toContain('cl-m1');
  });

  it('una propiedad con construcciones no es seleccionable y lo indica', () => {
    const built = prop({ property_ref: 'cl-m1', name: 'Mediterráneo', owner_ref: 'P-1', houses: 2 });
    render(<CreateTradeModal snap={snap({ properties: [built] })} fixedToRef={undefined} initial={undefined} onClose={vi.fn()} onSubmit={vi.fn()} />);
    expect(screen.getByText('No disponible: tiene construcciones')).toBeInTheDocument();
    expect(screen.getAllByRole('checkbox')[0]).toBeDisabled();
  });

  it('una propiedad hipotecada se marca', () => {
    const mort = prop({ property_ref: 'cl-m1', name: 'Mediterráneo', owner_ref: 'P-1', mortgaged: true });
    render(<CreateTradeModal snap={snap({ properties: [mort] })} fixedToRef={undefined} initial={undefined} onClose={vi.fn()} onSubmit={vi.fn()} />);
    expect(screen.getAllByText('Hipotecada').length).toBeGreaterThan(0);
  });

  it('el acuerdo personal muestra el aviso de cumplimiento manual', () => {
    render(<CreateTradeModal snap={snap()} fixedToRef={undefined} initial={undefined} onClose={vi.fn()} onSubmit={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Acuerdo personal'), { target: { value: 'No te cobro 1 turno' } });
    expect(screen.getByText(/no lo hará cumplir automáticamente/i)).toBeInTheDocument();
  });
});

describe('TradesPanel (Fase 7)', () => {
  const actions = () => ({ onAccept: vi.fn(), onReject: vi.fn(), onCancel: vi.fn(), onCounter: vi.fn() });

  it('un trato recibido (me toca actuar) ofrece Aceptar/Rechazar/Contraofertar', () => {
    const a = actions();
    // Recibido por P-1: from P-2, pending_party=P-1.
    const t = trade({ trade_ref: 'TR2', from_ref: 'P-2', from_name: 'Beto', to_ref: 'P-1', to_name: 'Ana', pending_party: 'P-1' });
    render(<TradesPanel snap={snap({ incoming_trades: [t] })} onCreate={vi.fn()} actions={a} />);
    fireEvent.click(screen.getByRole('button', { name: 'Aceptar' }));
    expect(a.onAccept).toHaveBeenCalledWith(t);
    fireEvent.click(screen.getByRole('button', { name: 'Contraofertar' }));
    expect(a.onCounter).toHaveBeenCalledWith(t);
    fireEvent.click(screen.getByRole('button', { name: 'Rechazar' }));
    expect(a.onReject).toHaveBeenCalledWith(t);
  });

  it('un trato enviado pendiente del otro ofrece Cancelar y "Esperando"', () => {
    const a = actions();
    const t = trade({ trade_ref: 'TR3' }); // from P-1 (me), pending_party=P-2
    render(<TradesPanel snap={snap({ outgoing_trades: [t] })} onCreate={vi.fn()} actions={a} />);
    expect(screen.getByText(/Esperando a Beto/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }));
    expect(a.onCancel).toHaveBeenCalledWith(t);
  });

  it('un trato en host_review indica que espera al anfitrión', () => {
    const t = trade({ trade_ref: 'TR4', status: 'host_review', requires_host: true, pending_party: null });
    render(<TradesPanel snap={snap({ outgoing_trades: [t] })} onCreate={vi.fn()} actions={actions()} />);
    expect(screen.getByText(/Esperando la aprobación del anfitrión/)).toBeInTheDocument();
  });

  it('"Crear trato" llama onCreate', () => {
    const onCreate = vi.fn();
    render(<TradesPanel snap={snap()} onCreate={onCreate} actions={actions()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Crear trato' }));
    expect(onCreate).toHaveBeenCalledTimes(1);
  });

  it('el historial reciente se muestra', () => {
    const done = trade({ trade_ref: 'TRH', status: 'executed', pending_party: null });
    render(<TradesPanel snap={snap({ recent_trades: [done] })} onCreate={vi.fn()} actions={actions()} />);
    expect(screen.getByText(/Historial reciente/)).toBeInTheDocument();
  });
});

describe('TradeReviewsTray — bandeja del anfitrión (Fase 7)', () => {
  it('no se renderiza si no hay tratos', () => {
    const { container } = render(<TradeReviewsTray snap={snap()} busy={false} onResolve={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('muestra el resumen y permite aprobar/rechazar', () => {
    const onResolve = vi.fn();
    const t = trade({ trade_ref: 'TRV', status: 'host_review', requires_host: true, from_properties: [{ property_ref: 'cl-m1', name: 'Mediterráneo', mortgaged: false }], pending_party: null });
    render(<TradeReviewsTray snap={snap({ trade_reviews: [t] })} busy={false} onResolve={onResolve} />);
    expect(screen.getByText('Mediterráneo')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Aprobar' }));
    expect(onResolve).toHaveBeenCalledWith(t, true);
    fireEvent.click(screen.getByRole('button', { name: 'Rechazar' }));
    expect(onResolve).toHaveBeenCalledWith(t, false);
  });
});
