import type { ConnStatus } from '../lib/connState';

/** Indicador/banner de conexión general. El botón de reintento aparece solo si está desconectado. */
export function ConnectionBar({ status, onRetry }: { status: ConnStatus; onRetry: () => void }) {
  if (status === 'offline') {
    return (
      <p role="status" className="rounded-lg bg-rose-950/60 px-3 py-1.5 text-center text-xs text-rose-200">
        Sin conexión
      </p>
    );
  }
  if (status === 'reconnecting') {
    return (
      <p role="status" className="rounded-lg bg-amber-950/60 px-3 py-1.5 text-center text-xs text-amber-200">
        Reconectando…
      </p>
    );
  }
  if (status === 'disconnected') {
    return (
      <div role="alert" className="flex items-center justify-between rounded-lg bg-rose-950/60 px-3 py-1.5 text-xs text-rose-200">
        <span>Conexión perdida</span>
        <button type="button" onClick={onRetry} className="rounded border border-rose-400/50 px-2 py-0.5 font-semibold">
          Reintentar
        </button>
      </div>
    );
  }
  if (status === 'connecting') {
    return (
      <p role="status" className="rounded-lg bg-slate-800 px-3 py-1.5 text-center text-xs text-slate-300">
        Conectando…
      </p>
    );
  }
  return (
    <p role="status" className="flex items-center justify-center gap-1.5 text-center text-xs text-emerald-400">
      <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
      Conectado
    </p>
  );
}

/** Punto de presencia por jugador. */
export function PresenceDot({ status }: { status: 'connected' | 'reconnecting' | 'disconnected' }) {
  const color = status === 'connected' ? 'bg-emerald-400' : status === 'reconnecting' ? 'bg-amber-400' : 'bg-slate-600';
  const label = status === 'connected' ? 'Conectado' : status === 'reconnecting' ? 'Reconectando' : 'Desconectado';
  return <span title={label} aria-label={label} className={`h-2 w-2 shrink-0 rounded-full ${color}`} />;
}
