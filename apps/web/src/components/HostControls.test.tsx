import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';

const { updateConfigMock, startGameMock, cancelGameMock } = vi.hoisted(() => ({
  updateConfigMock: vi.fn(),
  startGameMock: vi.fn(),
  cancelGameMock: vi.fn(),
}));
vi.mock('../lib/api', () => ({ updateConfig: updateConfigMock, startGame: startGameMock, cancelGame: cancelGameMock }));

import { HostControls } from './HostControls';
import type { SnapCounts, SnapGame, SnapPlayer } from '../lib/snapshot';

const game: SnapGame = {
  id: 'g1', code: 'ABC234', name: 'Demo', status: 'lobby', version: 7,
  started_at: null, cancelled_at: null, host_public_ref: 'P-1',
  config: { min_players: 6, max_players: 16, initial_money: 3000, token_catalog_version: 0, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false, allow_trade_built_properties: false },
};
const players: SnapPlayer[] = Array.from({ length: 6 }, (_, i) => ({
  public_ref: `P-${i + 1}`, name: `P-${i + 1}`, token_id: 't', status: 'ready', last_seen_at: 'x',
}));
const counts: SnapCounts = { player_count: 6, ready_count: 6, min_players: 6, max_players: 16 };
const reload = vi.fn(() => Promise.resolve());

beforeEach(() => {
  vi.clearAllMocks();
  updateConfigMock.mockResolvedValue({ ok: true, data: true });
  startGameMock.mockResolvedValue({ ok: true, data: true });
  cancelGameMock.mockResolvedValue({ ok: true, data: true });
});

function renderControls() {
  return render(<HostControls game={game} counts={counts} players={players} requests={[]} reload={reload} />);
}

describe('HostControls', () => {
  it('guardar configuración llama a update_config con la versión exacta del snapshot', async () => {
    renderControls();
    fireEvent.click(screen.getByRole('button', { name: /Guardar configuración/i }));
    await waitFor(() => expect(updateConfigMock).toHaveBeenCalled());
    const call = updateConfigMock.mock.calls[0]!;
    expect(call[0]).toBe('g1');
    expect(call[1]).toMatchObject({ name: 'Demo', min_players: 6, max_players: 16, initial_money: 3000 });
    expect(call[2]).toBe(7); // expected_version
    expect(reload).toHaveBeenCalled();
  });

  it('VERSION_CONFLICT recarga el snapshot y muestra el aviso', async () => {
    updateConfigMock.mockResolvedValue({ ok: false, code: 'VERSION_CONFLICT', message: 'Otro cambio se aplicó antes.' });
    renderControls();
    fireEvent.click(screen.getByRole('button', { name: /Guardar configuración/i }));
    await waitFor(() => expect(reload).toHaveBeenCalled());
    expect(await screen.findByText(/aplicó antes/i)).toBeInTheDocument();
  });

  it('iniciar requiere confirmación y llama a start_game con la versión', async () => {
    renderControls();
    fireEvent.click(screen.getByRole('button', { name: /Iniciar partida/i }));
    const dialog = screen.getByRole('dialog');
    fireEvent.click(within(dialog).getByRole('button', { name: /^Iniciar$/ }));
    await waitFor(() => expect(startGameMock).toHaveBeenCalledWith('g1', 7));
  });

  it('muestra error específico de inicio', async () => {
    startGameMock.mockResolvedValue({ ok: false, code: 'NOT_ENOUGH_PLAYERS', message: 'Faltan jugadores para empezar.' });
    renderControls();
    fireEvent.click(screen.getByRole('button', { name: /Iniciar partida/i }));
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: /^Iniciar$/ }));
    await waitFor(() => expect(screen.getByText(/Faltan jugadores/i)).toBeInTheDocument());
  });

  it('cancelar requiere confirmación y llama a cancel_game', async () => {
    renderControls();
    fireEvent.click(screen.getByRole('button', { name: /^Cancelar sala$/ }));
    const dialog = screen.getByRole('dialog');
    fireEvent.click(within(dialog).getByRole('button', { name: /Sí, cancelar/ }));
    await waitFor(() => expect(cancelGameMock).toHaveBeenCalledWith('g1'));
  });
});
