// Lógica pura del efecto "dinero recibido": decide si suena al aumentar MI saldo entre snapshots.
// Sin estado, sin red, sin audio (testeable). El cliente reproduce el sonido si play=true.
import type { ActiveSnapshot } from './activeSnapshot';
import { formatMoney } from './activeSelectors';

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

/** Mensaje descriptivo del banner "dinero recibido": intenta derivarlo del último asiento del
 *  ledger que ME abona (to_ref = yo); si no lo encuentra, cae en un texto genérico con el importe.
 *  Puro: no muta nada, no formatea fuera de `formatMoney`. */
export function describeReceive(snap: ActiveSnapshot, delta: number): string {
  const money = formatMoney(delta);
  const me = snap.me.public_ref;
  // Asiento más reciente (mayor seq) que me abona dinero.
  const credit = snap.ledger_recent
    .filter((l) => l.to_ref === me && l.amount > 0)
    .reduce<typeof snap.ledger_recent[number] | null>((best, l) => (!best || l.seq > best.seq ? l : best), null);
  if (!credit) return `Has recibido ${money}`;
  const fromName = credit.from_ref === null
    ? null
    : snap.players.find((p) => p.public_ref === credit.from_ref)?.display_name ?? null;
  switch (credit.kind) {
    case 'pass_start_bonus':
      return `Has cobrado ${money} al pasar por salida`;
    case 'rent_payment':
      return fromName ? `${fromName} te ha pagado ${money} de alquiler` : `Has cobrado ${money} de alquiler`;
    case 'player_to_player':
    case 'host_player_transfer':
      return fromName ? `${fromName} te ha pagado ${money}` : `Te han pagado ${money}`;
    case 'bank_to_player':
    case 'seed':
    case 'late_join_seed':
    case 'host_adjust':
      return `Has recibido ${money} de la banca`;
    default:
      return fromName ? `${fromName} te ha pagado ${money}` : `Has recibido ${money}`;
  }
}
