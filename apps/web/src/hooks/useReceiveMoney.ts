import { useEffect, useRef, useState } from 'react';
import type { ActiveSnapshot } from '../lib/activeSnapshot';
import { computeReceive, describeReceive, initialReceiveTracker, type ReceiveTracker } from '../lib/receiveMoney';
import { isCashSoundEnabled, playCashSound } from '../lib/cashSound';

export interface ReceiveFlash {
  amount: number;   // importe recibido (>0)
  message: string;  // texto descriptivo derivado del ledger
}

/** Efecto "dinero recibido": cuando MI saldo aumenta entre snapshots, reproduce el sonido (si está
 *  activado) y devuelve el importe + mensaje para mostrar un banner central ~3s. No salta en el primer
 *  snapshot ni dos veces por el mismo runtime_version; nunca por el saldo de otro jugador. */
export function useReceiveMoney(snap: ActiveSnapshot | null): ReceiveFlash | null {
  const tracker = useRef<ReceiveTracker>(initialReceiveTracker);
  const [flash, setFlash] = useState<ReceiveFlash | null>(null);
  const version = snap?.runtime_version ?? null;
  const balance = snap?.me.balance ?? null;

  useEffect(() => {
    if (!snap) return;
    const res = computeReceive(tracker.current, snap);
    tracker.current = res.next;
    if (res.play) {
      if (isCashSoundEnabled()) playCashSound();
      setFlash({ amount: res.delta, message: describeReceive(snap, res.delta) });
    }
    // Solo nos interesa reaccionar a cambios de versión/saldo propio.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version, balance]);

  useEffect(() => {
    if (flash === null) return;
    const t = setTimeout(() => setFlash(null), 3000);
    return () => clearTimeout(t);
  }, [flash]);

  return flash;
}
