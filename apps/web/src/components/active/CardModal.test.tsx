import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { LastCardDraw } from '../../lib/activeSnapshot';
import type { CardToShow } from '../../hooks/useCardDraw';
import { CardModal } from './CardModal';

const baseCard: LastCardDraw = {
  draw_id: 'd1', player_ref: 'P-1', deck_key: 'chance', board_key: 'classic', card_ref: 'chance-credit-200',
  title: 'Cobras de la banca', description: 'Cobra 200 de la banca.', effect_type: 'bank_credit',
  amount: 200, keepable: false, temporary: false, manual: false, manual_instruction: null,
};
const show = (over: Partial<CardToShow> = {}): CardToShow => ({ card: baseCard, mustResolve: false, choice: false, instruction: null, ...over });

describe('CardModal', () => {
  it('carta aplicada: muestra mazo, título, texto y "Aceptar" (no "Marcar como resuelta")', () => {
    const onAccept = vi.fn();
    render(<CardModal show={show()} busy={false} onAccept={onAccept} onResolve={vi.fn()} onChoice={vi.fn()} />);
    const dialog = screen.getByRole('dialog', { name: /Carta:/ });
    expect(dialog).toHaveTextContent('Suerte');
    expect(dialog).toHaveTextContent('Cobras de la banca');
    expect(dialog).toHaveTextContent('Cobra 200 de la banca');
    expect(screen.queryByRole('button', { name: /Marcar como resuelta/ })).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Aceptar' }));
    expect(onAccept).toHaveBeenCalledTimes(1);
  });

  it('marca de carta temporal visible', () => {
    render(<CardModal show={show({ card: { ...baseCard, temporary: true } })} busy={false} onAccept={vi.fn()} onResolve={vi.fn()} onChoice={vi.fn()} />);
    expect(screen.getByText(/Carta temporal/)).toBeInTheDocument();
  });

  it('carta manual: muestra "Marcar como resuelta" y llama onResolve', () => {
    const onResolve = vi.fn();
    const manual: LastCardDraw = { ...baseCard, card_ref: 'past-transporte', effect_type: 'to_nearest', manual: true, title: 'Transporte más cercano' };
    render(<CardModal show={show({ card: manual, mustResolve: true, instruction: 'Paga el doble del alquiler.' })} busy={false} onAccept={vi.fn()} onResolve={onResolve} onChoice={vi.fn()} />);
    expect(screen.queryByRole('button', { name: 'Aceptar' })).toBeNull();
    expect(screen.getByText('Paga el doble del alquiler.')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Marcar como resuelta/ }));
    expect(onResolve).toHaveBeenCalledTimes(1);
  });

  it('carta de elección: muestra dos botones y llama onChoice con pay/draw', () => {
    const onChoice = vi.fn();
    const cc: LastCardDraw = { ...baseCard, card_ref: 'cc-multa-o-suerte', deck_key: 'community_chest', effect_type: 'choice', manual: true, title: 'Multa o Suerte' };
    render(<CardModal show={show({ card: cc, mustResolve: true, choice: true })} busy={false} onAccept={vi.fn()} onResolve={vi.fn()} onChoice={onChoice} />);
    fireEvent.click(screen.getByRole('button', { name: /Pagar 10/ }));
    fireEvent.click(screen.getByRole('button', { name: /Robar carta de Suerte/ }));
    expect(onChoice).toHaveBeenNthCalledWith(1, 'pay');
    expect(onChoice).toHaveBeenNthCalledWith(2, 'draw');
  });
});
