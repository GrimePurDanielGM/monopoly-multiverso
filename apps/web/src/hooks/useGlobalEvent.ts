import { useEffect, useRef, useState } from 'react';
import type { ActiveSnapshot } from '../lib/activeSnapshot';

export interface GlobalBannerData {
  name: string;   // jugador que originó el evento
  amount: number; // importe (p. ej. bote cobrado)
  text: string;   // mensaje a mostrar (bote o resultado de la ruleta)
  icon: string;   // emoji
}

const ROULETTE_TEXT: Record<string, string> = {
  collect_pot: 'cobra el bote del Parking',
  draw_card: 'gira la ruleta y roba una carta',
  go_to_jail: 'gira la ruleta y va a la cárcel',
  lose_most_valuable: 'gira la ruleta y pierde su propiedad más valiosa',
  lose_least_valuable: 'gira la ruleta y pierde su propiedad menos valiosa',
  pay_500: 'gira la ruleta y paga 500 € al bote',
};

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
    if (evt && (evt.kind === 'parking_pot_payout' || evt.kind === 'parking_roulette')) {
      const name = snap?.players.find((p) => p.public_ref === evt.player_ref)?.display_name ?? 'Un jugador';
      if (evt.kind === 'parking_pot_payout') {
        setBanner({ name, amount: evt.amount, text: `ha cobrado el bote de Parking: ${evt.amount}`, icon: '🅿️💰' });
      } else {
        const t = ROULETTE_TEXT[evt.outcome ?? ''] ?? 'gira la ruleta de Parking';
        const amt = evt.outcome === 'collect_pot' || evt.outcome === 'pay_500' ? ` (${evt.amount} €)` : '';
        setBanner({ name, amount: evt.amount, text: `${t}${amt}`, icon: '🎡' });
      }
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
