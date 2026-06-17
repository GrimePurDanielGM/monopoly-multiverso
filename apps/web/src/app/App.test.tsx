import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { App } from './App';

describe('App', () => {
  it('renderiza la pantalla inicial con las acciones principales', async () => {
    render(<App />);
    expect(await screen.findByRole('button', { name: /crear partida/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /unirse/i })).toBeInTheDocument();
  });
});
