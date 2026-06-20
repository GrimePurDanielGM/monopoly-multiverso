import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { LastCardDraw } from '../../lib/activeSnapshot';
import { CardModal } from './CardModal';

const baseCard: LastCardDraw = {
  draw_id: 'd1', player_ref: 'P-1', deck_key: 'chance', board_key: 'classic', card_ref: 'chance-credit-200',
  title: '(Temporal) Cobras de la banca', description: 'Cobra 200 de la banca.', effect_type: 'bank_credit',
  amount: 200, keepable: false, temporary: true, manual: false,
};

describe('CardModal', () => {
  it('carta aplicada: muestra mazo, título, texto y "Aceptar" (no "Marcar como resuelta")', () => {
    const onAccept = vi.fn();
    render(<CardModal show={{ card: baseCard, mustResolve: false }} busy={false} onAccept={onAccept} onResolve={vi.fn()} />);
    const dialog = screen.getByRole('dialog', { name: /Carta:/ });
    expect(dialog).toHaveTextContent('Suerte');
    expect(dialog).toHaveTextContent('Cobras de la banca');
    expect(dialog).toHaveTextContent('Cobra 200 de la banca');
    expect(screen.queryByRole('button', { name: /Marcar como resuelta/ })).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Aceptar' }));
    expect(onAccept).toHaveBeenCalledTimes(1);
  });

  it('marca de carta temporal visible', () => {
    render(<CardModal show={{ card: baseCard, mustResolve: false }} busy={false} onAccept={vi.fn()} onResolve={vi.fn()} />);
    expect(screen.getByText(/Carta temporal/)).toBeInTheDocument();
  });

  it('carta manual: muestra "Marcar como resuelta" y llama onResolve', () => {
    const onResolve = vi.fn();
    const manual: LastCardDraw = { ...baseCard, card_ref: 'chance-manual', effect_type: 'manual', manual: true, title: '(Temporal) Carta manual' };
    render(<CardModal show={{ card: manual, mustResolve: true }} busy={false} onAccept={vi.fn()} onResolve={onResolve} />);
    expect(screen.queryByRole('button', { name: 'Aceptar' })).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: /Marcar como resuelta/ }));
    expect(onResolve).toHaveBeenCalledTimes(1);
  });
});
