import { create } from 'zustand';
import type { ActiveSnapshot } from '../lib/activeSnapshot';

interface ActiveState {
  snap: ActiveSnapshot | null;
  /** Sustituye el snapshot autoritativo (descarta versiones más viejas por runtime_version). */
  replaceActive: (snap: ActiveSnapshot) => void;
  clearActive: () => void;
}

export const useActiveStore = create<ActiveState>((set) => ({
  snap: null,
  replaceActive: (snap) =>
    set((s) => {
      // Nunca retroceder a una versión anterior (llegada fuera de orden).
      if (s.snap && s.snap.game.code === snap.game.code && snap.runtime_version < s.snap.runtime_version) return s;
      return { snap };
    }),
  clearActive: () => set({ snap: null }),
}));
