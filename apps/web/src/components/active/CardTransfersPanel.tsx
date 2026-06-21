import type { CardTransfer } from '../../lib/activeSnapshot';
import { formatMoney } from '../../lib/activeSelectors';

/** Banner de autorización de transferencias de carta «a cada jugador». El que mira es siempre el PAGADOR:
 *  autoriza pagar el importe al destinatario. Aparece para cobros (cada jugador paga al que robó) y para
 *  pagos (el que robó paga a cada jugador). */
export function CardTransfersPanel({ transfers, busy, onAuthorize }: {
  transfers: CardTransfer[]; busy: boolean; onAuthorize: (t: CardTransfer) => void;
}) {
  if (transfers.length === 0) return null;
  return (
    <section aria-label="Transferencias de carta" className="flex flex-col gap-2 rounded-xl border border-fuchsia-600/40 p-4">
      <h2 className="text-sm font-bold text-fuchsia-200">Pagos pendientes de una carta</h2>
      {transfers.map((t) => (
        <div key={t.transfer_ref} className="flex flex-wrap items-center gap-2 rounded-lg border border-slate-700 px-3 py-2 text-sm">
          <span className="flex-1">Debes pagar <span className="font-semibold tabular-nums">{formatMoney(t.amount)}</span> a <span className="font-semibold">{t.payee_name}</span>.</span>
          <button type="button" onClick={() => onAuthorize(t)} disabled={busy}
            className="min-h-[36px] rounded-lg bg-fuchsia-600 px-3 text-xs font-semibold disabled:opacity-40">
            Autorizar pago
          </button>
        </div>
      ))}
    </section>
  );
}
