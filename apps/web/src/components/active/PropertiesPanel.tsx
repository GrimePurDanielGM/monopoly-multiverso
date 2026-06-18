import type { ActiveProperty, ActiveSnapshot } from '../../lib/activeSnapshot';
import {
  formatMoney, propertiesByBoard, propertyStatus, canBuyProperty, canPayRent, ownerName, myProperties,
} from '../../lib/activeSelectors';

const KIND_LABEL: Record<string, string> = {
  street: 'Calle', station: 'Estación', utility: 'Servicio', special: 'Especial',
};

/** Sección "Propiedades": vista general por tablero + acciones (Comprar / Pagar alquiler / Tuya)
 *  y un bloque "Mis propiedades". Las acciones se deshabilitan en pausa/finalización. */
export function PropertiesPanel({
  snap,
  busy,
  onBuy,
  onPayRent,
}: {
  snap: ActiveSnapshot;
  busy: boolean;
  onBuy: (p: ActiveProperty) => void;
  onPayRent: (p: ActiveProperty) => void;
}) {
  const boards = propertiesByBoard(snap);
  const mine = myProperties(snap);
  const blocked = snap.runtime_status !== 'running';

  return (
    <section aria-label="Propiedades" className="flex flex-col gap-3 rounded-xl border border-slate-700 p-4">
      <h2 className="text-sm font-bold text-slate-200">Propiedades</h2>
      {blocked && (
        <p role="note" className="rounded-lg bg-slate-800 px-3 py-2 text-xs text-slate-300">
          {snap.runtime_status === 'paused'
            ? 'La partida está pausada; solo puedes consultar las propiedades.'
            : 'La partida ha finalizado; las propiedades no pueden cambiar.'}
        </p>
      )}

      {boards.map((b) => (
        <div key={b.board} className="flex flex-col gap-1.5">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">{b.label}</h3>
          <ul className="flex flex-col gap-1.5">
            {b.items.map((p) => {
              const status = propertyStatus(p, snap);
              return (
                <li key={p.property_ref} className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-slate-700 px-3 py-2">
                  <span className="flex-1 truncate text-sm">
                    {p.name}
                    <span className="ml-2 text-[11px] text-slate-500">{KIND_LABEL[p.kind] ?? p.kind}</span>
                  </span>
                  <span className="text-xs text-slate-400">
                    {p.is_buyable ? <>Precio {formatMoney(p.price)} · Alquiler {formatMoney(p.base_rent)}</> : 'No comprable'}
                  </span>
                  <span className="basis-full text-xs sm:basis-auto">
                    {status === 'mine' && <span className="rounded bg-indigo-600 px-2 py-0.5 font-semibold">Tuya</span>}
                    {status === 'owned' && <span className="text-amber-300">Propiedad de {ownerName(p, snap)}</span>}
                    {status === 'available' && <span className="text-emerald-400">Disponible</span>}
                    {status === 'not_buyable' && <span className="text-slate-500">—</span>}
                  </span>
                  {status === 'available' && (
                    <button
                      type="button"
                      onClick={() => onBuy(p)}
                      disabled={busy || !canBuyProperty(p, snap)}
                      className="min-h-[36px] rounded-lg bg-emerald-600 px-3 text-xs font-semibold disabled:opacity-40"
                    >
                      Comprar
                    </button>
                  )}
                  {status === 'owned' && (
                    <button
                      type="button"
                      onClick={() => onPayRent(p)}
                      disabled={busy || !canPayRent(p, snap)}
                      className="min-h-[36px] rounded-lg border border-amber-600 px-3 text-xs font-semibold text-amber-200 disabled:opacity-40"
                    >
                      Pagar alquiler
                    </button>
                  )}
                </li>
              );
            })}
          </ul>
        </div>
      ))}

      <div className="mt-1 flex flex-col gap-1 border-t border-slate-700 pt-3">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">Mis propiedades</h3>
        {mine.length === 0 ? (
          <p className="text-xs text-slate-500">Todavía no tienes propiedades.</p>
        ) : (
          <ul className="flex flex-col gap-0.5">
            {mine.map((p) => (
              <li key={p.property_ref} className="flex justify-between text-sm">
                <span className="truncate">{p.name}</span>
                <span className="text-xs text-slate-400">Alquiler {formatMoney(p.base_rent)}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
