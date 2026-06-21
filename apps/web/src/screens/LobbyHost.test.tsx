import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import type { ReactNode } from 'react';

const { snapMock, kickMock } = vi.hoisted(() => ({ snapMock: vi.fn(), kickMock: vi.fn() }));

vi.mock('react-router-dom', () => ({
  useParams: () => ({ code: 'ABC234' }),
  Link: ({ to, children }: { to: string; children: ReactNode }) => <a href={to}>{children}</a>,
}));
vi.mock('../lib/session', () => ({ ensureAnonSession: () => Promise.resolve('ready') }));
vi.mock('../hooks/useLobbyRealtime', () => ({ useLobbyRealtime: () => ({ reconnect: () => {} }) }));
vi.mock('../lib/api', () => ({
  getLobbySnapshotByCode: snapMock,
  listActiveTokens: () => Promise.resolve({ ok: true, data: [] }),
  kickPlayer: kickMock,
  getMyStatus: () => Promise.resolve({ ok: true, data: 'active' }),
  chooseToken: () => Promise.resolve({ ok: true, data: true }),
  setReady: () => Promise.resolve({ ok: true, data: true }),
  updateConfig: () => Promise.resolve({ ok: true, data: true }),
  startGame: () => Promise.resolve({ ok: true, data: true }),
  cancelGame: () => Promise.resolve({ ok: true, data: true }),
}));

import { LobbyScreen } from './LobbyScreen';
import { useLobbyStore } from '../store/lobby';
import type { LobbySnapshot } from '../lib/snapshot';

function snapshot(meIsHost: boolean): LobbySnapshot {
  return {
    game: {
      id: 'g1', code: 'ABC234', name: 'Demo', status: 'lobby', version: 3,
      started_at: null, cancelled_at: null, host_public_ref: 'P-1',
      config: { min_players: 6, max_players: 16, initial_money: 3000, token_catalog_version: 0, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false, allow_trade_built_properties: false },
    },
    players: [
      { public_ref: 'P-1', name: 'Ana', token_id: 'a', status: 'ready', last_seen_at: 'x' },
      { public_ref: 'P-2', name: 'Bob', token_id: 'b', status: 'joined', last_seen_at: 'x' },
    ],
    me: { public_ref: meIsHost ? 'P-1' : 'P-2', is_host: meIsHost, join_status: meIsHost ? 'ready' : 'joined', token_id: meIsHost ? 'a' : 'b', membership: 'active' },
    requests: [],
    counts: { player_count: 2, ready_count: 1, min_players: 6, max_players: 16 },
  };
}

beforeEach(() => {
  useLobbyStore.getState().reset();
  vi.clearAllMocks();
  kickMock.mockResolvedValue({ ok: true, data: true });
});

describe('LobbyScreen — anfitrión', () => {
  it('el host ve los controles y "Expulsar" solo en no-anfitriones', async () => {
    snapMock.mockResolvedValue({ ok: true, data: snapshot(true) });
    render(<LobbyScreen />);
    await screen.findByText('Demo');
    expect(screen.getByRole('button', { name: /Iniciar partida/i })).toBeInTheDocument();
    expect(screen.getByText(/Controles del anfitrión/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Expulsar a Bob/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Expulsar a Ana/i })).toBeNull(); // no se expulsa al host
  });

  it('un no-host NO ve controles ni "Expulsar"', async () => {
    snapMock.mockResolvedValue({ ok: true, data: snapshot(false) });
    render(<LobbyScreen />);
    await screen.findByText('Demo');
    expect(screen.queryByText(/Controles del anfitrión/i)).toBeNull();
    expect(screen.queryByRole('button', { name: /Expulsar/i })).toBeNull();
  });

  it('expulsar usa public_ref (kick_player) tras confirmar', async () => {
    snapMock.mockResolvedValue({ ok: true, data: snapshot(true) });
    render(<LobbyScreen />);
    await screen.findByText('Demo');
    fireEvent.click(screen.getByRole('button', { name: /Expulsar a Bob/i }));
    const dialog = screen.getByRole('dialog');
    fireEvent.click(within(dialog).getByRole('button', { name: /^Expulsar$/ }));
    await waitFor(() => expect(kickMock).toHaveBeenCalledWith('g1', 'P-2'));
  });
});
