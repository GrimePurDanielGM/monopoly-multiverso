import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ConnectionBar, PresenceDot } from './ConnectionBar';

describe('ConnectionBar', () => {
  it('connected muestra "Conectado"', () => {
    render(<ConnectionBar status="connected" onRetry={() => {}} />);
    expect(screen.getByText('Conectado')).toBeInTheDocument();
  });
  it('reconnecting muestra "Reconectando…" y NO "Conexión perdida" (antes de 12 s)', () => {
    render(<ConnectionBar status="reconnecting" onRetry={() => {}} />);
    expect(screen.getByText(/Reconectando/)).toBeInTheDocument();
    expect(screen.queryByText(/Conexión perdida/)).toBeNull();
  });
  it('offline muestra el banner "Sin conexión"', () => {
    render(<ConnectionBar status="offline" onRetry={() => {}} />);
    expect(screen.getByText(/Sin conexión/)).toBeInTheDocument();
  });
  it('disconnected muestra "Conexión perdida" y el botón de reintento funciona', () => {
    const onRetry = vi.fn();
    render(<ConnectionBar status="disconnected" onRetry={onRetry} />);
    expect(screen.getByText(/Conexión perdida/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/i }));
    expect(onRetry).toHaveBeenCalled();
  });
});

describe('PresenceDot', () => {
  it('refleja el estado por aria-label', () => {
    const { rerender } = render(<PresenceDot status="connected" />);
    expect(screen.getByLabelText('Conectado')).toBeInTheDocument();
    rerender(<PresenceDot status="reconnecting" />);
    expect(screen.getByLabelText('Reconectando')).toBeInTheDocument();
    rerender(<PresenceDot status="disconnected" />);
    expect(screen.getByLabelText('Desconectado')).toBeInTheDocument();
  });
});
