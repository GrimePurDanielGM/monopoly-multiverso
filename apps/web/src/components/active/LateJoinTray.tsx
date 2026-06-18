import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { formatMoney } from '../../lib/activeSelectors';

/** Bandeja diferenciada del anfitrión para solicitudes de incorporación tardía.
 *  No se mezcla con recuperación de jugador ni reentrada de expulsados. */
export function LateJoinTray({
  snap,
  icons,
  busy,
  onResolve,
}: {
  snap: ActiveSnapshot;
  icons: Record<string, string>;
  busy: boolean;
  onResolve: (requestRef: string, accept: boolean) => void;
}) {
  if (snap.late_join_requests.length === 0) return null;
  return (
    <section aria-label="Solicitudes para entrar en la partida" className="flex flex-col gap-2 rounded-xl border border-sky-500/40 p-4">
      <h2 className="text-sm font-bold text-sky-300">Solicitudes para entrar en la partida ({snap.late_join_requests.length})</h2>
      <p className="text-xs text-slate-400">
        Entrarán con {formatMoney(snap.game.config.initial_money)} y se añadirán al final del orden de turnos.
      </p>
      {snap.late_join_requests.map((r) => (
        <div key={r.request_ref} className="flex items-center gap-2 rounded-lg border border-slate-700 px-3 py-2 text-sm">
          <span aria-hidden className="text-2xl leading-none">{icons[r.token] ?? '·'}</span>
          <span className="flex-1 truncate">
            {r.name}
            {r.device_label && <span className="ml-2 text-xs text-slate-500">{r.device_label}</span>}
          </span>
          <button type="button" onClick={() => onResolve(r.request_ref, true)} disabled={busy}
            className="min-h-[36px] rounded-lg bg-emerald-600 px-3 text-xs font-semibold disabled:opacity-40">
            Aceptar
          </button>
          <button type="button" onClick={() => onResolve(r.request_ref, false)} disabled={busy}
            className="min-h-[36px] rounded-lg border border-rose-500/50 px-3 text-xs font-semibold text-rose-300 disabled:opacity-40">
            Rechazar
          </button>
        </div>
      ))}
    </section>
  );
}
