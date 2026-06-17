// Estado mínimo de una solicitud (recovery/reentry) EN CURSO. Separado del lobby.
// NUNCA contiene JWT, identificadores de auth, PIN, secretos ni filas internas.
import { create } from 'zustand';
import type { RequestKind, RequestStatus } from '../lib/requestState';

interface RequestState {
  requestRef: string | null;
  kind: RequestKind | null;
  status: RequestStatus | null;
  isPolling: boolean;
  error: string | null;
  start: (requestRef: string, kind: RequestKind, status: RequestStatus) => void;
  setStatus: (status: RequestStatus) => void;
  setPolling: (v: boolean) => void;
  setError: (e: string | null) => void;
  reset: () => void;
}

const EMPTY = { requestRef: null, kind: null, status: null, isPolling: false, error: null } as const;

export const useRequestStore = create<RequestState>((set) => ({
  ...EMPTY,
  start: (requestRef, kind, status) => set({ requestRef, kind, status, isPolling: true, error: null }),
  setStatus: (status) => set({ status }),
  setPolling: (isPolling) => set({ isPolling }),
  setError: (error) => set({ error }),
  reset: () => set({ ...EMPTY }),
}));
