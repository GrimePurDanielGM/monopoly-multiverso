import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

const { recoverHostMock, navigateMock } = vi.hoisted(() => ({ recoverHostMock: vi.fn(), navigateMock: vi.fn() }));
vi.mock('react-router-dom', () => ({ useNavigate: () => navigateMock }));
vi.mock('../lib/api', () => ({ recoverHost: recoverHostMock }));
vi.mock('../lib/session', () => ({ ensureAnonSession: () => Promise.resolve('ready') }));

import { RecoverHostScreen } from './RecoverHostScreen';

function fill() {
  fireEvent.change(screen.getByLabelText(/Código de la sala/i), { target: { value: 'ABC234' } });
  fireEvent.change(screen.getByLabelText(/PIN de anfitrión/i), { target: { value: '482915' } });
}
const btn = () => screen.getByRole('button', { name: /Recuperar control/i });

beforeEach(() => vi.clearAllMocks());

describe('RecoverHostScreen', () => {
  it('éxito navega a la sala y no persiste el PIN', async () => {
    const setItem = vi.spyOn(Storage.prototype, 'setItem');
    recoverHostMock.mockResolvedValue({ ok: true });
    render(<RecoverHostScreen />);
    fill();
    fireEvent.click(btn());
    await waitFor(() => expect(recoverHostMock).toHaveBeenCalledWith('ABC234', '482915'));
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/sala/ABC234'));
    expect(setItem.mock.calls.some((c) => c.some((a) => String(a).includes('482915')))).toBe(false);
    setItem.mockRestore();
  });

  it('INVALID_PIN muestra el error', async () => {
    recoverHostMock.mockResolvedValue({ ok: false, code: 'INVALID_PIN', message: 'PIN incorrecto.' });
    render(<RecoverHostScreen />);
    fill();
    fireEvent.click(btn());
    expect(await screen.findByText(/PIN incorrecto/i)).toBeInTheDocument();
  });

  it('LOCKED muestra cuenta atrás y deshabilita el botón', async () => {
    const until = new Date(Date.now() + 60000).toISOString();
    recoverHostMock.mockResolvedValue({ ok: false, code: 'LOCKED', message: 'Demasiados intentos.', lockedUntil: until });
    render(<RecoverHostScreen />);
    fill();
    fireEvent.click(btn());
    await waitFor(() => expect(screen.getByLabelText(/Tiempo de bloqueo/i)).toBeInTheDocument());
    expect(btn()).toBeDisabled();
  });

  it('SESSION_HAS_ACTIVE_PLAYER muestra el error', async () => {
    recoverHostMock.mockResolvedValue({ ok: false, code: 'SESSION_HAS_ACTIVE_PLAYER', message: 'Esta sesión ya controla un jugador en esta sala.' });
    render(<RecoverHostScreen />);
    fill();
    fireEvent.click(btn());
    expect(await screen.findByText(/ya controla un jugador/i)).toBeInTheDocument();
  });
});
