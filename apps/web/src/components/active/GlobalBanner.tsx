import type { GlobalBannerData } from '../../hooks/useGlobalEvent';
import { formatMoney } from '../../lib/activeSelectors';

/** Banner GLOBAL central (Fase 5 corrección): cuando alguien cobra el bote del Parking, TODOS lo ven ~3 s.
 *  Independiente del banner privado de dinero. role=status/aria-live; no bloquea la interacción. */
export function GlobalBanner({ banner }: { banner: GlobalBannerData | null }) {
  if (!banner) return null;
  return (
    <div
      role="status"
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 top-1/4 z-50 flex justify-center px-4"
    >
      <div className="flex animate-money-in flex-col items-center gap-1 rounded-2xl border border-sky-500/40 bg-sky-900/90 px-6 py-4 text-center shadow-xl shadow-black/40 backdrop-blur">
        <span aria-hidden className="text-2xl">🅿️💰</span>
        <span className="text-sm font-semibold text-sky-100">
          <span className="font-bold">{banner.name}</span> ha cobrado el bote de Parking: {formatMoney(banner.amount)}
        </span>
      </div>
    </div>
  );
}
