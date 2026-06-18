import { useEffect, useRef, useState } from 'react';
import type { ActiveSnapshot } from '../lib/activeSnapshot';
import { computeReceive, initialReceiveTracker, type ReceiveTracker } from '../lib/receiveMoney';
import { isCashSoundEnabled, playCashSound } from '../lib/cashSound';

/** Efecto "dinero recibido": cuando MI saldo aumenta entre snapshots, reproduce el sonido (si está
 *  activado) y devuelve el importe recibido para mostrar un flash. No suena en el primer snapshot ni
 *  dos veces por el mismo runtime_version. Devuelve el delta (o null) para el feedback visual. */
export function useReceiveMoney(snap: ActiveSnapshot | null): number | null {
  const tracker = useRef<ReceiveTracker>(initialReceiveTracker);
  const [flash, setFlash] = useState<number | null>(null);
  const version = snap?.runtime_version ?? null;
  const balance = snap?.me.balance ?? null;

  useEffect(() => {
    if (!snap) return;
    const res = computeReceive(tracker.current, snap);
    tracker.current = res.next;
    if (res.play) {
      if (isCashSoundEnabled()) playCashSound();
      setFlash(res.delta);
    }
    // Solo nos interesa reaccionar a cambios de versión/saldo propio.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version, balance]);

  useEffect(() => {
    if (flash === null) return;
    const t = setTimeout(() => setFlash(null), 2500);
    return () => clearTimeout(t);
  }, [flash]);

  return flash;
}
