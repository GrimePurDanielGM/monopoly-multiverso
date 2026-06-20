import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { useState } from 'react';
import { NumberStepper } from './NumberStepper';

// Wrapper controlado para ejercitar el comportamiento real (estado del padre).
function Harness({ initial = 6, min, max, onValue }: { initial?: number; min: number; max: number; onValue?: (n: number) => void }) {
  const [v, setV] = useState(initial);
  return <NumberStepper ariaLabel="Mínimo" value={v} min={min} max={max} onChange={(n) => { setV(n); onValue?.(n); }} />;
}

describe('NumberStepper (item 6 — inputs numéricos iPhone)', () => {
  it('los botones + y − ajustan el valor respetando min/max', () => {
    const onValue = vi.fn();
    render(<Harness initial={6} min={2} max={16} onValue={onValue} />);
    fireEvent.click(screen.getByRole('button', { name: 'Aumentar' }));
    expect(onValue).toHaveBeenLastCalledWith(7);
    fireEvent.click(screen.getByRole('button', { name: 'Disminuir' }));
    expect(onValue).toHaveBeenLastCalledWith(6);
    expect(screen.getByLabelText('Mínimo')).toHaveValue('6');
  });

  it('el botón − no baja del mínimo', () => {
    render(<Harness initial={2} min={2} max={16} />);
    expect(screen.getByRole('button', { name: 'Disminuir' })).toBeDisabled();
  });

  it('permite escribir a mano un valor', () => {
    const onValue = vi.fn();
    render(<Harness initial={6} min={2} max={16} onValue={onValue} />);
    fireEvent.change(screen.getByLabelText('Mínimo'), { target: { value: '12' } });
    expect(onValue).toHaveBeenLastCalledWith(12);
  });

  it('permite un estado temporal vacío sin romper (no propaga NaN)', () => {
    const onValue = vi.fn();
    render(<Harness initial={6} min={2} max={16} onValue={onValue} />);
    fireEvent.change(screen.getByLabelText('Mínimo'), { target: { value: '' } });
    expect(screen.getByLabelText('Mínimo')).toHaveValue('');     // se permite vacío mientras se escribe
    expect(onValue).not.toHaveBeenCalled();                       // no propaga un valor inválido
    fireEvent.change(screen.getByLabelText('Mínimo'), { target: { value: '3' } });
    expect(onValue).toHaveBeenLastCalledWith(3);
  });
});
