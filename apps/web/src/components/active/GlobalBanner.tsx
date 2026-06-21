import type { GlobalBannerData } from '../../hooks/useGlobalEvent';

/** Banner GLOBAL central: cuando alguien cobra el bote del Parking o gira la ruleta de Parking, TODOS lo ven ~3 s.
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
        <span aria-hidden className="text-2xl">{banner.icon}</span>
        <span className="text-sm font-semibold text-sky-100">
          <span className="font-bold">{banner.name}</span> {banner.text}
        </span>
      </div>
    </div>
  );
}
