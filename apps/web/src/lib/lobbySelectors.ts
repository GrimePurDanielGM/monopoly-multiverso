// Selectores derivados del snapshot (puros, testeables). El servidor es la autoridad;
// estos solo presentan/derivan a partir del snapshot saneado.
import type { SnapMe, SnapPlayer } from './snapshot';

/** Conjunto de token_id ya ocupados por jugadores activos. */
export function takenTokenIds(players: readonly SnapPlayer[]): Set<string> {
  const taken = new Set<string>();
  for (const p of players) {
    if (p.token_id !== null) taken.add(p.token_id);
  }
  return taken;
}

/** true si el jugador del snapshot es el jugador actual (por public_ref). */
export function isMe(player: SnapPlayer, me: SnapMe): boolean {
  return player.public_ref === me.public_ref;
}

/** Solo se puede marcar "preparado" (true) si ya hay ficha elegida. Quitarlo siempre se permite. */
export function canSetReady(me: SnapMe, next: boolean): boolean {
  if (!next) return true;
  return me.token_id !== null;
}
