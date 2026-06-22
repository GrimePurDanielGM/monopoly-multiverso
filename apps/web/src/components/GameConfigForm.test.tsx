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
      diceMode="virtual_only"
      housesAvailable={32}
      hotelsAvailable={12}
      allowBuildWithoutMonopoly={false}
      allowTradeBuiltProperties={false}
      parkingMode="pot"
      startInvestPct={0}
      currentPlayers={1}
      busy={false}
      onSubmit={onSubmit}
      {...over}
    />,
  );
  return { onSubmit };
}

describe('GameConfigForm — configuración de dados', () => {
  it('incluye el modo de dados elegido en el patch', () => {
    const { onSubmit } = renderForm();
    fireEvent.change(screen.getByLabelText('Configuración de dados'), { target: { value: 'physical_allowed' } });
    fireEvent.click(screen.getByRole('button', { name: 'Guardar configuración' }));
    expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({ dice_mode: 'physical_allowed', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false, allow_trade_built_properties: false, parking_mode: 'pot', start_invest_pct: 0 }));
  });
});

describe('GameConfigForm — stock de construcción (Fase 6 pulido)', () => {
  it('envía el stock configurado y la regla de construir sin grupo', () => {
    const { onSubmit } = renderForm();
    fireEvent.change(screen.getByLabelText('Casas disponibles'), { target: { value: '64' } });
    fireEvent.change(screen.getByLabelText('Hoteles disponibles'), { target: { value: '24' } });
    fireEvent.click(screen.getByLabelText(/Permitir construir casas sin tener el grupo completo/));
    fireEvent.click(screen.getByRole('button', { name: 'Guardar configuración' }));
    expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({ initial_houses_available: 64, initial_hotels_available: 24, allow_build_without_monopoly: true, allow_trade_built_properties: false, parking_mode: 'pot', start_invest_pct: 0 }));
  });

  it('rechaza bajar de 32 casas / 12 hoteles (Guardar deshabilitado)', () => {
    renderForm();
    fireEvent.change(screen.getByLabelText('Casas disponibles'), { target: { value: '20' } });
    expect(screen.getByRole('button', { name: 'Guardar configuración' })).toBeDisabled();
    fireEvent.change(screen.getByLabelText('Casas disponibles'), { target: { value: '32' } });
    fireEvent.change(screen.getByLabelText('Hoteles disponibles'), { target: { value: '8' } });
    expect(screen.getByRole('button', { name: 'Guardar configuración' })).toBeDisabled();
  });
});

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
