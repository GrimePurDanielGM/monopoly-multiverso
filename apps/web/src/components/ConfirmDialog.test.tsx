import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ConfirmDialog } from './ConfirmDialog';

describe('ConfirmDialog', () => {
  it('enfoca el botón cancelar al abrir y Escape cancela', () => {
    const onCancel = vi.fn();
    render(<ConfirmDialog open title="T" message="m" confirmLabel="Sí" onConfirm={() => {}} onCancel={onCancel} />);
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Cancelar' }));
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(onCancel).toHaveBeenCalled();
  });

  it('no renderiza cuando open=false', () => {
    render(<ConfirmDialog open={false} title="T" message="m" confirmLabel="Sí" onConfirm={() => {}} onCancel={() => {}} />);
    expect(screen.queryByRole('dialog')).toBeNull();
  });
});
