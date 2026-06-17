import { useEffect, useState } from 'react';
import { formatCountdown, remainingLockMs } from '../lib/requestState';

/** Cuenta atrás hasta lockedUntil (mm:ss). Llama a onExpire al llegar a 0. */
export function LockedCountdown({ lockedUntil, onExpire }: { lockedUntil: string; onExpire?: () => void }) {
  const [ms, setMs] = useState(() => remainingLockMs(lockedUntil, Date.now()));
  useEffect(() => {
    const id = setInterval(() => {
      const left = remainingLockMs(lockedUntil, Date.now());
      setMs(left);
      if (left <= 0) {
        clearInterval(id);
        onExpire?.();
      }
    }, 1000);
    return () => clearInterval(id);
  }, [lockedUntil, onExpire]);
  if (ms <= 0) return null;
  return <span aria-label="Tiempo de bloqueo restante">{formatCountdown(ms)}</span>;
}
