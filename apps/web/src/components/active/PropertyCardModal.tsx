import { useRef } from 'react';
import type { ActiveProperty, ActiveSnapshot } from '../../lib/activeSnapshot';
import {
  formatMoney, propertyStatus, ownerName, groupLabel, groupSwatch, BOARD_LABEL, type PropertyStatus,
  isMine, canBuildHouse, canBuildHotel, canSellHouse, canSellHotel, canMortgage, canUnmortgage, buildBlockReason,
} from '../../lib/activeSelectors';
import { useDialogA11y } from '../../hooks/useDialogA11y';

export interface BuildingActions {
  onBuildHouse?: (p: ActiveProperty) => void;
  onBuildHotel?: (p: ActiveProperty) => void;
  onSellHouse?: (p: ActiveProperty) => void;
  onSellHotel?: (p: ActiveProperty) => void;
  onMortgage?: (p: ActiveProperty) => void;
  onUnmortgage?: (p: ActiveProperty) => void;
}

const KIND_LABEL: Record<string, string> = {
  street: 'Calle', station: 'Estación', transport: 'Transporte', utility: 'Servicio', special: 'Especial',
};
const STATUS_LABEL: Record<PropertyStatus, string> = {
  mine: 'Tuya', available: 'Disponible', owned: 'De otro jugador', not_buyable: 'No comprable', in_auction: 'En subasta',
};
const PENDING = 'Pendiente de confirmar';

/** Importe formateado o "Pendiente de confirmar" si el dato no existe (no se inventa nada). */
function money(v: number | null | undefined): string {
  return v == null ? PENDING : formatMoney(v);
}

function Row({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  const pending = value === PENDING;
  return (
    <div className="flex items-center justify-between gap-3 px-3 py-1.5">
      <span className="text-xs text-slate-400">{label}</span>
      <span className={`text-sm tabular-nums ${pending ? 'text-slate-500 italic' : strong ? 'font-bold text-slate-100' : 'text-slate-200'}`}>{value}</span>
    </div>
  );
}

/** Ficha completa de la TARJETA de título (solo consulta): precio, alquileres con casas/hotel, costes de
 *  construcción, hipoteca/deshipoteca y estado. NO incluye acciones de construir/hipotecar (fase posterior). */
export function PropertyCardModal({ property: p, snap, onClose, busy = false, actions = {} }: {
  property: ActiveProperty;
  snap: ActiveSnapshot;
  onClose: () => void;
  busy?: boolean;
  actions?: BuildingActions;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  useDialogA11y(true, ref, { onEscape: onClose, initialFocusRef: closeRef });
  const status = propertyStatus(p, snap);
  const statusText = p.mortgaged
    ? 'Hipotecada'
    : status === 'owned' ? `${STATUS_LABEL.owned} (${ownerName(p, snap)})` : STATUS_LABEL[status];
  const mine = isMine(p, snap);
  const buildLabel = p.has_hotel ? 'Hotel' : (p.houses ?? 0) > 0 ? `${p.houses} ${p.houses === 1 ? 'casa' : 'casas'}` : 'Sin construir';
  const reason = buildBlockReason(p, snap);

  const rentRows: Array<[string, number | null | undefined]> = [
    ['Alquiler base', p.base_rent],
    ['Con 1 casa', p.rent_1],
    ['Con 2 casas', p.rent_2],
    ['Con 3 casas', p.rent_3],
    ['Con 4 casas', p.rent_4],
    ['Con hotel', p.rent_hotel],
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 sm:items-center sm:p-4" onClick={onClose}>
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-label={`Ficha de ${p.name}`}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-[90dvh] w-full max-w-md flex-col overflow-hidden rounded-t-2xl border border-slate-700 bg-slate-900 shadow-xl sm:rounded-2xl"
      >
        <header className="flex items-center justify-between gap-2 border-b border-slate-700 px-4 py-3 pt-[max(0.75rem,env(safe-area-inset-top))] sm:pt-3">
          <div className="flex min-w-0 items-center gap-2">
            <span className="h-4 w-4 shrink-0 rounded-sm" style={{ backgroundColor: groupSwatch(p.group_key) }} aria-hidden />
            <h2 className="truncate text-base font-bold">{p.name}</h2>
          </div>
          <button ref={closeRef} type="button" onClick={onClose} aria-label="Cerrar"
            className="min-h-[36px] shrink-0 rounded-lg border border-slate-600 px-3 text-sm font-semibold">
            Cerrar
          </button>
        </header>

        <div className="flex flex-col gap-3 overflow-y-auto px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="rounded-lg bg-slate-800/60 px-3 py-2"><p className="text-slate-400">Tablero</p><p className="font-semibold text-slate-100">{BOARD_LABEL[p.board_key]}</p></div>
            <div className="rounded-lg bg-slate-800/60 px-3 py-2"><p className="text-slate-400">Grupo</p><p className="font-semibold text-slate-100">{groupLabel(p.group_key)}</p></div>
            <div className="rounded-lg bg-slate-800/60 px-3 py-2"><p className="text-slate-400">Tipo</p><p className="font-semibold text-slate-100">{KIND_LABEL[p.kind] ?? p.kind}</p></div>
            <div className="rounded-lg bg-slate-800/60 px-3 py-2"><p className="text-slate-400">Estado</p><p className="font-semibold text-slate-100">{statusText}</p></div>
            {p.kind === 'street' && (
              <>
                <div className="rounded-lg bg-slate-800/60 px-3 py-2"><p className="text-slate-400">Construcción</p><p className="font-semibold text-slate-100">{buildLabel}</p></div>
                <div className="rounded-lg bg-slate-800/60 px-3 py-2"><p className="text-slate-400">Monopolio</p><p className="font-semibold text-slate-100">{p.monopoly ? 'Sí' : 'No'}</p></div>
              </>
            )}
          </div>

          {/* Alquiler actual que adeudaría quien cae (calles/estaciones); en hipotecada, sin alquiler. */}
          {status === 'owned' && p.rent_due != null && (
            <div className="rounded-lg border border-amber-700/50 bg-amber-950/20 px-3 py-2 text-sm">
              {p.mortgaged
                ? <span className="text-amber-300">Propiedad hipotecada. No se debe alquiler.</span>
                : <>Alquiler actual: <span className="font-bold text-amber-200">{formatMoney(p.rent_due)}</span></>}
            </div>
          )}

          <div className="rounded-lg border border-slate-700">
            <Row label="Precio de compra" value={p.is_buyable ? money(p.price) : 'No comprable'} strong />
          </div>

          <div className="overflow-hidden rounded-lg border border-slate-700">
            <p className="border-b border-slate-700 bg-slate-800/60 px-3 py-1.5 text-xs font-semibold text-slate-300">Alquileres</p>
            <div className="divide-y divide-slate-800">
              {rentRows.map(([label, value]) => <Row key={label} label={label} value={money(value)} />)}
            </div>
            {p.kind === 'utility' && (
              <div className="px-3 py-1.5 text-[11px] text-slate-400">
                <p className="text-slate-300">El alquiler se cobra por los dados (tirada × multiplicador):</p>
                <ul className="mt-0.5 grid grid-cols-2 gap-x-3 tabular-nums">
                  <li>1 servicio: tirada ×4</li>
                  <li>2 servicios: tirada ×10</li>
                  <li>3 servicios: tirada ×14</li>
                  <li>4 servicios: tirada ×20</li>
                </ul>
                <p className="mt-1 text-slate-500">Los servicios se combinan entre ambos tableros.</p>
              </div>
            )}
            {(p.kind === 'station' || p.kind === 'transport') && (
              <div className="px-3 py-1.5 text-[11px] text-slate-400">
                <p className="text-slate-300">Alquiler acumulativo según estaciones/transportes del propietario:</p>
                <ul className="mt-0.5 grid grid-cols-2 gap-x-3 tabular-nums">
                  <li>1: 25 €</li>
                  <li>2: 50 €</li>
                  <li>3: 100 €</li>
                  <li>4: 200 €</li>
                  <li>5: 300 €</li>
                  <li>6: 400 €</li>
                  <li>7: 500 €</li>
                  <li>8: 600 €</li>
                </ul>
                <p className="mt-1 text-slate-500">Las estaciones y transportes se combinan entre ambos tableros.</p>
              </div>
            )}
          </div>

          <div className="overflow-hidden rounded-lg border border-slate-700">
            <p className="border-b border-slate-700 bg-slate-800/60 px-3 py-1.5 text-xs font-semibold text-slate-300">Construcción</p>
            <div className="divide-y divide-slate-800">
              <Row label="Coste por casa" value={money(p.house_cost)} />
              <Row label="Coste del hotel" value={money(p.hotel_cost)} />
            </div>
          </div>

          <div className="overflow-hidden rounded-lg border border-slate-700">
            <p className="border-b border-slate-700 bg-slate-800/60 px-3 py-1.5 text-xs font-semibold text-slate-300">Hipoteca</p>
            <div className="divide-y divide-slate-800">
              <Row label="Valor de hipoteca" value={money(p.mortgage_value)} />
              <Row label="Deshipotecar (hipoteca + 10%)" value={money(p.unmortgage_cost)} />
            </div>
          </div>

          {/* Acciones del propietario (Fase 6): construir/vender casas y hoteles, hipotecar/deshipotecar. */}
          {mine && (
            <div className="flex flex-col gap-2 border-t border-slate-700 pt-3">
              <p className="text-xs font-semibold text-slate-300">Acciones</p>
              {reason && <p className="text-[11px] text-amber-300/90">{reason}</p>}
              <div className="grid grid-cols-2 gap-2">
                {canBuildHouse(p, snap) && (
                  <button type="button" disabled={busy} onClick={() => actions.onBuildHouse?.(p)}
                    className="min-h-[40px] rounded-lg bg-orange-600 px-3 text-xs font-semibold disabled:opacity-40">
                    Construir casa ({money(p.house_cost)})
                  </button>
                )}
                {canBuildHotel(p, snap) && (
                  <button type="button" disabled={busy} onClick={() => actions.onBuildHotel?.(p)}
                    className="min-h-[40px] rounded-lg bg-purple-600 px-3 text-xs font-semibold disabled:opacity-40">
                    Construir hotel ({money(p.hotel_cost)})
                  </button>
                )}
                {canSellHouse(p, snap) && (
                  <button type="button" disabled={busy} onClick={() => actions.onSellHouse?.(p)}
                    className="min-h-[40px] rounded-lg border border-slate-600 px-3 text-xs font-semibold disabled:opacity-40">
                    Vender casa
                  </button>
                )}
                {canSellHotel(p, snap) && (
                  <button type="button" disabled={busy} onClick={() => actions.onSellHotel?.(p)}
                    className="min-h-[40px] rounded-lg border border-slate-600 px-3 text-xs font-semibold disabled:opacity-40">
                    Vender hotel
                  </button>
                )}
                {canMortgage(p, snap) && (
                  <button type="button" disabled={busy} onClick={() => actions.onMortgage?.(p)}
                    className="min-h-[40px] rounded-lg border border-amber-700 px-3 text-xs font-semibold text-amber-200 disabled:opacity-40">
                    Hipotecar ({money(p.mortgage_value)})
                  </button>
                )}
                {canUnmortgage(p, snap) && (
                  <button type="button" disabled={busy} onClick={() => actions.onUnmortgage?.(p)}
                    className="min-h-[40px] rounded-lg border border-emerald-700 px-3 text-xs font-semibold text-emerald-200 disabled:opacity-40">
                    Deshipotecar ({money(p.unmortgage_cost)})
                  </button>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
