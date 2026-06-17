import type { SnapRequest } from '../lib/snapshot';

/** Tarjeta de una solicitud en la bandeja del anfitrión. */
export function RecoveryRequestCard({
  request,
  name,
  busy,
  onAccept,
  onReject,
}: {
  request: SnapRequest;
  name: string;
  busy: boolean;
  onAccept: () => void;
  onReject: () => void;
}) {
  const kindLabel = request.kind === 'recovery' ? 'Recuperación' : 'Reentrada';
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-slate-700 p-3">
      <p className="text-sm font-medium">
        {kindLabel}: <span className="text-slate-200">{name}</span>
      </p>
      {request.device_label && <p className="text-xs text-slate-400">Dispositivo: {request.device_label}</p>}
      <div className="flex gap-2">
        <button
          type="button"
          disabled={busy}
          onClick={onAccept}
          className="min-h-[44px] flex-1 rounded-lg bg-emerald-600 px-3 text-sm font-semibold disabled:opacity-40"
        >
          Aceptar
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={onReject}
          className="min-h-[44px] flex-1 rounded-lg border border-rose-500/50 px-3 text-sm font-semibold text-rose-300 disabled:opacity-40"
        >
          Rechazar
        </button>
      </div>
    </div>
  );
}
