import { describe, it, expect, beforeEach } from 'vitest';
import { useRealtimeStore } from './realtime';

beforeEach(() => useRealtimeStore.getState().reset());

describe('useRealtimeStore', () => {
  it('no contiene datos autoritativos duplicados del snapshot', () => {
    const keys = Object.keys(useRealtimeStore.getState());
    for (const forbidden of ['players', 'game', 'config', 'tokens', 'name', 'ready', 'host', 'counts']) {
      expect(keys).not.toContain(forbidden);
    }
  });
  it('guarda solo transporte (estado + presencia por public_ref)', () => {
    useRealtimeStore.getState().setChannelStatus('connected');
    useRealtimeStore.getState().setPresence(['P-AAAAAAAAAA']);
    const s = useRealtimeStore.getState();
    expect(s.channelStatus).toBe('connected');
    expect(s.presentPublicRefs).toEqual(['P-AAAAAAAAAA']);
  });
  it('reset vuelve al estado inicial', () => {
    useRealtimeStore.getState().setPresence(['P-AAAAAAAAAA']);
    useRealtimeStore.getState().reset();
    expect(useRealtimeStore.getState().presentPublicRefs).toEqual([]);
  });
});
