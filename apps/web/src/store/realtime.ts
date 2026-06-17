// Estado de transporte Realtime. SEPARADO del snapshot autoritativo: NO duplica nombres,
// fichas, ready, host, config ni jugadores completos. Lo visual sale de cruzar
// snapshot.players (store de lobby) con presentPublicRefs (aquí).
import { create } from 'zustand';
import type { ConnStatus } from '../lib/connState';

interface RealtimeState {
  channelStatus: ConnStatus;
  presentPublicRefs: string[];
  lastRealtimeEventAt: number | null;
  lastSuccessfulSyncAt: number | null;
  isDocumentVisible: boolean;
  transportError: string | null;
  setChannelStatus: (s: ConnStatus) => void;
  setPresence: (refs: string[]) => void;
  markEvent: (at: number) => void;
  markSync: (at: number) => void;
  setVisible: (v: boolean) => void;
  setTransportError: (e: string | null) => void;
  reset: () => void;
}

const INITIAL = {
  channelStatus: 'connecting' as ConnStatus,
  presentPublicRefs: [] as string[],
  lastRealtimeEventAt: null as number | null,
  lastSuccessfulSyncAt: null as number | null,
  isDocumentVisible: true,
  transportError: null as string | null,
};

export const useRealtimeStore = create<RealtimeState>((set) => ({
  ...INITIAL,
  setChannelStatus: (channelStatus) => set({ channelStatus }),
  setPresence: (presentPublicRefs) => set({ presentPublicRefs }),
  markEvent: (lastRealtimeEventAt) => set({ lastRealtimeEventAt }),
  markSync: (lastSuccessfulSyncAt) => set({ lastSuccessfulSyncAt }),
  setVisible: (isDocumentVisible) => set({ isDocumentVisible }),
  setTransportError: (transportError) => set({ transportError }),
  reset: () => set({ ...INITIAL }),
}));
