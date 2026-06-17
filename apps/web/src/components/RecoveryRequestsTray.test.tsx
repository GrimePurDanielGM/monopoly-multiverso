import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';

const { resolveRecoveryMock, resolveReentryMock } = vi.hoisted(() => ({ resolveRecoveryMock: vi.fn(), resolveReentryMock: vi.fn() }));
vi.mock('../lib/api', () => ({ resolveRecovery: resolveRecoveryMock, resolveReentry: resolveReentryMock }));

import { RecoveryRequestsTray } from './RecoveryRequestsTray';
import type { SnapPlayer, SnapRequest } from '../lib/snapshot';

const players: SnapPlayer[] = [{ public_ref: 'P-1', name: 'Ana', token_id: 'a', status: 'ready', last_seen_at: 'x' }];
const requests: SnapRequest[] = [
  { request_ref: 'R-1', kind: 'recovery', status: 'pending', target_public_ref: 'P-1', device_label: 'iPhone' },
  { request_ref: 'R-2', kind: 'reentry', status: 'pending', target_public_ref: 'P-9', device_label: null },
];
const reload = vi.fn(() => Promise.resolve());

beforeEach(() => {
  vi.clearAllMocks();
  resolveRecoveryMock.mockResolvedValue({ ok: true, data: true });
  resolveReentryMock.mockResolvedValue({ ok: true, data: true });
});

describe('RecoveryRequestsTray', () => {
  it('aceptar una recuperación confirma y llama resolve_recovery(true) (nombre por public_ref)', async () => {
    render(<RecoveryRequestsTray requests={requests} players={players} reload={reload} />);
    const card = screen.getByText(/Recuperación:/).closest('div') as HTMLElement;
    expect(within(card).getByText('Ana')).toBeInTheDocument(); // mapeado de target_public_ref P-1 -> Ana
    fireEvent.click(within(card).getByRole('button', { name: /Aceptar/ }));
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: /Aprobar/ }));
    await waitFor(() => expect(resolveRecoveryMock).toHaveBeenCalledWith('R-1', true));
    expect(reload).toHaveBeenCalled();
  });

  it('rechazar una reentrada llama resolve_reentry(false)', async () => {
    render(<RecoveryRequestsTray requests={requests} players={players} reload={reload} />);
    const card = screen.getByText(/Reentrada:/).closest('div') as HTMLElement;
    fireEvent.click(within(card).getByRole('button', { name: /Rechazar/ }));
    await waitFor(() => expect(resolveReentryMock).toHaveBeenCalledWith('R-2', false));
  });
});
