import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

const { navigateMock, createGameMock, listActiveTokensMock } = vi.hoisted(() => ({
  navigateMock: vi.fn(),
  createGameMock: vi.fn(),
  listActiveTokensMock: vi.fn(),
}));

vi.mock('react-router-dom', () => ({ useNavigate: () => navigateMock }));
vi.mock('../lib/api', () => ({ createGame: createGameMock, listActiveTokens: listActiveTokensMock }));
vi.mock('../lib/session', () => ({ ensureAnonSession: () => Promise.resolve('ready') }));

import { CreateGameScreen } from './CreateGameScreen';

const TOKENS = [
  { id: 'delorean', label: 'DeLorean', icon: '🚗' },
  { id: 'hoverboard', label: 'Hoverboard', icon: '🛹' },
];

function fillValid() {
  fireEvent.change(screen.getByLabelText(/Nombre de la partida/i), { target: { value: 'Sábado noche' } });
  fireEvent.change(screen.getByLabelText(/Tu nombre/i), { target: { value: 'Daniel' } });
  fireEvent.change(screen.getByLabelText(/PIN de anfitrión/i), { target: { value: '482915' } });
}

const okResult = { ok: true, data: { game_id: 'g1', code: 'ABC234', host_public_ref: 'P-1', idempotent: false } };

beforeEach(() => {
  vi.clearAllMocks();
  listActiveTokensMock.mockResolvedValue({ ok: true, data: TOKENS });
});

describe('CreateGameScreen', () => {
  it('no permite enviar sin ficha seleccionada', async () => {
    render(<CreateGameScreen />);
    await screen.findByRole('radio', { name: 'DeLorean' });
    fillValid();
    const submit = screen.getByRole('button', { name: /crear y entrar/i });
    expect(submit).toBeDisabled();
    fireEvent.click(submit);
    expect(createGameMock).not.toHaveBeenCalled();
  });

  it('envía la ficha seleccionada exactamente como host_token', async () => {
    createGameMock.mockResolvedValue(okResult);
    render(<CreateGameScreen />);
    await screen.findByRole('radio', { name: 'Hoverboard' });
    fillValid();
    fireEvent.click(screen.getByRole('radio', { name: 'Hoverboard' }));
    const submit = screen.getByRole('button', { name: /crear y entrar/i });
    await waitFor(() => expect(submit).toBeEnabled());
    fireEvent.click(submit);
    await waitFor(() => expect(createGameMock).toHaveBeenCalledTimes(1));
    expect(createGameMock).toHaveBeenCalledWith(
      expect.objectContaining({ host_token: 'hoverboard', name: 'Sábado noche', host_name: 'Daniel', pin: '482915' }),
    );
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/sala/ABC234'));
  });

  it('no persiste el PIN en localStorage', async () => {
    const setItem = vi.spyOn(Storage.prototype, 'setItem');
    createGameMock.mockResolvedValue(okResult);
    render(<CreateGameScreen />);
    await screen.findByRole('radio', { name: 'DeLorean' });
    fillValid();
    fireEvent.click(screen.getByRole('radio', { name: 'DeLorean' }));
    const submit = screen.getByRole('button', { name: /crear y entrar/i });
    await waitFor(() => expect(submit).toBeEnabled());
    fireEvent.click(submit);
    await waitFor(() => expect(createGameMock).toHaveBeenCalled());
    const persistedPin = setItem.mock.calls.some((c) => c.some((arg) => String(arg).includes('482915')));
    expect(persistedPin).toBe(false);
    setItem.mockRestore();
  });

  it('mantiene el request_id estable en los reintentos del mismo intento', async () => {
    createGameMock
      .mockResolvedValueOnce({ ok: false, code: 'NAME_TAKEN', message: 'Nombre en uso' })
      .mockResolvedValueOnce(okResult);
    render(<CreateGameScreen />);
    await screen.findByRole('radio', { name: 'DeLorean' });
    fillValid();
    fireEvent.click(screen.getByRole('radio', { name: 'DeLorean' }));
    const submit = screen.getByRole('button', { name: /crear y entrar/i });
    await waitFor(() => expect(submit).toBeEnabled());
    fireEvent.click(submit); // intento 1 -> falla
    await waitFor(() => expect(createGameMock).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(submit).toBeEnabled()); // re-habilitado tras el error
    fireEvent.click(submit); // intento 2 (mismo intento) -> ok
    await waitFor(() => expect(createGameMock).toHaveBeenCalledTimes(2));
    const id1 = (createGameMock.mock.calls[0]?.[0] as { request_id: string }).request_id;
    const id2 = (createGameMock.mock.calls[1]?.[0] as { request_id: string }).request_id;
    expect(id1).toBe(id2);
  });
});
