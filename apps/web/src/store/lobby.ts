// Store del lobby. SOLO contiene datos saneados del snapshot (nunca ids de auth, JWT,
// PIN, pepper, hashes, salts, filas crudas ni jugadores expulsados). El snapshot completo
// SUSTITUYE el estado anterior; no se mezclan fragmentos ni se presuponen cambios locales.
import { create } from 'zustand';
import type { LobbySnapshot, SnapGame, SnapPlayer, SnapMe, SnapRequest, SnapCounts } from '../lib/snapshot';

export type SnapshotStatus = 'idle' | 'loading' | 'ready' | 'not_member' | 'kicked' | 'error';

interface LobbyState {
  game: SnapGame | null;
  players: SnapPlayer[];
  me: SnapMe | null;
  requests: SnapRequest[];
  counts: SnapCounts | null;
  snapshotStatus: SnapshotStatus;
  lastLoadedAt: number | null;
  error: string | null;
  replaceSnapshot: (snapshot: LobbySnapshot, at: number) => void;
  setStatus: (status: SnapshotStatus) => void;
  setError: (status: SnapshotStatus, error: string | null) => void;
  reset: () => void;
}

const EMPTY = {
  game: null,
  players: [] as SnapPlayer[],
  me: null,
  requests: [] as SnapRequest[],
  counts: null,
};

export const useLobbyStore = create<LobbyState>((set) => ({
  ...EMPTY,
  snapshotStatus: 'idle',
  lastLoadedAt: null,
  error: null,
  // El snapshot autoritativo reemplaza por completo el estado anterior.
  replaceSnapshot: (snapshot, at) =>
    set({
      game: snapshot.game,
      players: snapshot.players,
      me: snapshot.me,
      requests: snapshot.requests,
      counts: snapshot.counts,
      snapshotStatus: 'ready',
      lastLoadedAt: at,
      error: null,
    }),
  setStatus: (snapshotStatus) => set({ snapshotStatus }),
  setError: (snapshotStatus, error) => set({ snapshotStatus, error }),
  reset: () => set({ ...EMPTY, snapshotStatus: 'idle', lastLoadedAt: null, error: null }),
}));
