import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { SharePanel } from './SharePanel';
import { joinLink } from '../lib/config';

const writeText = vi.fn(() => Promise.resolve());
beforeEach(() => {
  writeText.mockClear();
  Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
});

describe('SharePanel', () => {
  it('muestra el enlace /j/CODE y copia al portapapeles', async () => {
    render(<SharePanel code="ABC234" />);
    expect(screen.getByText(/\/j\/ABC234/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Copiar enlace/i }));
    // El host concreto depende de VITE_PUBLIC_BASE_URL; afirmamos contra el enlace canónico calculado
    // (config.test.ts ya fija el valor por defecto de producción) para no depender de .env.local.
    await waitFor(() => expect(writeText).toHaveBeenCalledWith(joinLink('ABC234')));
  });

  it('el QR contiene solo el enlace (sin secretos en el alt)', async () => {
    render(<SharePanel code="ABC234" />);
    const img = await screen.findByAltText(/Código QR del enlace de la sala/i);
    expect(img.getAttribute('alt')).toContain('/j/ABC234');
    expect(img.getAttribute('alt')).not.toMatch(/eyJ|PIN|pepper|secret|service_role/i);
  });
});
