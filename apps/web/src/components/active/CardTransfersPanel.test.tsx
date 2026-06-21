import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { CardTransfer } from '../../lib/activeSnapshot';
import { CardTransfersPanel } from './CardTransfersPanel';

const tr = (over: Partial<CardTransfer> = {}): CardTransfer => ({
  transfer_ref: 'T1', amount: 50, payer_ref: 'P-1', payee_ref: 'P-2', payer_name: 'Ana', payee_name: 'Beto', ...over,
});

describe('CardTransfersPanel (Fase 8 C3)', () => {
  it('no renderiza nada sin transferencias', () => {
    const { container } = render(<CardTransfersPanel transfers={[]} busy={false} onAuthorize={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('muestra a quién pagar y cuánto, y autoriza al pulsar', () => {
    const onAuthorize = vi.fn();
    const t = tr();
    render(<CardTransfersPanel transfers={[t]} busy={false} onAuthorize={onAuthorize} />);
    const region = screen.getByRole('region', { name: 'Transferencias de carta' });
    expect(region).toHaveTextContent('Beto');
    expect(region).toHaveTextContent('50 €');
    fireEvent.click(screen.getByRole('button', { name: 'Autorizar pago' }));
    expect(onAuthorize).toHaveBeenCalledWith(t);
  });
});
