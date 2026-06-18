import type { ActiveSnapshot } from '../../lib/activeSnapshot';

/** Bloque "Control de la partida" (solo anfitrión). running: Pausar/Finalizar;
 *  paused: Reanudar/Finalizar; finished: no se muestra. */
export function GameControlPanel({
  snap,
  busy,
  onPause,
  onResume,
  onFinish,
}: {
  snap: ActiveSnapshot;
  busy: boolean;
  onPause: () => void;
  onResume: () => void;
  onFinish: () => void;
}) {
  if (snap.runtime_status === 'finished') return null;
  const paused = snap.runtime_status === 'paused';
  return (
    <section aria-label="Control de la partida" className="flex flex-col gap-2 rounded-xl border border-slate-600 p-4">
      <h2 className="text-sm font-bold text-slate-200">Control de la partida</h2>
      {paused ? (
        <button type="button" onClick={onResume} disabled={busy}
          className="min-h-[44px] rounded-xl bg-emerald-600 px-4 text-sm font-semibold disabled:opacity-40">
          Reanudar partida
        </button>
      ) : (
        <button type="button" onClick={onPause} disabled={busy}
          className="min-h-[44px] rounded-xl bg-amber-600 px-4 text-sm font-semibold disabled:opacity-40">
          Pausar partida
        </button>
      )}
      <button type="button" onClick={onFinish} disabled={busy}
        className="min-h-[44px] rounded-xl border border-rose-500/60 px-4 text-sm font-semibold text-rose-300 disabled:opacity-40">
        Finalizar partida
      </button>
    </section>
  );
}

/** Aviso visible para todos cuando la partida está en pausa. */
export function PausedBanner() {
  return (
    <div role="status" aria-live="polite" className="rounded-xl border border-amber-500 bg-amber-950/50 p-4 text-center">
      <p className="text-base font-bold text-amber-200">Partida en pausa</p>
      <p className="mt-0.5 text-sm text-amber-300/90">El anfitrión debe reanudarla para continuar.</p>
    </div>
  );
}
