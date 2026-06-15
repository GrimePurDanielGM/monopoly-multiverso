import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { engineFingerprint } from '@multiverso/engine';
import { App } from './App';

describe('App (fase 0)', () => {
  it('renderiza y muestra el fingerprint del motor compartido', () => {
    render(<App />);
    const fp = engineFingerprint();
    expect(screen.getByText(/Monopoly: El Multiverso/)).toBeInTheDocument();
    expect(screen.getByText(new RegExp(String(fp.checksum)))).toBeInTheDocument();
  });
});
