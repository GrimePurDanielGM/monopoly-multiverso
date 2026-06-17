import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

const { statusMock } = vi.hoisted(() => ({ statusMock: vi.fn() }));
vi.mock('../lib/api', () => ({ getRequestStatus: statusMock }));

import { renderHook, act } from '@testing-library/react';
import { useRequestPolling } from './useRequestPolling';
import { useRequestStore } from '../store/request';

beforeEach(() => {
  vi.useFakeTimers();
  useRequestStore.getState().reset();
  statusMock.mockReset();
});
afterEach(() => vi.useRealTimers());

describe('useRequestPolling', () => {
  it('sondea hasta approved, llama onApproved una vez y se detiene', async () => {
    statusMock
      .mockResolvedValueOnce({ ok: true, data: { kind: 'recovery', status: 'pending' } })
      .mockResolvedValueOnce({ ok: true, data: { kind: 'recovery', status: 'approved' } });
    const onApproved = vi.fn();
    useRequestStore.getState().start('P-REQ', 'recovery', 'pending');
    renderHook(() => useRequestPolling(onApproved));

    await act(async () => {
      await vi.advanceTimersByTimeAsync(2600); // tick inmediato (pending) + 1 intervalo (approved)
    });
    expect(onApproved).toHaveBeenCalledTimes(1);
    expect(useRequestStore.getState().status).toBe('approved');

    const calls = statusMock.mock.calls.length;
    await act(async () => {
      await vi.advanceTimersByTimeAsync(6000);
    });
    expect(statusMock.mock.calls.length).toBe(calls); // detenido: no más sondeos
  });

  it('se detiene al desmontar (sin sondeos posteriores)', async () => {
    statusMock.mockResolvedValue({ ok: true, data: { kind: 'reentry', status: 'pending' } });
    useRequestStore.getState().start('P-REQ', 'reentry', 'pending');
    const { unmount } = renderHook(() => useRequestPolling(() => {}));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2600);
    });
    const calls = statusMock.mock.calls.length;
    unmount();
    await act(async () => {
      await vi.advanceTimersByTimeAsync(6000);
    });
    expect(statusMock.mock.calls.length).toBe(calls);
  });
});
