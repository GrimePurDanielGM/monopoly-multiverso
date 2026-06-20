import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { GlobalBanner } from './GlobalBanner';

describe('GlobalBanner', () => {
  it('no renderiza nada sin banner', () => {
    const { container } = render(<GlobalBanner banner={null} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('muestra quién cobró el bote y cuánto, en una región accesible (role=status), sin bloquear', () => {
    render(<GlobalBanner banner={{ name: 'Daniel', amount: 450 }} />);
    const status = screen.getByRole('status');
    expect(status).toHaveTextContent('Daniel');
    expect(status).toHaveTextContent('ha cobrado el bote de Parking');
    expect(status).toHaveTextContent('450 ₥');
    expect(status.className).toContain('pointer-events-none');
  });
});
