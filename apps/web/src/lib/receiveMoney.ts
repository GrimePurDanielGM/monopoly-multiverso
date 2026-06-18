// Lógica pura del efecto "dinero recibido": decide si suena al aumentar MI saldo entre snapshots.
// Sin estado, sin red, sin audio (testeable). El cliente reproduce el sonido si play=true.
import type { ActiveSnapshot } from './activeSnapshot';

export interface ReceiveTracker {
  lastBalance: number | null; // saldo propio del snapshot anterior (null = aún no hay)
  lastVersion: number | null; // runtime_version ya procesado (evita doble disparo)
}
export const initialReceiveTracker: ReceiveTracker = { lastBalance: null, lastVersion: null };

export interface ReceiveResult {
  play: boolean; // ¿reproducir el sonido / mostrar el flash?
  delta: number; // cuánto ha aumentado (0 si no procede)
  next: ReceiveTracker; // tracker actualizado para el siguiente snapshot
}

/** Decide si suena el efecto de dinero recibido para el jugador local:
 *  - NO en el primer snapshot (solo fija la línea base);
 *  - solo si MI saldo aumenta respecto al snapshot anterior;
 *  - nunca dos veces por el mismo runtime_version;
 *  - nunca para un espectador (en bancarrota no controla saldo activo). */
export function computeReceive(prev: ReceiveTracker, snap: ActiveSnapshot): ReceiveResult {
  const balance = snap.me.balance;
  const version = snap.runtime_version;
  // Mismo runtime_version ya procesado: no reproducir y no alterar la línea base.
  if (prev.lastVersion !== null && prev.lastVersion === version) {
    return { play: false, delta: 0, next: prev };
  }
  const next: ReceiveTracker = { lastBalance: balance, lastVersion: version };
  if (prev.lastBalance === null) return { play: false, delta: 0, next }; // primer snapshot
  const delta = balance - prev.lastBalance;
  const play = delta > 0 && !snap.me.is_spectator;
  return { play, delta: play ? delta : 0, next };
}
