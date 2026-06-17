import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { HomeScreen } from './HomeScreen';

describe('HomeScreen', () => {
  it('muestra las acciones de crear y unirse', () => {
    render(
      <MemoryRouter>
        <HomeScreen />
      </MemoryRouter>,
    );
    expect(screen.getByRole('button', { name: /crear partida/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /unirse/i })).toBeInTheDocument();
  });
});
