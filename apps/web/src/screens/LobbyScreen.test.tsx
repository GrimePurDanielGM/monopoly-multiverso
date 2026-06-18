import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';

const { snapMock, tokensMock, chooseMock, readyMock, activeMock } = vi.hoisted(() => ({
  snapMock: vi.fn(),
  tokensMock: vi.fn(),
  chooseMock: vi.fn(),
  readyMock: vi.fn(),
  activeMock: vi.fn(),
}));

vi.mock('react-router-dom', () => ({
  useParams: () => ({ code: 'ABC234' }),
  Link: ({ to, children }: { to: string; children: ReactNode }) => <a href={to}>{children}</a>,
}));
vi.mock('../lib/api', () => ({
  getLobbySnapshotByCode: snapMock,
  getActiveSnapshotByCode: activeMock,
  peekGame: () => Promise.resolve({ ok: true, data: { status: 'lobby', player_count: 3, max_players: 16, accepts_entries: true, name: 'x', open_slots: 13, available_tokens: [], players: [] } }),
  listActiveTokens: tokensMock,
  chooseToken: chooseMock,
  setReady: readyMock,
  // host/kick: no se ejercitan en estos tests; presentes para evitar undefined al renderizar host
  getMyStatus: () => Promise.resolve({ ok: true, data: 'active' }),
  kickPlayer: () => Promise.resolve({ ok: true, data: true }),
  updateConfig: () => Promise.resolve({ ok: true, data: true }),
  startGame: () => Promise.resolve({ ok: true, data: true }),
  cancelGame: () => Promise.resolve({ ok: true, data: true }),
  // Acciones de partida activa (no se ejercitan al renderizar; no-ops para imports)
  endTurn: () => Promise.resolve({ ok: true, data: true }),
  bankTransfer: () => Promise.resolve({ ok: true, data: true }),
  playerTransfer: () => Promise.resolve({ ok: true, data: true }),
  hostPlayerTransfer: () => Promise.resolve({ ok: true, data: true }),
  hostAdjustBalance: () => Promise.resolve({ ok: true, data: true }),
  hostSetTurn: () => Promise.resolve({ ok: true, data: true }),
  hostRevertMovement: () => Promise.resolve({ ok: true, data: true }),
}));
vi.mock('../lib/session', () => ({ ensureAnonSession: () => Promise.resolve('ready') }));
vi.mock('../hooks/useLobbyRealtime', () => ({ useLobbyRealtime: () => ({ reconnect: () => {} }) }));

import { LobbyScreen } from './LobbyScreen';
import { useLobbyStore } from '../store/lobby';
import type { GameStatus, JoinStatus, LobbySnapshot, SnapPlayer } from '../lib/snapshot';

const TOKENS = [
  { id: 'delorean', label: 'DeLorean', icon: '🚗' },
  { id: 'hoverboard', label: 'Hoverboard', icon: '🛹' },
  { id: 'plutonium_case', label: 'Plutonio', icon: '⚛️' },
];

function mkPlayer(ref: string, token: string | null, status: JoinStatus = 'joined'): SnapPlayer {
  return { public_ref: ref, name: `Jugador ${ref}`, token_id: token, status, last_seen_at: '2026-06-17T00:00:00Z' };
}
function mkSnapshot(opts: { status?: GameStatus; players?: SnapPlayer[]; meToken?: string | null } = {}): LobbySnapshot {
  const players = opts.players ?? [mkPlayer('P-1', 'delorean'), mkPlayer('P-2', 'hoverboard')];
  return {
    game: {
      id: 'g1', code: 'ABC234', name: 'Demo Sala', status: opts.status ?? 'lobby', version: 0,
      started_at: null, cancelled_at: null, host_public_ref: 'P-1',
      config: { min_players: 6, max_players: 16, initial_money: 3000, token_catalog_version: 0 },
    },
    players,
    me: { public_ref: 'P-1', is_host: true, join_status: 'joined', token_id: opts.meToken === undefined ? 'delorean' : opts.meToken, membership: 'active' },
    requests: [],
    counts: { player_count: players.length, ready_count: players.filter((p) => p.status === 'ready').length, min_players: 6, max_players: 16 },
  };
}

beforeEach(() => {
  useLobbyStore.getState().reset();
  vi.clearAllMocks();
  tokensMock.mockResolvedValue({ ok: true, data: TOKENS });
  snapMock.mockResolvedValue({ ok: true, data: mkSnapshot() });
  chooseMock.mockResolvedValue({ ok: true, data: true });
  readyMock.mockResolvedValue({ ok: true, data: true });
});

describe('LobbyScreen', () => {
  it('carga la sala y muestra nombre, contadores y jugadores', async () => {
    render(<LobbyScreen />);
    expect(await screen.findByText('Demo Sala')).toBeInTheDocument();
    expect(screen.getByText('2/16')).toBeInTheDocument(); // jugadores
    expect(screen.getByText('0/2')).toBeInTheDocument(); // preparados
    expect(screen.getByText('Jugador P-1')).toBeInTheDocument();
    expect(screen.getByText('Jugador P-2')).toBeInTheDocument();
  });

  it('renderiza 6 y 16 jugadores', async () => {
    const six = Array.from({ length: 6 }, (_, i) => mkPlayer(`P-${i + 1}`, null));
    snapMock.mockResolvedValue({ ok: true, data: mkSnapshot({ players: six }) });
    const { unmount } = render(<LobbyScreen />);
    expect(await screen.findByText('Jugador P-6')).toBeInTheDocument();
    expect(screen.getByText('6/16')).toBeInTheDocument();
    unmount();

    useLobbyStore.getState().reset();
    const sixteen = Array.from({ length: 16 }, (_, i) => mkPlayer(`P-${i + 1}`, null));
    snapMock.mockResolvedValue({ ok: true, data: mkSnapshot({ players: sixteen }) });
    render(<LobbyScreen />);
    expect(await screen.findByText('Jugador P-16')).toBeInTheDocument();
    expect(screen.getByText('16/16')).toBeInTheDocument();
  });

  it('marca "Tú" y "Anfitrión" para el jugador actual host', async () => {
    render(<LobbyScreen />);
    await screen.findByText('Demo Sala');
    expect(screen.getByText('Tú')).toBeInTheDocument();
    expect(screen.getAllByText('Anfitrión').length).toBeGreaterThanOrEqual(1);
  });

  it('cambiar ficha llama a choose_token', async () => {
    render(<LobbyScreen />);
    await screen.findByText('Demo Sala');
    fireEvent.click(screen.getByRole('radio', { name: 'Plutonio' }));
    await waitFor(() => expect(chooseMock).toHaveBeenCalledWith('g1', 'plutonium_case'));
  });

  it('TOKEN_TAKEN provoca recarga del snapshot y muestra error', async () => {
    chooseMock.mockResolvedValue({ ok: false, code: 'TOKEN_TAKEN', message: 'Otra persona acaba de coger esa ficha.' });
    render(<LobbyScreen />);
    await screen.findByText('Demo Sala');
    expect(snapMock).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole('radio', { name: 'Plutonio' }));
    await waitFor(() => expect(chooseMock).toHaveBeenCalled());
    await waitFor(() => expect(snapMock).toHaveBeenCalledTimes(2)); // recarga autoritativa
    expect(await screen.findByText(/acaba de coger/i)).toBeInTheDocument();
  });

  it('marcar preparado llama a set_ready', async () => {
    render(<LobbyScreen />);
    await screen.findByText('Demo Sala');
    fireEvent.click(screen.getByRole('button', { name: /Marcar Preparado/i }));
    await waitFor(() => expect(readyMock).toHaveBeenCalledWith('g1', true));
  });

  it('no permite marcar preparado sin ficha', async () => {
    snapMock.mockResolvedValue({ ok: true, data: mkSnapshot({ meToken: null, players: [mkPlayer('P-1', null), mkPlayer('P-2', 'hoverboard')] }) });
    render(<LobbyScreen />);
    await screen.findByText('Demo Sala');
    expect(screen.getByRole('button', { name: /Marcar Preparado/i })).toBeDisabled();
  });

  it('renderiza la pantalla de partida activa en estado active', async () => {
    snapMock.mockResolvedValue({ ok: true, data: mkSnapshot({ status: 'active' }) });
    activeMock.mockResolvedValue({
      ok: true,
      data: {
        game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16 } },
        me: { public_ref: 'P-1', is_host: true, balance: 3000, is_current: true },
        turn: { turn_number: 1, current_player_ref: 'P-1', order: ['P-1'] },
        players: [{ public_ref: 'P-1', display_name: 'Anfitrión', token_id: 'delorean', balance: 3000, is_current: true }],
        ledger_recent: [],
        runtime_status: 'running',
        control: { paused_by_ref: null, finished_by_ref: null, reason: null },
        runtime_version: 0,
      },
    });
    render(<LobbyScreen />);
    expect(await screen.findByText('Partida ABC234')).toBeInTheDocument();
  });

  it('muestra "La partida ha sido cancelada" en estado cancelled', async () => {
    snapMock.mockResolvedValue({ ok: true, data: mkSnapshot({ status: 'cancelled' }) });
    render(<LobbyScreen />);
    expect(await screen.findByText(/ha sido cancelada/i)).toBeInTheDocument();
  });

  it('NOT_ACTIVE_MEMBER muestra salida hacia unirse', async () => {
    snapMock.mockResolvedValue({ ok: false, code: 'NOT_ACTIVE_MEMBER', message: 'No formas parte de esta sala.' });
    render(<LobbyScreen />);
    expect(await screen.findByText(/No formas parte/i)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Unirse/i })).toBeInTheDocument();
  });
});
