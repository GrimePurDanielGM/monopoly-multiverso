import { useEffect, useRef, useState } from 'react';
import type { ActiveSnapshot } from '../lib/activeSnapshot';

export interface GlobalBannerData {
  name: string;   // jugador que originó el evento
  amount: number; // importe (p. ej. bote cobrado)
}

/** Banner GLOBAL de partida para TODOS (Fase 5 corrección): hoy, cobro del bote del Parking. Se basa en
 *  last_global_event.event_id (único por evento), no en inferencias. No aparece en el primer snapshot ni
 *  al recargar (línea base por montaje) ni dos veces por el mismo evento. Se autodescarta a los 3 s. */
export function useGlobalEvent(snap: ActiveSnapshot | null): GlobalBannerData | null {
  const evt = snap?.last_global_event ?? null;
  const eventId = evt?.event_id ?? null;
  const primed = useRef(false);
  const lastId = useRef<string | null>(null);
  const [banner, setBanner] = useState<GlobalBannerData | null>(null);

  useEffect(() => {
    if (!primed.current) { primed.current = true; lastId.current = eventId; return; } // línea base (no mostrar al cargar)
    if (eventId === lastId.current) return;
    lastId.current = eventId;
    if (evt && evt.kind === 'parking_pot_payout') {
      const name = snap?.players.find((p) => p.public_ref === evt.player_ref)?.display_name ?? 'Un jugador';
      setBanner({ name, amount: evt.amount });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [eventId]);

  useEffect(() => {
    if (!banner) return;
    const t = setTimeout(() => setBanner(null), 3000);
    return () => clearTimeout(t);
  }, [banner]);

  return banner;
}
