import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type { ActiveSnapshot } from '../lib/activeSnapshot';

const { activeMock, finishMock, pauseMock, resumeMock, leaveMock, removeMock } = vi.hoisted(() => ({
  activeMock: vi.fn(),
  finishMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  pauseMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  resumeMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  leaveMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
  removeMock: vi.fn(() => Promise.resolve({ ok: true, data: true })),
}));

vi.mock('../lib/api', () => {
  const noop = () => Promise.resolve({ ok: true, data: true });
  return {
    getActiveSnapshotByCode: activeMock,
    listActiveTokens: () => Promise.resolve({ ok: true, data: [] }),
    endTurn: noop, bankTransfer: noop, playerTransfer: noop, hostPlayerTransfer: noop,
    hostAdjustBalance: noop, hostSetTurn: noop, hostRevertMovement: noop,
    pauseGame: pauseMock, resumeGame: resumeMock, finishGame: finishMock,
    leaveActiveGame: leaveMock, removeActivePlayer: removeMock,
    resolveRecovery: noop, resolveReentry: noop,
  };
});

import { ActiveGameScreen } from './ActiveGameScreen';
import { useActiveStore } from '../store/active';

function snap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16, allow_late_join: false } },
    me: { public_ref: 'P-1', is_host: true, balance: 3000, is_current: false },
    turn: { turn_number: 1, current_player_ref: 'P-2', order: ['P-1', 'P-2'] },
    players: [
      { public_ref: 'P-1', display_name: 'Host', token_id: 'cat', balance: 3000, is_current: false },
      { public_ref: 'P-2', display_name: 'Marty', token_id: 'boot', balance: 3000, is_current: true },
    ],
    ledger_recent: [],
    late_join_requests: [],
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
  const playerSnap = () => snap({ me: { public_ref: 'P-2', is_host: false, balance: 3000, is_current: true } });

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
    const yes = screen.getByRole('button', { name: 'Sí, abandonar partida' });
    fireEvent.click(yes);
    fireEvent.click(yes);
    await waitFor(() => expect(leaveMock).toHaveBeenCalledTimes(1));
    expect(leaveMock).toHaveBeenCalledWith('g1', expect.any(String), 5);
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
    renderScreen(snap({ me: { public_ref: 'P-2', is_host: false, balance: 3000, is_current: false }, runtime_status: 'paused', control: { paused_by_ref: 'P-1', finished_by_ref: null, reason: null } }));
    expect(screen.getByRole('button', { name: 'Abandonar partida' })).toBeEnabled();
  });
});
