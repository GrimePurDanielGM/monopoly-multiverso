import { useEffect, useRef } from 'react';
import type { ActiveSnapshot } from '../lib/activeSnapshot';
import { playSfx } from '../lib/sfx';

/** Sonidos de cárcel del jugador local: sirena al ENTRAR (no preso → preso) y puerta al SALIR
 *  (preso → no preso, por pago/carta/dobles/forzado). No suena en el primer snapshot ni dos veces por
 *  el mismo runtime_version; falla en silencio (playSfx). */
export function useJailSounds(snap: ActiveSnapshot | null): void {
  const lastVersion = useRef<number | null>(null);
  const lastJailed = useRef<boolean | null>(null);
  const version = snap?.runtime_version ?? null;
  const jailed = snap ? snap.my_jail !== null : null;

  useEffect(() => {
    if (version === null || jailed === null) return;
    if (lastVersion.current === version) return; // mismo snapshot ya procesado
    const prevJailed = lastJailed.current;
    lastVersion.current = version;
    lastJailed.current = jailed;
    if (prevJailed === null) return;              // primer snapshot: solo fija la línea base
    if (!prevJailed && jailed) playSfx('siren');  // me han enviado a la cárcel
    else if (prevJailed && !jailed) playSfx('door'); // he salido de la cárcel
  }, [version, jailed]);
}
