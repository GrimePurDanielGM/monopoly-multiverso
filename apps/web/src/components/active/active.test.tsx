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
import { PropertiesSummary } from './PropertiesSummary';
import { PropertyBoardModal } from './PropertyBoardModal';
import { AuctionsPanel } from './AuctionsPanel';
import { PurchaseRequestsTray, LeaveRequestsTray, BankruptcyRequestsTray } from './HostRequestTrays';
import { BankruptcyDialog } from './BankruptcyDialog';
import type { ActiveProperty, PropertyAuction } from '../../lib/activeSnapshot';

function makeSnap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16, allow_late_join: false, start_bonus: 200, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false } },
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
    boards: [{ board_key: 'classic', ring_size: 40, start_bonus: 200, provisional: false }, { board_key: 'back_to_the_future', ring_size: 29, start_bonus: 200, provisional: true }],
    spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null, card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null, last_global_event: null, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running',
    current_landing_rent_resolved: false, building_stock: { houses_available: 32, hotels_available: 12 }, building_requests: [], my_building_requests: [], incoming_trades: [], outgoing_trades: [], trade_reviews: [], recent_trades: [], control: { paused_by_ref: null, finished_by_ref: null, reason: null },
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

  it('privacidad: muestra mi saldo y oculta el ajeno (balance null → "Saldo oculto")', () => {
    // me = P-BBBB (saldo 1000); el otro (P-AAAA) llega con balance null.
    const s = makeSnap({
      players: [
        { public_ref: 'P-AAAA', display_name: 'Ana', token_id: 'cat', balance: null, is_current: true, status: 'active' },
        { public_ref: 'P-BBBB', display_name: 'Beto', token_id: 'boot', balance: 1000, is_current: false, status: 'active' },
      ],
    });
    render(<PlayerBalances snap={s} icons={{}} />);
    expect(screen.getByText('Saldo oculto')).toBeInTheDocument();
    expect(screen.getByText(/1\.000/)).toBeInTheDocument(); // mi saldo sí
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
  it('configuración de dados: cambiar el modo llama a onSetDiceMode', () => {
    const onSetDiceMode = vi.fn();
    render(<HostCorrections snap={makeSnap()} busy={false} onAdjust={vi.fn()} onSetTurn={vi.fn()} onHostTransfer={vi.fn()} onSetPosition={vi.fn()} onSetDiceMode={onSetDiceMode} />);
    const apply = screen.getByRole('button', { name: 'Aplicar modo de dados' });
    expect(apply).toBeDisabled(); // sin cambios respecto al modo actual
    fireEvent.change(screen.getByLabelText('Modo de dados'), { target: { value: 'physical_only' } });
    fireEvent.click(apply);
    expect(onSetDiceMode).toHaveBeenCalledWith('physical_only');
  });

  it('ajustar saldo exige motivo (deshabilitado sin él)', () => {
    const onAdjust = vi.fn();
    render(<HostCorrections snap={makeSnap()} busy={false} onAdjust={onAdjust} onSetTurn={vi.fn()} onHostTransfer={vi.fn()} onSetPosition={vi.fn()} onSetDiceMode={vi.fn()} />);
    const balInput = screen.getByLabelText('Nuevo saldo');
    fireEvent.change(balInput, { target: { value: '9000' } });
    const btn = screen.getByRole('button', { name: 'Ajustar saldo' });
    expect(btn).toBeDisabled(); // sin motivo
    const reason = screen.getAllByLabelText('Motivo (obligatorio)')[0]!;
    fireEvent.change(reason, { target: { value: 'corrección válida' } });
    fireEvent.click(btn);
    expect(onAdjust).toHaveBeenCalledWith('P-AAAA', 9000, 'corrección válida');
  });

  it('corregir posición: el selector de casilla muestra "índice — nombre" y envía el índice', () => {
    const onSetPosition = vi.fn();
    const snap = makeSnap({
      spaces: [
        { space_ref: 'cl-0', board_key: 'classic', space_index: 0, name: 'Salida', space_type: 'start', property_ref: null, is_start: true },
        { space_ref: 'cl-1', board_key: 'classic', space_index: 1, name: 'Ronda de Valencia', space_type: 'property', property_ref: 'cl-1', is_start: false },
        { space_ref: 'cl-5', board_key: 'classic', space_index: 5, name: 'Plaza de España', space_type: 'property', property_ref: 'cl-5', is_start: false },
      ],
    });
    render(<HostCorrections snap={snap} busy={false} onAdjust={vi.fn()} onSetTurn={vi.fn()} onHostTransfer={vi.fn()} onSetPosition={onSetPosition} onSetDiceMode={vi.fn()} />);
    const casilla = screen.getByLabelText(/Casilla/) as HTMLSelectElement;
    // Se puede elegir por nombre: la opción muestra índice + nombre.
    expect(screen.getByRole('option', { name: '1 — Ronda de Valencia' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: '5 — Plaza de España' })).toBeInTheDocument();
    fireEvent.change(casilla, { target: { value: '5' } });
    // El formulario de posición es el último; su "Motivo" es el último de la lista.
    const posReasons = screen.getAllByLabelText('Motivo (obligatorio)');
    fireEvent.change(posReasons[posReasons.length - 1]!, { target: { value: 'recolocar ficha' } });
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar posición' }));
    expect(onSetPosition).toHaveBeenCalledWith('P-AAAA', 'classic', 5, 'recolocar ficha');
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

const prop = (over: Partial<ActiveProperty> = {}): ActiveProperty => ({
  property_ref: 'cl-marron-1', board_key: 'classic', group_key: 'marron', name: 'Mediterráneo',
  kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 10, owner_ref: null, in_auction: false, ...over,
});

describe('PropertiesSummary (pantalla principal: resumen ligero)', () => {
  // me = P-BBBB (host) en makeSnap.
  it('muestra "Mis propiedades" y el botón abre el tablero (onOpenBoard)', () => {
    const onOpen = vi.fn();
    const s = makeSnap({ properties: [prop({ owner_ref: 'P-BBBB', name: 'Gran Vía' })] });
    render(<PropertiesSummary snap={s} onOpenBoard={onOpen} />);
    expect(screen.getByText(/Mis propiedades: 1/)).toBeInTheDocument();
    expect(screen.getByText('Gran Vía')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Ver tablero de propiedades' }));
    expect(onOpen).toHaveBeenCalledTimes(1);
  });

  it('NO renderiza el catálogo completo: una propiedad libre no aparece en el resumen', () => {
    const s = makeSnap({ properties: [prop({ name: 'Mediterráneo', owner_ref: null })] });
    render(<PropertiesSummary snap={s} onOpenBoard={vi.fn()} />);
    expect(screen.queryByText('Mediterráneo')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Solicitar compra' })).toBeNull();
  });

  it('muestra el resumen por jugador (nombre + recuento) sin acciones de compra', () => {
    const s = makeSnap({ properties: [prop({ owner_ref: 'P-AAAA', name: 'Atocha' })] });
    render(<PropertiesSummary snap={s} onOpenBoard={vi.fn()} />);
    expect(screen.getByText('Ana')).toBeInTheDocument();
    expect(screen.getByText(/1 propiedades/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Pagar alquiler' })).toBeNull();
  });
});

describe('PropertyBoardModal (tablero de propiedades)', () => {
  const onClose = vi.fn();
  const render0 = (s: ActiveSnapshot, over: Record<string, unknown> = {}) =>
    render(
      <PropertyBoardModal
        snap={s} isHost={s.me.is_host} busy={false} onClose={onClose}
        onRequestPurchase={vi.fn()} onPayRent={vi.fn()} onBid={vi.fn()} onCloseAuction={vi.fn()} onCancelAuction={vi.fn()}
        {...over}
      />,
    );
  const withProps = (props: ActiveProperty[], over = {}) => makeSnap({ properties: props, ...over });

  it('agrupa por tablero (Clásico) y por grupo de color (Marrón) y muestra nombre/precio', () => {
    render0(withProps([prop()]));
    expect(screen.getByText('Clásico')).toBeInTheDocument();
    expect(screen.getByText('Marrón')).toBeInTheDocument();
    expect(screen.getByText('Mediterráneo')).toBeInTheDocument();
    expect(screen.getByText('60 ₥')).toBeInTheDocument();
  });

  it('la cabecera respeta el safe area superior (iPhone)', () => {
    const { container } = render0(withProps([prop()]));
    expect(container.querySelector('header')?.className).toContain('safe-area-inset-top');
    expect(screen.getByRole('button', { name: 'Cerrar' })).toBeVisible();
  });

  it('agrupa también el tablero Regreso al futuro', () => {
    render0(withProps([
      prop(),
      prop({ property_ref: 'bf-1', board_key: 'back_to_the_future', group_key: 'celeste', name: 'Hill Valley', sort_order: 200 }),
    ]));
    expect(screen.getByText('Clásico')).toBeInTheDocument();
    expect(screen.getByText('Regreso al futuro')).toBeInTheDocument();
  });

  it('disponible y estoy en la casilla en mi turno: "Solicitar compra" llama onRequestPurchase', () => {
    const onReq = vi.fn();
    // Fase 4: solo se ofrece comprar la propiedad en la que estoy, en mi turno.
    const s = withProps([prop()], {
      me: { public_ref: 'P-BBBB', is_host: true, balance: 1000, is_current: true, is_spectator: false },
      current_space: { space_ref: 'sp', board_key: 'classic', space_index: 1, name: 'Mediterráneo', space_type: 'property', property_ref: 'cl-marron-1', is_start: false },
    });
    render0(s, { onRequestPurchase: onReq });
    const btn = screen.getByRole('button', { name: 'Solicitar compra' });
    expect(btn).toBeEnabled();
    fireEvent.click(btn);
    expect(onReq).toHaveBeenCalledTimes(1);
  });

  it('disponible pero NO estoy en la casilla: no ofrece "Solicitar compra" (explica por qué)', () => {
    render0(withProps([prop()]));  // me no es current y current_space null
    expect(screen.queryByRole('button', { name: 'Solicitar compra' })).toBeNull();
    expect(screen.getByText(/Solo puedes solicitar comprar la propiedad en la que has caído/)).toBeInTheDocument();
  });

  it('mía: muestra "Tuya" y no ofrece comprar/pagar', () => {
    render0(withProps([prop({ owner_ref: 'P-BBBB' })]));
    expect(screen.getByText('Tuya')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Solicitar compra' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Pagar alquiler' })).toBeNull();
  });

  it('de otro jugador: muestra el propietario y "Pagar alquiler" llama onPayRent', () => {
    const onRent = vi.fn();
    render0(withProps([prop({ owner_ref: 'P-AAAA', base_rent: 25 })]), { onPayRent: onRent });
    expect(screen.getByText(/Propiedad de Ana/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Pagar alquiler' }));
    expect(onRent).toHaveBeenCalledTimes(1);
  });

  it('en subasta: muestra el estado "En subasta" sin botón de compra', () => {
    render0(withProps([prop({ in_auction: true })]));
    expect(screen.getByText('En subasta')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Solicitar compra' })).toBeNull();
  });

  it('en pausa: aviso y sin botón de compra (acciones bloqueadas)', () => {
    render0(withProps([prop()], { runtime_status: 'paused' }));
    expect(screen.getByText(/acciones están deshabilitadas/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Solicitar compra' })).toBeNull();
  });

  it('espectador (en bancarrota): aviso y sin acciones', () => {
    const s = makeSnap({ properties: [prop()], me: { public_ref: 'P-BBBB', is_host: false, balance: 1000, is_current: false, is_spectator: true } });
    render0(s);
    expect(screen.getByText(/en bancarrota: solo puedes consultar/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Solicitar compra' })).toBeNull();
  });

  it('las tarjetas se ven sin hover (grupos abiertos por defecto) y "Cerrar" llama onClose', () => {
    const close = vi.fn();
    render0(withProps([prop()]), { onClose: close });
    // El grupo está abierto por defecto: la tarjeta es visible sin interacción.
    expect(screen.getByText('Mediterráneo')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar' }));
    expect(close).toHaveBeenCalledTimes(1);
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
