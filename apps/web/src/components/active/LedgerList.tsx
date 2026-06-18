import type { ActiveSnapshot, LedgerEntry } from '../../lib/activeSnapshot';
import { formatMoney, kindLabel, refLabel, isRevertible } from '../../lib/activeSelectors';

/** Movimientos recientes. Si es anfitrión, permite revertir por ledger_ref los reversibles. */
export function LedgerList({
  snap,
  isHost,
  busy,
  onRevert,
}: {
  snap: ActiveSnapshot;
  isHost: boolean;
  busy: boolean;
  onRevert: (ledgerRef: string) => void;
}) {
  if (snap.ledger_recent.length === 0) {
    return <p className="text-sm text-slate-500">Aún no hay movimientos.</p>;
  }
  return (
    <ul aria-label="Movimientos recientes" className="flex flex-col gap-2">
      {snap.ledger_recent.map((e: LedgerEntry) => (
        <li key={e.ledger_ref} className="flex items-center gap-2 rounded-lg border border-slate-700 px-3 py-2 text-sm">
          <div className="flex-1">
            <p>
              <span className="font-medium">{kindLabel(e.kind)}</span>{' '}
              <span className="text-slate-400">
                {refLabel(e.from_ref, snap.players)} → {refLabel(e.to_ref, snap.players)}
              </span>
            </p>
            {e.reason && <p className="text-xs text-slate-500">Motivo: {e.reason}</p>}
          </div>
          <span className="font-semibold tabular-nums">{formatMoney(e.amount)}</span>
          {isHost && isRevertible(e) && (
            <button
              type="button"
              onClick={() => onRevert(e.ledger_ref)}
              disabled={busy}
              className="min-h-[36px] rounded-lg border border-amber-500/50 px-2 text-xs font-semibold text-amber-300 disabled:opacity-40"
            >
              Revertir
            </button>
          )}
        </li>
      ))}
    </ul>
  );
}
