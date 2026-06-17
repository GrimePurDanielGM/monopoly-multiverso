import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';

const { peekMock, requestRecoveryMock, navigateMock, pollMock } = vi.hoisted(() => ({
  peekMock: vi.fn(),
  requestRecoveryMock: vi.fn(),
  navigateMock: vi.fn(),
  pollMock: vi.fn(),
}));
vi.mock('react-router-dom', () => ({
  useParams: () => ({ code: 'ABC234' }),
  useNavigate: () => navigateMock,
  Link: ({ to, children }: { to: string; children: ReactNode }) => <a href={to}>{children}</a>,
}));
vi.mock('../lib/api', () => ({ peekGame: peekMock, requestRecovery: requestRecoveryMock }));
vi.mock('../lib/session', () => ({ ensureAnonSession: () => Promise.resolve('ready') }));
vi.mock('../hooks/useRequestPolling', () => ({ useRequestPolling: (cb: () => void) => pollMock(cb) }));

import { RecoveryScreen } from './RecoveryScreen';
import { useRequestStore } from '../store/request';

const peekData = {
  name: 'Demo', status: 'lobby', player_count: 2, max_players: 16, open_slots: 14, accepts_entries: true,
  available_tokens: [],
  players: [
    { public_ref: 'P-1', name: 'Ana', token_id: 'a', status: 'ready', kicked: false },
    { public_ref: 'P-2', name: 'Bob', token_id: 'b', status: 'joined', kicked: false },
  ],
};

beforeEach(() => {
  vi.clearAllMocks();
  useRequestStore.getState().reset();
  peekMock.mockResolvedValue({ ok: true, data: peekData });
  requestRecoveryMock.mockResolvedValue({ ok: true, data: { request_ref: 'R-1', status: 'pending' } });
});

describe('RecoveryScreen', () => {
  it('muestra identidades y solicita recuperación por public_ref', async () => {
    render(<RecoveryScreen />);
    await screen.findByRole('radio', { name: 'Ana' });
    fireEvent.click(screen.getByRole('radio', { name: 'Bob' }));
    fireEvent.click(screen.getByRole('button', { name: /Solicitar recuperación/i }));
    await waitFor(() => expect(requestRecoveryMock).toHaveBeenCalledWith('ABC234', 'P-2', null));
    await waitFor(() => expect(screen.getByText(/pendiente de aprobación/i)).toBeInTheDocument());
  });

  it('al aprobarse navega a la sala', () => {
    pollMock.mockImplementation((cb: () => void) => cb()); // simula aprobación
    render(<RecoveryScreen />);
    expect(navigateMock).toHaveBeenCalledWith('/sala/ABC234');
  });
});
