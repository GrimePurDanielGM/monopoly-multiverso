import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MoneyBanner } from './MoneyBanner';

describe('MoneyBanner', () => {
  it('no renderiza nada sin flash', () => {
    const { container } = render(<MoneyBanner flash={null} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('muestra importe + mensaje en una región accesible (role=status)', () => {
    render(<MoneyBanner flash={{ amount: 200, message: 'Has cobrado 200 ₥ al pasar por salida' }} />);
    const status = screen.getByRole('status');
    expect(status).toHaveTextContent('+200 ₥');
    expect(status).toHaveTextContent('al pasar por salida');
  });

  it('no bloquea la interacción (pointer-events-none)', () => {
    render(<MoneyBanner flash={{ amount: 50, message: 'Beto te ha pagado 50 ₥' }} />);
    expect(screen.getByRole('status').className).toContain('pointer-events-none');
  });
});
