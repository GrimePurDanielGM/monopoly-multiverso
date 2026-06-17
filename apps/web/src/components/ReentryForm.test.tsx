import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';

const { requestReentryMock } = vi.hoisted(() => ({ requestReentryMock: vi.fn() }));
vi.mock('../lib/api', () => ({ requestReentry: requestReentryMock }));
vi.mock('../lib/session', () => ({ ensureAnonSession: () => Promise.resolve('ready') }));
vi.mock('../hooks/useRequestPolling', () => ({ useRequestPolling: () => {} }));
vi.mock('react-router-dom', () => ({ Link: ({ to, children }: { to: string; children: ReactNode }) => <a href={to}>{children}</a> }));

import { ReentryForm } from './ReentryForm';
import { useRequestStore } from '../store/request';

beforeEach(() => {
  vi.clearAllMocks();
  useRequestStore.getState().reset();
  requestReentryMock.mockResolvedValue({ ok: true, data: { request_ref: 'R-1', status: 'pending' } });
});

describe('ReentryForm', () => {
  it('solicita reentrada con el nombre y pasa a estado pendiente', async () => {
    render(<ReentryForm code="ABC234" onApproved={() => {}} />);
    fireEvent.change(screen.getByLabelText(/Nombre para volver/i), { target: { value: 'Pedro2' } });
    fireEvent.click(screen.getByRole('button', { name: /Solicitar reentrada/i }));
    await waitFor(() => expect(requestReentryMock).toHaveBeenCalledWith('ABC234', 'Pedro2', null));
    await waitFor(() => expect(screen.getByText(/pendiente de aprobación/i)).toBeInTheDocument());
  });
});
