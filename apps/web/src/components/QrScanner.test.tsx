import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

vi.mock('@zxing/browser', () => ({
  BrowserMultiFormatReader: class {
    decodeFromStream() {
      return Promise.resolve({ stop: vi.fn() });
    }
  },
}));

import { QrScanner } from './QrScanner';

const onDetected = vi.fn();
const onClose = vi.fn();

beforeEach(() => vi.clearAllMocks());

describe('QrScanner', () => {
  it('entrada manual: código válido llama onDetected normalizado', () => {
    render(<QrScanner open onDetected={onDetected} onClose={onClose} />);
    fireEvent.change(screen.getByLabelText(/introduce el código/i), { target: { value: 'abc234' } });
    fireEvent.click(screen.getByRole('button', { name: /^Usar$/ }));
    expect(onDetected).toHaveBeenCalledWith('ABC234');
  });

  it('entrada manual inválida avisa y no llama onDetected', () => {
    render(<QrScanner open onDetected={onDetected} onClose={onClose} />);
    fireEvent.change(screen.getByLabelText(/introduce el código/i), { target: { value: 'no-valido-12345' } });
    fireEvent.click(screen.getByRole('button', { name: /^Usar$/ }));
    expect(onDetected).not.toHaveBeenCalled();
    expect(screen.getByText(/no es de una sala válida/i)).toBeInTheDocument();
  });

  it('permiso de cámara denegado muestra el mensaje', async () => {
    const getUserMedia = vi.fn(() => Promise.reject(new DOMException('x', 'NotAllowedError')));
    Object.defineProperty(navigator, 'mediaDevices', { value: { getUserMedia }, configurable: true });
    render(<QrScanner open onDetected={onDetected} onClose={onClose} />);
    fireEvent.click(screen.getByRole('button', { name: /Escanear QR/i }));
    expect(await screen.findByText(/Permiso de cámara denegado/i)).toBeInTheDocument();
  });

  it('libera la cámara al desmontar (track.stop)', async () => {
    const stop = vi.fn();
    const stream = { getTracks: () => [{ stop }] } as unknown as MediaStream;
    const getUserMedia = vi.fn(() => Promise.resolve(stream));
    Object.defineProperty(navigator, 'mediaDevices', { value: { getUserMedia }, configurable: true });
    const { unmount } = render(<QrScanner open onDetected={onDetected} onClose={onClose} />);
    fireEvent.click(screen.getByRole('button', { name: /Escanear QR/i }));
    await waitFor(() => expect(getUserMedia).toHaveBeenCalled());
    unmount();
    expect(stop).toHaveBeenCalled();
  });
});
