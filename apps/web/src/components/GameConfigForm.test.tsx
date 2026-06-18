import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { GameConfigForm } from './GameConfigForm';

function renderForm(over: Partial<React.ComponentProps<typeof GameConfigForm>> = {}) {
  const onSubmit = vi.fn();
  render(
    <GameConfigForm
      name="Mi sala"
      minPlayers={6}
      maxPlayers={16}
      initialMoney={3000}
      allowLateJoin={false}
      currentPlayers={1}
      busy={false}
      onSubmit={onSubmit}
      {...over}
    />,
  );
  return { onSubmit };
}

describe('GameConfigForm — mínimo de jugadores', () => {
  it('permite seleccionar 2 como mínimo y lo envía', () => {
    const { onSubmit } = renderForm();
    fireEvent.change(screen.getByLabelText('Mínimo'), { target: { value: '2' } });
    const save = screen.getByRole('button', { name: 'Guardar configuración' });
    expect(save).toBeEnabled();
    fireEvent.click(save);
    expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({ min_players: 2, max_players: 16 }));
  });

  it('el input acepta 2 (atributo min=2)', () => {
    renderForm();
    expect(screen.getByLabelText('Mínimo')).toHaveAttribute('min', '2');
  });

  it('rechaza mínimo 1 (Guardar deshabilitado)', () => {
    renderForm();
    fireEvent.change(screen.getByLabelText('Mínimo'), { target: { value: '1' } });
    expect(screen.getByRole('button', { name: 'Guardar configuración' })).toBeDisabled();
  });
});
