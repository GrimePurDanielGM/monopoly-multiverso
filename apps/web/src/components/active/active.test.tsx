import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { TurnBanner } from './TurnBanner';
import { PlayerBalances } from './PlayerBalances';
import { PlayerTransferForm } from './PlayerTransferForm';
import { BankPanel } from './BankPanel';
import { HostCorrections } from './HostCorrections';
import { LedgerList } from './LedgerList';
import { RevertDialog } from './RevertDialog';
import { LateJoinTray } from './LateJoinTray';
import { PropertiesPanel } from './PropertiesPanel';
import { AuctionsPanel } from './AuctionsPanel';
import { PurchaseRequestsTray, LeaveRequestsTray, BankruptcyRequestsTray } from './HostRequestTrays';
import { BankruptcyDialog } from './BankruptcyDialog';
import type { ActiveProperty, PropertyAuction } from '../../lib/activeSnapshot';

function makeSnap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16, allow_late_join: false } },
    me: { public_ref: 'P-BBBB', is_host: true, balance: 1000, is_current: false, is_spectator: false },
    turn: { turn_number: 5, current_player_ref: 'P-AAAA', order: ['P-AAAA', 'P-BBBB'] },
    players: [
      { public_ref: 'P-AAAA', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true, status: 'active' },
      { public_ref: 'P-BBBB', display_name: 'Beto', token_id: 'boot', balance: 1000, is_current: false, status: 'active' },
    ],
    ledger_recent: [],
    properties: [],
    auctions: [],
    purchase_requests: [],
    leave_requests: [],
    bankruptcy_requests: [],
    late_join_requests: [],
    runtime_status: 'running',
    control: { paused_by_ref: null, finished_by_ref: null, reason: null },
    runtime_version: 7,
    ...over,
  };
}

describe('TurnBanner', () => {
  it('muestra "Turno de Ana" cuando no es mi turno', () => {
    render(<TurnBanner snap={makeSnap()} />);
    expect(screen.getByText(/Turno de Ana/)).toBeInTheDocument();
  });
  it('muestra "Tu turno" cuando es mi turno', () => {
    render(<TurnBanner snap={makeSnap({ me: { public_ref: 'P-AAAA', is_host: true, balance: 1, is_current: true, is_spectator: false } })} />);
    expect(screen.getByText('Tu turno')).toBeInTheDocument();
  });
});

describe('PlayerBalances', () => {
  it('muestra saldos y "Tú"', () => {
    render(<PlayerBalances snap={makeSnap()} icons={{ cat: '🐱', boot: '🥾' }} />);
    expect(screen.getByText(/3\.000/)).toBeInTheDocument();
    expect(screen.getByText('Tú')).toBeInTheDocument();
  });

  it('jugador normal solo ve "Abandonar partida" en su propia fila (nunca "Sacar jugador")', () => {
    const onLeave = vi.fn();
    const onRemove = vi.fn();
    // soy P-AAAA (no anfitrión)
    const snap = makeSnap({ me: { public_ref: 'P-AAAA', is_host: false, balance: 3000, is_current: true, is_spectator: false } });
    render(<PlayerBalances snap={snap} icons={{}} isHost={false} onLeave={onLeave} onRemove={onRemove} />);
    expect(screen.getByRole('button', { name: 'Abandonar partida' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Sacar jugador' })).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Abandonar partida' }));
    expect(onLeave).toHaveBeenCalledTimes(1);
  });

  it('anfitrión ve "Sacar jugador" en otros y NO en su propia fila ni "Abandonar"', () => {
    const onRemove = vi.fn();
    // soy P-BBBB (anfitrión); el otro es P-AAAA
    const snap = makeSnap({ me: { public_ref: 'P-BBBB', is_host: true, balance: 1000, is_current: false, is_spectator: false } });
    render(<PlayerBalances snap={snap} icons={{}} isHost onLeave={vi.fn()} onRemove={onRemove} />);
    const removes = screen.getAllByRole('button', { name: 'Sacar jugador' });
    expect(removes).toHaveLength(1); // solo sobre el otro jugador, no sobre el anfitrión
    expect(screen.queryByRole('button', { name: 'Abandonar partida' })).toBeNull();
    fireEvent.click(removes[0]!);
    expect(onRemove).toHaveBeenCalledWith('P-AAAA', 'Ana');
  });

  it('deshabilita las acciones mientras se procesa', () => {
    const snap = makeSnap({ me: { public_ref: 'P-AAAA', is_host: false, balance: 3000, is_current: true, is_spectator: false } });
    render(<PlayerBalances snap={snap} icons={{}} isHost={false} disabled onLeave={vi.fn()} />);
    expect(screen.getByRole('button', { name: 'Abandonar partida' })).toBeDisabled();
  });

  it('muestra cuántas propiedades tiene cada jugador', () => {
    const snap = makeSnap({
      properties: [
        { property_ref: 'a', board_key: 'classic', group_key: 'm', name: 'Mediterráneo', kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 1, owner_ref: 'P-AAAA', in_auction: false },
        { property_ref: 'b', board_key: 'classic', group_key: 'm', name: 'Báltico', kind: 'street', price: 60, base_rent: 4, is_buyable: true, sort_order: 2, owner_ref: 'P-AAAA', in_auction: false },
      ],
    });
    render(<PlayerBalances snap={snap} icons={{}} />);
    expect(screen.getByText('2 propiedades')).toBeInTheDocument();
  });
});

describe('PlayerTransferForm', () => {
  it('transferencia válida llama onTransfer con el importe', () => {
    const onTransfer = vi.fn();
    render(<PlayerTransferForm snap={makeSnap()} busy={false} onTransfer={onTransfer} />);
    fireEvent.change(screen.getByLabelText('Importe'), { target: { value: '500' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enviar' }));
    expect(onTransfer).toHaveBeenCalledWith('P-AAAA', 500);
  });
  it('fondos insuficientes deshabilita y avisa', () => {
    const onTransfer = vi.fn();
    render(<PlayerTransferForm snap={makeSnap()} busy={false} onTransfer={onTransfer} />);
    fireEvent.change(screen.getByLabelText('Importe'), { target: { value: '5000' } });
    expect(screen.getByText('Saldo insuficiente.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Enviar' })).toBeDisabled();
  });
});

describe('BankPanel', () => {
  it('pagar y cobrar llaman onBank con la dirección correcta', () => {
    const onBank = vi.fn();
    render(<BankPanel snap={makeSnap()} busy={false} onBank={onBank} />);
    fireEvent.change(screen.getByLabelText('Importe'), { target: { value: '300' } });
    fireEvent.click(screen.getByRole('button', { name: 'Pagar al jugador' }));
    expect(onBank).toHaveBeenCalledWith('P-AAAA', 'to_player', 300);
    fireEvent.click(screen.getByRole('button', { name: 'Cobrar al jugador' }));
    expect(onBank).toHaveBeenCalledWith('P-AAAA', 'from_player', 300);
  });
});

describe('HostCorrections', () => {
  it('ajustar saldo exige motivo (deshabilitado sin él)', () => {
    const onAdjust = vi.fn();
    render(<HostCorrections snap={makeSnap()} busy={false} onAdjust={onAdjust} onSetTurn={vi.fn()} onHostTransfer={vi.fn()} />);
    const balInput = screen.getByLabelText('Nuevo saldo');
    fireEvent.change(balInput, { target: { value: '9000' } });
    const btn = screen.getByRole('button', { name: 'Ajustar saldo' });
    expect(btn).toBeDisabled(); // sin motivo
    const reason = screen.getAllByLabelText('Motivo (obligatorio)')[0]!;
    fireEvent.change(reason, { target: { value: 'corrección válida' } });
    fireEvent.click(btn);
    expect(onAdjust).toHaveBeenCalledWith('P-AAAA', 9000, 'corrección válida');
  });
});

describe('LedgerList', () => {
  const snap = makeSnap({
    ledger_recent: [
      { ledger_ref: 'L-PAY', seq: 3, kind: 'bank_to_player', from_ref: null, to_ref: 'P-AAAA', amount: 100, before_balance: null, after_balance: null, reason: null, actor_ref: 'P-BBBB', reverts_ref: null, created_at: 't' },
      { ledger_ref: 'L-SEED', seq: 1, kind: 'seed', from_ref: null, to_ref: 'P-AAAA', amount: 3000, before_balance: null, after_balance: null, reason: null, actor_ref: null, reverts_ref: null, created_at: 't' },
    ],
  });
  it('host puede revertir solo los reversibles; onRevert recibe ledger_ref', () => {
    const onRevert = vi.fn();
    render(<LedgerList snap={snap} isHost busy={false} onRevert={onRevert} />);
    const reverts = screen.getAllByRole('button', { name: 'Revertir' });
    expect(reverts).toHaveLength(1); // seed no es reversible
    fireEvent.click(reverts[0]!);
    expect(onRevert).toHaveBeenCalledWith('L-PAY');
  });
  it('no-host no ve botones de revertir', () => {
    render(<LedgerList snap={snap} isHost={false} busy={false} onRevert={vi.fn()} />);
    expect(screen.queryByRole('button', { name: 'Revertir' })).toBeNull();
  });
});

describe('LateJoinTray', () => {
  const snap = makeSnap({
    late_join_requests: [{ request_ref: 'L-REQ1', name: 'Nuevo', token: 'cat', device_label: 'iPad' }],
  });
  it('muestra la solicitud separada con aviso de saldo/orden y resuelve', () => {
    const onResolve = vi.fn();
    render(<LateJoinTray snap={snap} icons={{ cat: '🐱' }} busy={false} onResolve={onResolve} />);
    expect(screen.getByText(/Solicitudes para entrar en la partida/)).toBeInTheDocument();
    expect(screen.getByText(/se añadirán al final del orden/)).toBeInTheDocument();
    expect(screen.getByText('Nuevo')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Aceptar' }));
    expect(onResolve).toHaveBeenCalledWith('L-REQ1', true);
    fireEvent.click(screen.getByRole('button', { name: 'Rechazar' }));
    expect(onResolve).toHaveBeenCalledWith('L-REQ1', false);
  });
  it('sin solicitudes no renderiza nada', () => {
    const { container } = render(<LateJoinTray snap={makeSnap()} icons={{}} busy={false} onResolve={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
  });
});

describe('PropertiesPanel', () => {
  const prop = (over: Partial<ActiveProperty> = {}): ActiveProperty => ({
    property_ref: 'cl-marron-1', board_key: 'classic', group_key: 'marron', name: 'Mediterráneo',
    kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 10, owner_ref: null, in_auction: false, ...over,
  });
  // me = P-BBBB (host, saldo 1000 en makeSnap).
  const withProps = (props: ActiveProperty[], over = {}) => makeSnap({ properties: props, ...over });

  it('muestra propiedades por tablero con precio y alquiler', () => {
    render(<PropertiesPanel snap={withProps([prop()])} busy={false} onRequestPurchase={vi.fn()} onPayRent={vi.fn()} />);
    expect(screen.getByText('Clásico')).toBeInTheDocument();
    expect(screen.getByText('Mediterráneo')).toBeInTheDocument();
    expect(screen.getByText(/Precio 60/)).toBeInTheDocument();
  });

  it('disponible: "Solicitar compra" llama onRequestPurchase', () => {
    const onReq = vi.fn();
    render(<PropertiesPanel snap={withProps([prop({ price: 60 })])} busy={false} onRequestPurchase={onReq} onPayRent={vi.fn()} />);
    const btn = screen.getByRole('button', { name: 'Solicitar compra' });
    expect(btn).toBeEnabled();
    fireEvent.click(btn);
    expect(onReq).toHaveBeenCalledTimes(1);
  });

  it('en subasta: muestra "En subasta" sin botón de compra', () => {
    render(<PropertiesPanel snap={withProps([prop({ in_auction: true })])} busy={false} onRequestPurchase={vi.fn()} onPayRent={vi.fn()} />);
    expect(screen.getByText('En subasta')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Solicitar compra' })).toBeNull();
  });

  it('de otro jugador: "Pagar alquiler" llama onPayRent', () => {
    const onRent = vi.fn();
    render(<PropertiesPanel snap={withProps([prop({ owner_ref: 'P-AAAA', base_rent: 25 })])} busy={false} onRequestPurchase={vi.fn()} onPayRent={onRent} />);
    fireEvent.click(screen.getByRole('button', { name: 'Pagar alquiler' }));
    expect(onRent).toHaveBeenCalledTimes(1);
  });

  it('mía: muestra "Tuya" y aparece en "Mis propiedades", sin botones de acción', () => {
    render(<PropertiesPanel snap={withProps([prop({ owner_ref: 'P-BBBB' })])} busy={false} onRequestPurchase={vi.fn()} onPayRent={vi.fn()} />);
    expect(screen.getAllByText('Tuya').length).toBeGreaterThan(0);
    expect(screen.queryByRole('button', { name: 'Solicitar compra' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Pagar alquiler' })).toBeNull();
  });

  it('en pausa: aviso y acciones deshabilitadas', () => {
    render(<PropertiesPanel snap={withProps([prop()], { runtime_status: 'paused' })} busy={false} onRequestPurchase={vi.fn()} onPayRent={vi.fn()} />);
    expect(screen.getByText(/solo puedes consultar las propiedades/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Solicitar compra' })).toBeDisabled();
  });

  it('espectador (en bancarrota): aviso y acciones deshabilitadas', () => {
    const s = makeSnap({ properties: [prop()], me: { public_ref: 'P-BBBB', is_host: false, balance: 1000, is_current: false, is_spectator: true } });
    render(<PropertiesPanel snap={s} busy={false} onRequestPurchase={vi.fn()} onPayRent={vi.fn()} />);
    expect(screen.getByText(/en bancarrota: solo puedes consultar/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Solicitar compra' })).toBeDisabled();
  });
});

describe('RevertDialog', () => {
  it('exige motivo y confirma con él', () => {
    const onConfirm = vi.fn();
    render(<RevertDialog open busy={false} onConfirm={onConfirm} onCancel={vi.fn()} />);
    const btn = screen.getByRole('button', { name: 'Revertir' });
    expect(btn).toBeDisabled();
    fireEvent.change(screen.getByLabelText('Motivo (obligatorio)'), { target: { value: 'me equivoqué' } });
    fireEvent.click(btn);
    expect(onConfirm).toHaveBeenCalledWith('me equivoqué');
  });
});

describe('AuctionsPanel', () => {
  const auc = (over: Partial<PropertyAuction> = {}): PropertyAuction => ({
    auction_ref: 'A-1', property_ref: 'cl-prado', property_name: 'Paseo del Prado',
    high_bid: 100, high_bidder_ref: 'P-AAAA', started_by_ref: 'P-AAAA', ...over,
  });
  it('muestra la puja actual y pujar llama onBid con el importe', () => {
    const onBid = vi.fn();
    // me = P-BBBB saldo 1000; puja mínima 101
    const s = makeSnap({ auctions: [auc()] });
    render(<AuctionsPanel snap={s} isHost={false} busy={false} onBid={onBid} onClose={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.getByText('Paseo del Prado')).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('Tu puja'), { target: { value: '150' } });
    fireEvent.click(screen.getByRole('button', { name: 'Pujar' }));
    expect(onBid).toHaveBeenCalledWith(expect.objectContaining({ auction_ref: 'A-1' }), 150);
  });
  it('el anfitrión ve cerrar/cancelar', () => {
    const onClose = vi.fn(); const onCancel = vi.fn();
    render(<AuctionsPanel snap={makeSnap({ auctions: [auc()] })} isHost busy={false} onBid={vi.fn()} onClose={onClose} onCancel={onCancel} />);
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar subasta' }));
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }));
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(onCancel).toHaveBeenCalledTimes(1);
  });
  it('sin subastas no renderiza nada', () => {
    const { container } = render(<AuctionsPanel snap={makeSnap()} isHost={false} busy={false} onBid={vi.fn()} onClose={vi.fn()} onCancel={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
  });
});

describe('Bandejas del anfitrión', () => {
  it('PurchaseRequestsTray: aprobar / rechazar / subastar', () => {
    const onResolve = vi.fn(); const onAuction = vi.fn();
    const s = makeSnap({ purchase_requests: [{ request_ref: 'PR-1', property_ref: 'cl-bailen', property_name: 'Calle Bailén', requester_ref: 'P-AAAA', requester_name: 'Ana' }] });
    render(<PurchaseRequestsTray snap={s} busy={false} onResolve={onResolve} onAuction={onAuction} />);
    expect(screen.getByText(/Ana.*Calle Bailén|quiere Calle Bailén/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Aprobar' }));
    expect(onResolve).toHaveBeenCalledWith(expect.objectContaining({ request_ref: 'PR-1' }), true);
    fireEvent.click(screen.getByRole('button', { name: 'Subastar' }));
    expect(onAuction).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole('button', { name: 'Rechazar' }));
    expect(onResolve).toHaveBeenCalledWith(expect.objectContaining({ request_ref: 'PR-1' }), false);
  });
  it('LeaveRequestsTray: aprobar con destino del dinero / rechazar', () => {
    const onResolve = vi.fn();
    const s = makeSnap({ leave_requests: [{ request_ref: 'LR-1', requester_ref: 'P-AAAA', requester_name: 'Ana' }] });
    render(<LeaveRequestsTray snap={s} busy={false} onResolve={onResolve} />);
    fireEvent.click(screen.getByRole('button', { name: 'Aprobar · a la banca' }));
    expect(onResolve).toHaveBeenCalledWith(expect.objectContaining({ request_ref: 'LR-1' }), true, 'to_bank');
    fireEvent.click(screen.getByRole('button', { name: 'Aprobar · repartir' }));
    expect(onResolve).toHaveBeenCalledWith(expect.objectContaining({ request_ref: 'LR-1' }), true, 'distribute');
  });
  it('BankruptcyRequestsTray: muestra tipo y acreedor; aprobar', () => {
    const onResolve = vi.fn();
    const s = makeSnap({ bankruptcy_requests: [{ request_ref: 'BR-1', requester_ref: 'P-AAAA', requester_name: 'Ana', kind: 'to_player', creditor_ref: 'P-BBBB', creditor_name: 'Beto', reason: 'sin fondos' }] });
    render(<BankruptcyRequestsTray snap={s} busy={false} onResolve={onResolve} />);
    expect(screen.getByText(/frente a/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Aprobar' }));
    expect(onResolve).toHaveBeenCalledWith(expect.objectContaining({ request_ref: 'BR-1' }), true);
  });
});

describe('BankruptcyDialog', () => {
  it('frente a banca exige motivo y confirma con (to_bank, null, motivo)', () => {
    const onConfirm = vi.fn();
    render(<BankruptcyDialog open snap={makeSnap()} busy={false} onConfirm={onConfirm} onCancel={vi.fn()} />);
    const btn = screen.getByRole('button', { name: 'Declararme en bancarrota' });
    expect(btn).toBeDisabled();
    fireEvent.change(screen.getByPlaceholderText(/motivo/i), { target: { value: 'me arruino' } });
    fireEvent.click(btn);
    expect(onConfirm).toHaveBeenCalledWith('to_bank', null, 'me arruino');
  });
});
