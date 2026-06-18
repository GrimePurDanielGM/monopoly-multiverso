import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { TurnBanner } from './TurnBanner';
import { PlayerBalances } from './PlayerBalances';
import { PlayerTransferForm } from './PlayerTransferForm';
import { BankPanel } from './BankPanel';
import { HostCorrections } from './HostCorrections';
import { LedgerList } from './LedgerList';
import { RevertDialog } from './RevertDialog';
import { LateJoinTray } from './LateJoinTray';

function makeSnap(over: Partial<ActiveSnapshot> = {}): ActiveSnapshot {
  return {
    game: { code: 'ABC234', status: 'active', config: { initial_money: 3000, min_players: 6, max_players: 16, allow_late_join: false } },
    me: { public_ref: 'P-BBBB', is_host: true, balance: 1000, is_current: false },
    turn: { turn_number: 5, current_player_ref: 'P-AAAA', order: ['P-AAAA', 'P-BBBB'] },
    players: [
      { public_ref: 'P-AAAA', display_name: 'Ana', token_id: 'cat', balance: 3000, is_current: true },
      { public_ref: 'P-BBBB', display_name: 'Beto', token_id: 'boot', balance: 1000, is_current: false },
    ],
    ledger_recent: [],
    late_join_requests: [],
    runtime_status: 'running',
    control: { paused_by_ref: null, finished_by_ref: null, reason: null },
    runtime_version: 7,
    ...over,
  };
}

describe('TurnBanner', () => {
  it('muestra "Turno de Ana" cuando no es mi turno', () => {
    render(<TurnBanner snap={makeSnap()} />);
    expect(screen.getByText(/Turno de Ana/)).toBeInTheDocument();
  });
  it('muestra "Tu turno" cuando es mi turno', () => {
    render(<TurnBanner snap={makeSnap({ me: { public_ref: 'P-AAAA', is_host: true, balance: 1, is_current: true } })} />);
    expect(screen.getByText('Tu turno')).toBeInTheDocument();
  });
});

describe('PlayerBalances', () => {
  it('muestra saldos y "Tú"', () => {
    render(<PlayerBalances snap={makeSnap()} icons={{ cat: '🐱', boot: '🥾' }} />);
    expect(screen.getByText(/3\.000/)).toBeInTheDocument();
    expect(screen.getByText('Tú')).toBeInTheDocument();
  });
});

describe('PlayerTransferForm', () => {
  it('transferencia válida llama onTransfer con el importe', () => {
    const onTransfer = vi.fn();
    render(<PlayerTransferForm snap={makeSnap()} busy={false} onTransfer={onTransfer} />);
    fireEvent.change(screen.getByLabelText('Importe'), { target: { value: '500' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enviar' }));
    expect(onTransfer).toHaveBeenCalledWith('P-AAAA', 500);
  });
  it('fondos insuficientes deshabilita y avisa', () => {
    const onTransfer = vi.fn();
    render(<PlayerTransferForm snap={makeSnap()} busy={false} onTransfer={onTransfer} />);
    fireEvent.change(screen.getByLabelText('Importe'), { target: { value: '5000' } });
    expect(screen.getByText('Saldo insuficiente.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Enviar' })).toBeDisabled();
  });
});

describe('BankPanel', () => {
  it('pagar y cobrar llaman onBank con la dirección correcta', () => {
    const onBank = vi.fn();
    render(<BankPanel snap={makeSnap()} busy={false} onBank={onBank} />);
    fireEvent.change(screen.getByLabelText('Importe'), { target: { value: '300' } });
    fireEvent.click(screen.getByRole('button', { name: 'Pagar al jugador' }));
    expect(onBank).toHaveBeenCalledWith('P-AAAA', 'to_player', 300);
    fireEvent.click(screen.getByRole('button', { name: 'Cobrar al jugador' }));
    expect(onBank).toHaveBeenCalledWith('P-AAAA', 'from_player', 300);
  });
});

describe('HostCorrections', () => {
  it('ajustar saldo exige motivo (deshabilitado sin él)', () => {
    const onAdjust = vi.fn();
    render(<HostCorrections snap={makeSnap()} busy={false} onAdjust={onAdjust} onSetTurn={vi.fn()} onHostTransfer={vi.fn()} />);
    const balInput = screen.getByLabelText('Nuevo saldo');
    fireEvent.change(balInput, { target: { value: '9000' } });
    const btn = screen.getByRole('button', { name: 'Ajustar saldo' });
    expect(btn).toBeDisabled(); // sin motivo
    const reason = screen.getAllByLabelText('Motivo (obligatorio)')[0]!;
    fireEvent.change(reason, { target: { value: 'corrección válida' } });
    fireEvent.click(btn);
    expect(onAdjust).toHaveBeenCalledWith('P-AAAA', 9000, 'corrección válida');
  });
});

describe('LedgerList', () => {
  const snap = makeSnap({
    ledger_recent: [
      { ledger_ref: 'L-PAY', seq: 3, kind: 'bank_to_player', from_ref: null, to_ref: 'P-AAAA', amount: 100, before_balance: null, after_balance: null, reason: null, actor_ref: 'P-BBBB', reverts_ref: null, created_at: 't' },
      { ledger_ref: 'L-SEED', seq: 1, kind: 'seed', from_ref: null, to_ref: 'P-AAAA', amount: 3000, before_balance: null, after_balance: null, reason: null, actor_ref: null, reverts_ref: null, created_at: 't' },
    ],
  });
  it('host puede revertir solo los reversibles; onRevert recibe ledger_ref', () => {
    const onRevert = vi.fn();
    render(<LedgerList snap={snap} isHost busy={false} onRevert={onRevert} />);
    const reverts = screen.getAllByRole('button', { name: 'Revertir' });
    expect(reverts).toHaveLength(1); // seed no es reversible
    fireEvent.click(reverts[0]!);
    expect(onRevert).toHaveBeenCalledWith('L-PAY');
  });
  it('no-host no ve botones de revertir', () => {
    render(<LedgerList snap={snap} isHost={false} busy={false} onRevert={vi.fn()} />);
    expect(screen.queryByRole('button', { name: 'Revertir' })).toBeNull();
  });
});

describe('LateJoinTray', () => {
  const snap = makeSnap({
    late_join_requests: [{ request_ref: 'L-REQ1', name: 'Nuevo', token: 'cat', device_label: 'iPad' }],
  });
  it('muestra la solicitud separada con aviso de saldo/orden y resuelve', () => {
    const onResolve = vi.fn();
    render(<LateJoinTray snap={snap} icons={{ cat: '🐱' }} busy={false} onResolve={onResolve} />);
    expect(screen.getByText(/Solicitudes para entrar en la partida/)).toBeInTheDocument();
    expect(screen.getByText(/se añadirán al final del orden/)).toBeInTheDocument();
    expect(screen.getByText('Nuevo')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Aceptar' }));
    expect(onResolve).toHaveBeenCalledWith('L-REQ1', true);
    fireEvent.click(screen.getByRole('button', { name: 'Rechazar' }));
    expect(onResolve).toHaveBeenCalledWith('L-REQ1', false);
  });
  it('sin solicitudes no renderiza nada', () => {
    const { container } = render(<LateJoinTray snap={makeSnap()} icons={{}} busy={false} onResolve={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
  });
});

describe('RevertDialog', () => {
  it('exige motivo y confirma con él', () => {
    const onConfirm = vi.fn();
    render(<RevertDialog open busy={false} onConfirm={onConfirm} onCancel={vi.fn()} />);
    const btn = screen.getByRole('button', { name: 'Revertir' });
    expect(btn).toBeDisabled();
    fireEvent.change(screen.getByLabelText('Motivo (obligatorio)'), { target: { value: 'me equivoqué' } });
    fireEvent.click(btn);
    expect(onConfirm).toHaveBeenCalledWith('me equivoqué');
  });
});
