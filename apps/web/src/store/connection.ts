import { create } from 'zustand';

interface ConnectionState {
  online: boolean;
  setOnline: (v: boolean) => void;
}

/** Estado mínimo de conexión (placeholder de Fase 0; el estado de partida llega en fases >0). */
export const useConnectionStore = create<ConnectionState>((set) => ({
  online: typeof navigator === 'undefined' ? true : navigator.onLine,
  setOnline: (v) => set({ online: v }),
}));
