import type { ReceiveFlash } from '../../hooks/useReceiveMoney';
import { formatMoney } from '../../lib/activeSelectors';

/** Banner central de "dinero recibido": tarjeta flotante visible ~3s con el importe y un texto
 *  derivado del ledger. No bloquea la interacción (pointer-events-none) y es accesible (role=status,
 *  aria-live). El temporizado de 3s y la decisión de mostrarlo viven en useReceiveMoney. */
export function MoneyBanner({ flash }: { flash: ReceiveFlash | null }) {
  if (!flash) return null;
  return (
    <div
      role="status"
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 top-1/3 z-50 flex justify-center px-4"
    >
      <div className="flex animate-money-in flex-col items-center gap-1 rounded-2xl border border-emerald-500/40 bg-emerald-900/90 px-6 py-4 text-center shadow-xl shadow-black/40 backdrop-blur">
        <span className="text-3xl font-extrabold tabular-nums text-emerald-100">
          +{formatMoney(flash.amount)}
        </span>
        <span className="text-sm font-medium text-emerald-200">{flash.message}</span>
      </div>
    </div>
  );
}
