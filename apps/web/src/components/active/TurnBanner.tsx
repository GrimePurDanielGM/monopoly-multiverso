import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { currentPlayerName } from '../../lib/activeSelectors';

/** Cabecera de turno: número de turno y de quién es (con "Tu turno" destacado). */
export function TurnBanner({ snap }: { snap: ActiveSnapshot }) {
  const mine = snap.me.is_current;
  return (
    <div
      role="status"
      aria-live="polite"
      className={`rounded-xl border p-4 ${mine ? 'border-emerald-500 bg-emerald-950/40' : 'border-slate-700'}`}
    >
      <p className="text-[11px] uppercase tracking-wide text-slate-400">Turno {snap.turn.turn_number}</p>
      <p className="mt-0.5 text-lg font-bold">
        {mine ? 'Tu turno' : `Turno de ${currentPlayerName(snap)}`}
      </p>
    </div>
  );
}
