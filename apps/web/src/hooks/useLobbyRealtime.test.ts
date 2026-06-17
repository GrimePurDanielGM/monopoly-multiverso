import { describe, it, expect, vi, beforeEach } from 'vitest';

interface FakeChannel {
  topic: string;
  on: ReturnType<typeof vi.fn>;
  subscribe: ReturnType<typeof vi.fn>;
  track: ReturnType<typeof vi.fn>;
  presenceState: ReturnType<typeof vi.fn>;
  emit: (s: string) => void;
}

const H = vi.hoisted(() => {
  const channels: FakeChannel[] = [];
  const removed: FakeChannel[] = [];
  function makeChannel(topic: string): FakeChannel {
    let subCb: ((s: string) => void) | undefined;
    const ch: FakeChannel = {
      topic,
      on: vi.fn(() => ch),
      subscribe: vi.fn((cb: (s: string) => void) => {
        subCb = cb;
        return ch;
      }),
      track: vi.fn(() => Promise.resolve('ok')),
      presenceState: vi.fn(() => ({})),
      emit: (s) => subCb?.(s),
    };
    channels.push(ch);
    return ch;
  }
  const supabase = {
    channel: vi.fn((topic: string) => makeChannel(topic)),
    removeChannel: vi.fn((ch: FakeChannel) => {
      removed.push(ch);
    }),
    realtime: { setAuth: vi.fn(() => Promise.resolve()) },
    auth: { getSession: vi.fn(() => Promise.resolve({ data: { session: { access_token: 't' } } })) },
  };
  const heartbeat = vi.fn(() => Promise.resolve({ ok: true, data: true }));
  return { channels, removed, supabase, heartbeat };
});

vi.mock('../lib/supabase', () => ({ supabase: H.supabase, supabaseConfigured: true }));
vi.mock('../lib/api', () => ({ heartbeat: H.heartbeat }));
vi.mock('../lib/session', () => ({ ensureAnonSession: () => Promise.resolve('ready') }));

import { renderHook, act, waitFor } from '@testing-library/react';
import { useLobbyRealtime } from './useLobbyRealtime';
import { useRealtimeStore } from '../store/realtime';

const params = (resync = vi.fn(() => Promise.resolve())) => ({
  code: 'ABC234',
  gameId: 'g1',
  myPublicRef: 'P-AAAAAAAAAA',
  knownRefs: new Set(['P-AAAAAAAAAA']),
  resync,
});

beforeEach(() => {
  H.channels.length = 0;
  H.removed.length = 0;
  vi.clearAllMocks();
  useRealtimeStore.getState().reset();
});

describe('useLobbyRealtime', () => {
  it('suscribe al montar, conecta y recarga; limpia al desmontar', async () => {
    const resync = vi.fn(() => Promise.resolve());
    const { unmount } = renderHook(() => useLobbyRealtime(params(resync)));
    await waitFor(() => expect(H.channels.length).toBe(1));
    const ch = H.channels[0]!;
    expect(ch.subscribe).toHaveBeenCalled();
    await act(async () => {
      ch.emit('SUBSCRIBED');
    });
    await waitFor(() => expect(useRealtimeStore.getState().channelStatus).toBe('connected'));
    expect(ch.track).toHaveBeenCalledWith({ public_ref: 'P-AAAAAAAAAA' });
    await waitFor(() => expect(resync).toHaveBeenCalled());
    unmount();
    expect(H.removed).toContain(ch);
  });

  it('remontar no deja canales duplicados', async () => {
    const a = renderHook(() => useLobbyRealtime(params()));
    await waitFor(() => expect(H.channels.length).toBe(1));
    a.unmount();
    const b = renderHook(() => useLobbyRealtime(params()));
    await waitFor(() => expect(H.channels.length).toBe(2));
    b.unmount();
    expect(H.removed.length).toBe(2); // ambos retirados, ninguno queda activo
  });

  it('ignora callbacks de la suscripción antigua tras desmontar (guarda de generación)', async () => {
    const { unmount } = renderHook(() => useLobbyRealtime(params()));
    await waitFor(() => expect(H.channels.length).toBe(1));
    const ch = H.channels[0]!;
    unmount();
    useRealtimeStore.getState().setChannelStatus('offline');
    await act(async () => {
      ch.emit('SUBSCRIBED');
    });
    expect(useRealtimeStore.getState().channelStatus).toBe('offline');
  });

  it('reconnect() recrea el canal sin duplicar', async () => {
    const { result } = renderHook(() => useLobbyRealtime(params()));
    await waitFor(() => expect(H.channels.length).toBe(1));
    await act(async () => {
      result.current.reconnect();
      await Promise.resolve();
    });
    await waitFor(() => expect(H.channels.length).toBe(2));
    expect(H.removed.length).toBeGreaterThanOrEqual(1);
  });
});
