import { useState } from 'react';
import type { ActiveSnapshot, LastCardDraw } from '../lib/activeSnapshot';

export interface CardToShow {
  card: LastCardDraw;
  mustResolve: boolean; // carta de resolución manual: hay que marcarla resuelta (no se descarta sin RPC)
  choice: boolean;      // carta de elección: pagar al bote o robar una carta de Suerte
  instruction: string | null; // instrucción para el anfitrión (movimiento especial / reparaciones / elección)
}

/** Decide cuándo mostrar el modal de carta al jugador local: al robar una carta NUEVA para mí (por
 *  draw_id, descartable con "Aceptar") o mientras tenga una carta manual pendiente (persiste hasta
 *  resolverla). Devuelve la carta a mostrar (o null) y un dismiss() para cerrar las ya aplicadas. */
export function useCardDraw(snap: ActiveSnapshot | null): { show: CardToShow | null; dismiss: () => void } {
  const me = snap?.me.public_ref ?? null;
  const draw = snap?.last_card_draw ?? null;
  const pending = snap?.pending_card ?? null;
  const [dismissedId, setDismissedId] = useState<string | null>(null);

  const mineManual = !!(pending && me && pending.player_ref === me);
  const mineDraw = !!(draw && me && draw.player_ref === me);

  let show: CardToShow | null = null;
  if (mineManual && draw) {
    show = { card: draw, mustResolve: true, choice: pending?.kind === 'choice',
      instruction: pending?.manual_instruction ?? draw.manual_instruction };
  } else if (mineDraw && draw && draw.draw_id !== dismissedId) {
    show = { card: draw, mustResolve: false, choice: false, instruction: draw.manual_instruction };
  }

  const dismiss = () => { if (draw) setDismissedId(draw.draw_id); };
  return { show, dismiss };
}
