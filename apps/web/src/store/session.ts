// Estado de la sesión anónima. Guarda SOLO el estado (nunca el uid de sesión).
import { create } from 'zustand';
import type { SessionStatus } from '../lib/session';

interface SessionState {
  status: SessionStatus;
  setStatus: (s: SessionStatus) => void;
}

export const useSessionStore = create<SessionState>((set) => ({
  status: 'loading',
  setStatus: (status) => set({ status }),
}));
