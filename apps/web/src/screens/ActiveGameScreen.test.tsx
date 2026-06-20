import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import type { ActiveSnapshot, ActiveProperty } from '../lib/activeSnapshot';

const { activeMock, finishMock, pauseMock, resumeMock, leaveMock, removeMock, buyMock, rentMock, bankruptcyMock } = vi.hoisted(() => ({
  activeMock: vi.fn(),
  finishMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  pauseMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  resumeMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  leaveMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  removeMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  buyMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  rentMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  bankruptcyMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
}));

vi.mock('../lib/api', () => {
  const noop = () => Promise.resolve({ ok: true, data: true });
  return {
    getActiveSnapshotByCode: activeMock,
    listActiveTokens: () => Promise.resolve({ ok: true, data: [] }),
    endTurn: noop, bankTransfer: noop, playerTransfer: noop, hostPlayerTransfer: noop,
    hostAdjustBalance: noop, hostSetTurn: noop, hostRevertMovement: noop,
    pauseGame: pauseMock, resumeGame: resumeMock, finishGame: finishMock,
    requestLeaveActive: leaveMock, resolveLeaveActive: noop, removeActivePlayer: removeMock,
    requestPropertyPurchase: buyMock, resolvePropertyPurchase: noop, payRent: rentMock,
    startPropertyAuction: noop, placePropertyBid: noop, closePropertyAuction: noop, cancelPropertyAuction: noop,
    requestBankruptcy: bankruptcyMock, resolveBankruptcy: noop,
    resolveRecovery: noop, resolveReentry: noop,
  };
});

// Silenciar el audio real (jsdom no implementa HTMLMediaElement.play/load) sin perder el cableado.
vi.mock('../lib/cashSound', () => ({
  isCashSoundEnabled: () => true,
  setCashSoundEnabled: vi.fn(),
  primeCashSound: vi.fn(),
  playCashSound: vi.fn(),
}));

const PROP = (over: Partial<ActiveProperty> = {}): ActiveProperty => ({
  property_ref: 'cl-marron-1', board_key: 'classic', group_key: 'marron', name: 'Mediterráneo',
  kind: 'street', price: 60, base_rent: 2, is_buyable: true, sort_order: 10, owner_ref: null, in_auction: false, ...over,
});

import { ActiveGameScreen } from './ActiveGameScreen';
import { useActiveStore } from '../store/active';

function snap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16, allow_late_join: false, start_bonus: 200 } },
    me: { public_ref: 'P-1', is_host: true, balance: 3000, is_current: false, is_spectator: false },
    turn: { turn_number: 1, current_player_ref: 'P-2', order: ['P-1', 'P-2'] },
    players: [
      { public_ref: 'P-1', display_name: 'Host', token_id: 'cat', balance: 3000, is_current: false, status: 'active' },
      { public_ref: 'P-2', display_name: 'Marty', token_id: 'boot', balance: 3000, is_current: true, status: 'active' },
    ],
    ledger_recent: [],
    properties: [],
    auctions: [],
    purchase_requests: [],
    leave_requests: [],
    bankruptcy_requests: [],
    late_join_requests: [],
    boards: [], spaces: [], board_links: [], guardians: [], pending_junction: null, parking_pot: 0, jail: [], my_jail: null, card_decks: [], last_card_draw: null, held_cards: [], my_held_cards: [], pending_card: null, pending_payment: null, last_global_event: null, positions: [], my_position: null, current_space: null, last_roll: null, last_move: null,
    runtime_status: 'running',
    control: { paused_by_ref: null, finished_by_ref: null, reason: null },
    runtime_version: 5,
    ...over,
  };
}

function renderScreen(s: ActiveSnapshot) {
  activeMock.mockResolvedValue({ ok: true, data: s });
  useActiveStore.setState({ snap: s });
  return render(<ActiveGameScreen code="ABC234" gameId="g1" onReload={() => Promise.resolve()} onReconnect={() => {}} />);
}

beforeEach(() => { vi.clearAllMocks(); useActiveStore.setState({ snap: null }); });

describe('ActiveGameScreen — finalizar (confirmación obligatoria)', () => {
  it('"Finalizar partida" solo abre el diálogo (no llama a la RPC)', async () => {
    renderScreen(snap());
    fireEvent.click(screen.getByRole('button', { name: 'Finalizar partida' }));
    expect(screen.getByRole('dialog', { name: 'Finalizar partida' })).toBeInTheDocument();
    expect(finishMock).not.toHaveBeenCalled();
  });

  it('foco inicial en la opción segura; Escape no finaliza', async () => {
    renderScreen(snap());
    fireEvent.click(screen.getByRole('button', { name: 'Finalizar partida' }));
    expect(screen.getByRole('button', { name: 'No, continuar jugando' })).toHaveFocus();
    fireEvent.keyDown(document, { key: 'Escape' });
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());
    expect(finishMock).not.toHaveBeenCalled();
  });

  it('"No, continuar jugando" no llama a la RPC', () => {
    renderScreen(snap());
    fireEvent.click(screen.getByRole('button', { name: 'Finalizar partida' }));
    fireEvent.click(screen.getByRole('button', { name: 'No, continuar jugando' }));
    expect(finishMock).not.toHaveBeenCalled();
  });

  it('"Sí, finalizar partida" llama una sola vez; doble pulsación no duplica', async () => {
    renderScreen(snap());
    fireEvent.click(screen.getByRole('button', { name: 'Finalizar partida' }));
    const yes = screen.getByRole('button', { name: 'Sí, finalizar partida' });
    fireEvent.click(yes);
    fireEvent.click(yes); // segunda pulsación: el botón se deshabilita por busy
    await waitFor(() => expect(finishMock).toHaveBeenCalledTimes(1));
    expect(finishMock).toHaveBeenCalledWith('g1', '', expect.any(String), 5);
  });
});

describe('ActiveGameScreen — control y estados', () => {
  it('en pausa muestra el aviso y deshabilita acciones', () => {
    renderScreen(snap({ runtime_status: 'paused', control: { paused_by_ref: 'P-1', finished_by_ref: null, reason: 'café' } }));
    expect(screen.getByText('Partida en pausa')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Enviar' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Reanudar partida' })).toBeInTheDocument();
  });

  it('finalizada muestra la pantalla final sin acciones', () => {
    renderScreen(snap({ runtime_status: 'finished', control: { paused_by_ref: null, finished_by_ref: 'P-1', reason: null } }));
    expect(screen.getByRole('heading', { name: 'Partida finalizada' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Finalizar partida' })).toBeNull();
  });

  it('"Recargar partida" es un botón que recarga el snapshot', async () => {
    renderScreen(snap());
    activeMock.mockClear();
    fireEvent.click(screen.getByRole('button', { name: 'Recargar partida' }));
    await waitFor(() => expect(activeMock).toHaveBeenCalledWith('ABC234'));
  });
});

describe('ActiveGameScreen — abandonar/expulsar', () => {
  // jugador normal (no anfitrión): P-2
  const playerSnap = () => snap({ me: { public_ref: 'P-2', is_host: false, balance: 3000, is_current: true, is_spectator: false } });

  it('"Abandonar partida" solo abre el diálogo; Cancelar no llama a la RPC', () => {
    renderScreen(playerSnap());
    fireEvent.click(screen.getByRole('button', { name: 'Abandonar partida' }));
    expect(screen.getByRole('dialog', { name: 'Abandonar partida' })).toBeInTheDocument();
    expect(leaveMock).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'No, seguir jugando' }));
    expect(leaveMock).not.toHaveBeenCalled();
  });

  it('confirmar abandono llama leaveActiveGame una sola vez (con runtime_version)', async () => {
    renderScreen(playerSnap());
    fireEvent.click(screen.getByRole('button', { name: 'Abandonar partida' }));
    const yes = screen.getByRole('button', { name: 'Sí, solicitar abandono' });
    fireEvent.click(yes);
    fireEvent.click(yes);
    await waitFor(() => expect(leaveMock).toHaveBeenCalledTimes(1));
    expect(leaveMock).toHaveBeenCalledWith('g1', expect.any(String));
  });

  it('anfitrión: "Sacar jugador" abre diálogo con destino del saldo; por defecto a la banca', async () => {
    renderScreen(snap()); // me anfitrión P-1
    fireEvent.click(screen.getByRole('button', { name: 'Sacar jugador' }));
    expect(screen.getByRole('dialog', { name: 'Sacar jugador' })).toBeInTheDocument();
    expect(screen.getByLabelText('Devolver a la banca')).toBeChecked();
    fireEvent.click(screen.getByRole('button', { name: 'Sí, sacar jugador' }));
    await waitFor(() => expect(removeMock).toHaveBeenCalledTimes(1));
    expect(removeMock).toHaveBeenCalledWith('g1', 'P-2', 'to_bank', '', expect.any(String), 5);
  });

  it('anfitrión: elegir "Repartir" envía resolución distribute', async () => {
    renderScreen(snap());
    fireEvent.click(screen.getByRole('button', { name: 'Sacar jugador' }));
    fireEvent.click(screen.getByLabelText('Repartir entre jugadores restantes'));
    fireEvent.click(screen.getByRole('button', { name: 'Sí, sacar jugador' }));
    await waitFor(() => expect(removeMock).toHaveBeenCalledWith('g1', 'P-2', 'distribute', '', expect.any(String), 5));
  });

  it('en pausa se permite abandonar (acción no bloqueada por el fieldset)', () => {
    renderScreen(snap({ me: { public_ref: 'P-2', is_host: false, balance: 3000, is_current: false, is_spectator: false }, runtime_status: 'paused', control: { paused_by_ref: 'P-1', finished_by_ref: null, reason: null } }));
    expect(screen.getByRole('button', { name: 'Abandonar partida' })).toBeEnabled();
  });
});

describe('ActiveGameScreen — propiedades', () => {
  // Fase 4: solo puedo solicitar comprar la casilla en la que estoy, en mi turno.
  const onProp = {
    me: { public_ref: 'P-1', is_host: true, balance: 3000, is_current: true, is_spectator: false } as const,
    current_space: { space_ref: 'sp', board_key: 'classic' as const, space_index: 1, name: 'Mediterráneo', space_type: 'property' as const, property_ref: 'cl-marron-1', is_start: false },
  };
  it('solicitar compra abre confirmación; confirmar llama requestPropertyPurchase una vez', async () => {
    renderScreen(snap({ properties: [PROP({ price: 60 })], ...onProp }));
    fireEvent.click(screen.getByRole('button', { name: 'Ver tablero de propiedades' }));
    const board = screen.getByRole('dialog', { name: 'Tablero de propiedades' });
    fireEvent.click(within(board).getByRole('button', { name: 'Solicitar compra' }));
    const dlg = screen.getByRole('dialog', { name: 'Solicitar compra' });
    expect(dlg).toBeInTheDocument();
    expect(buyMock).not.toHaveBeenCalled();
    const yes = within(dlg).getByRole('button', { name: 'Solicitar compra' });
    fireEvent.click(yes);
    fireEvent.click(yes);
    await waitFor(() => expect(buyMock).toHaveBeenCalledTimes(1));
    expect(buyMock).toHaveBeenCalledWith('g1', 'cl-marron-1', expect.any(String));
  });

  it('cancelar la solicitud no llama a la RPC', () => {
    renderScreen(snap({ properties: [PROP({ price: 60 })], ...onProp }));
    fireEvent.click(screen.getByRole('button', { name: 'Ver tablero de propiedades' }));
    const board = screen.getByRole('dialog', { name: 'Tablero de propiedades' });
    fireEvent.click(within(board).getByRole('button', { name: 'Solicitar compra' }));
    fireEvent.click(within(screen.getByRole('dialog', { name: 'Solicitar compra' })).getByRole('button', { name: 'Cancelar' }));
    expect(buyMock).not.toHaveBeenCalled();
  });

  it('pagar alquiler abre confirmación; confirmar llama payRent una vez', async () => {
    // me = P-1 (host); la propiedad es de P-2.
    renderScreen(snap({ properties: [PROP({ owner_ref: 'P-2', base_rent: 25 })] }));
    fireEvent.click(screen.getByRole('button', { name: 'Ver tablero de propiedades' }));
    fireEvent.click(screen.getByRole('button', { name: 'Pagar alquiler' }));
    const dlg = screen.getByRole('dialog', { name: 'Pagar alquiler' });
    expect(dlg).toBeInTheDocument();
    const yes = within(dlg).getByRole('button', { name: 'Pagar alquiler' });
    fireEvent.click(yes);
    await waitFor(() => expect(rentMock).toHaveBeenCalledTimes(1));
    expect(rentMock).toHaveBeenCalledWith('g1', 'cl-marron-1', expect.any(String), 5);
  });

  it('un jugador no anfitrión puede declararse en bancarrota (abre el diálogo y solicita)', async () => {
    renderScreen(snap({ me: { public_ref: 'P-2', is_host: false, balance: 3000, is_current: true, is_spectator: false } }));
    fireEvent.click(screen.getByRole('button', { name: 'Declararme en bancarrota' }));
    const dlg = screen.getByRole('dialog', { name: 'Declararme en bancarrota' });
    fireEvent.change(within(dlg).getByPlaceholderText(/motivo/i), { target: { value: 'sin fondos' } });
    fireEvent.click(within(dlg).getByRole('button', { name: 'Declararme en bancarrota' }));
    await waitFor(() => expect(bankruptcyMock).toHaveBeenCalledTimes(1));
    expect(bankruptcyMock).toHaveBeenCalledWith('g1', 'to_bank', null, 'sin fondos', expect.any(String));
  });

  it('el espectador (en bancarrota) ve el aviso y no puede declararse de nuevo', () => {
    renderScreen(snap({ me: { public_ref: 'P-2', is_host: false, balance: 0, is_current: false, is_spectator: true },
      players: [
        { public_ref: 'P-1', display_name: 'Host', token_id: 'cat', balance: 3000, is_current: true, status: 'active' },
        { public_ref: 'P-2', display_name: 'Marty', token_id: 'boot', balance: 0, is_current: false, status: 'bankrupt' },
      ] }));
    expect(screen.getByText(/Estás en bancarrota\. Puedes seguir consultando/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Declararme en bancarrota' })).toBeNull();
  });
});
