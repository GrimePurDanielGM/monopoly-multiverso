// Sondea el estado de una solicitud (recovery/reentry) hasta un estado terminal.
// Se detiene en terminal y al desmontar; un único intervalo (sin duplicados); los fallos
// transitorios se reintentan en el siguiente tick SIN crear otra solicitud.
import { useEffect, useRef } from 'react';
import { getRequestStatus } from '../lib/api';
import { isTerminal } from '../lib/requestState';
import { useRequestStore } from '../store/request';

const POLL_MS = 2500;

export function useRequestPolling(onApproved: () => void): void {
  const onApprovedRef = useRef(onApproved);
  onApprovedRef.current = onApproved;
  const requestRef = useRequestStore((s) => s.requestRef);

  useEffect(() => {
    if (!requestRef) return;
    const rq = useRequestStore.getState;
    const cur = rq().status;
    if (cur && isTerminal(cur)) {
      rq().setPolling(false);
      return;
    }

    let cancelled = false;
    let timer: ReturnType<typeof setInterval> | undefined;
    const stop = () => {
      if (timer !== undefined) {
        clearInterval(timer);
        timer = undefined;
      }
      rq().setPolling(false);
    };

    const tick = async () => {
      if (cancelled) return;
      const r = await getRequestStatus(requestRef);
      if (cancelled) return;
      if (r.ok) {
        rq().setError(null);
        rq().setStatus(r.data.status);
        if (isTerminal(r.data.status)) {
          stop();
          if (r.data.status === 'approved') onApprovedRef.current();
        }
      } else {
        rq().setError(r.message); // transitorio: se reintenta; nunca se crea otra solicitud
      }
    };

    rq().setPolling(true);
    void tick();
    timer = setInterval(() => void tick(), POLL_MS);
    return () => {
      cancelled = true;
      stop();
    };
  }, [requestRef]);
}
