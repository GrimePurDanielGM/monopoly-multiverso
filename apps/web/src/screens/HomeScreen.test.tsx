import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { HomeScreen } from './HomeScreen';
import { rememberGame, loadGameHistory } from '../lib/gameHistory';

const navigateMock = vi.fn();
vi.mock('react-router-dom', async (orig) => ({ ...(await orig<typeof import('react-router-dom')>()), useNavigate: () => navigateMock }));

function renderHome() {
  return render(<MemoryRouter><HomeScreen /></MemoryRouter>);
}

describe('HomeScreen', () => {
  beforeEach(() => { try { window.localStorage.clear(); } catch { /* */ } navigateMock.mockClear(); });

  it('muestra las acciones de crear y unirse', () => {
    renderHome();
    expect(screen.getByRole('button', { name: /crear partida/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /unirse/i })).toBeInTheDocument();
  });

  it('sin historial no muestra "Mis partidas"', () => {
    renderHome();
    expect(screen.queryByRole('region', { name: 'Mis partidas' })).toBeNull();
  });

  it('muestra el historial local con código, estado y nombre', () => {
    rememberGame({ code: 'ABC234', role: 'host', display_name: 'Ana', status: 'active', game_title: 'Sábado' });
    renderHome();
    const region = screen.getByRole('region', { name: 'Mis partidas' });
    expect(region).toHaveTextContent('ABC234');
    expect(region).toHaveTextContent('En curso');
    expect(region).toHaveTextContent('Ana');
  });

  it('"Entrar" navega a /sala/{CODE}', () => {
    rememberGame({ code: 'ABC234', status: 'active' });
    renderHome();
    fireEvent.click(screen.getByRole('button', { name: 'Entrar' }));
    expect(navigateMock).toHaveBeenCalledWith('/sala/ABC234');
  });

  it('etiqueta "Finalizada" para partidas terminadas', () => {
    rememberGame({ code: 'ZZZ999', status: 'finished' });
    renderHome();
    expect(screen.getByRole('region', { name: 'Mis partidas' })).toHaveTextContent('Finalizada');
  });

  it('"Quitar" elimina la partida de la lista', () => {
    rememberGame({ code: 'ABC234', status: 'active' });
    renderHome();
    fireEvent.click(screen.getByRole('button', { name: /Quitar ABC234/ }));
    expect(loadGameHistory()).toHaveLength(0);
    expect(screen.queryByRole('region', { name: 'Mis partidas' })).toBeNull();
  });
});
