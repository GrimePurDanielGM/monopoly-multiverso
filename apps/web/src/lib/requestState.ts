// Máquina de estados de las solicitudes (recovery/reentry) y utilidades de bloqueo del PIN.
export type RequestStatus = 'pending' | 'approved' | 'rejected' | 'cancelled' | 'expired';
export type RequestKind = 'recovery' | 'reentry' | 'late_join';

/** Estado terminal: ya no hay que seguir consultando. */
export function isTerminal(status: RequestStatus): boolean {
  return status !== 'pending';
}

/** Mensaje legible para cada estado terminal de una solicitud. */
export function requestResultMessage(status: RequestStatus): string {
  switch (status) {
    case 'approved':
      return 'Tu solicitud fue aprobada.';
    case 'rejected':
      return 'El anfitrión rechazó tu solicitud.';
    case 'cancelled':
      return 'La solicitud fue cancelada.';
    case 'expired':
      return 'La solicitud caducó.';
    default:
      return 'Solicitud pendiente de aprobación…';
  }
}

/** ms restantes de bloqueo (0 si ya no está bloqueado o no hay fecha). */
export function remainingLockMs(lockedUntil: string | null | undefined, nowMs: number): number {
  if (!lockedUntil) return 0;
  const until = Date.parse(lockedUntil);
  if (Number.isNaN(until)) return 0;
  return Math.max(0, until - nowMs);
}

/** Formatea ms como mm:ss. */
export function formatCountdown(ms: number): string {
  const total = Math.ceil(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}
