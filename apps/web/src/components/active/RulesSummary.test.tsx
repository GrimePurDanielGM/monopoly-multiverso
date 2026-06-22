import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import type { ActiveConfig } from '../../lib/activeSnapshot';
import { RulesSummary } from './RulesSummary';

const cfg = (over: Partial<ActiveConfig> = {}): ActiveConfig => ({
  initial_money: 3000, min_players: 2, max_players: 16, allow_late_join: false, start_bonus: 200,
  dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12,
  allow_build_without_monopoly: false, allow_trade_built_properties: false, parking_mode: 'pot', start_invest_pct: 0, ...over,
});

describe('RulesSummary (Fase 9)', () => {
  it('muestra las opciones configuradas, incluida la de tratos con construcciones', () => {
    render(<RulesSummary config={cfg({ allow_trade_built_properties: true, dice_mode: 'physical_only' })} />);
    expect(screen.getByText('Reglas de la partida')).toBeInTheDocument();
    expect(screen.getByText('Tratos con propiedades construidas')).toBeInTheDocument();
    expect(screen.getByText('Solo dados físicos')).toBeInTheDocument();
    // fila de tratos construidos = "Sí"
    const row = screen.getByText('Tratos con propiedades construidas').parentElement!;
    expect(row.textContent).toContain('Sí');
  });

  it('refleja las opciones desactivadas como "No"', () => {
    render(<RulesSummary config={cfg()} />);
    const row = screen.getByText('Construir sin el grupo completo').parentElement!;
    expect(row.textContent).toContain('No');
  });
});
