import { useRef } from 'react';
import type { ActiveProperty, ActiveSnapshot } from '../../lib/activeSnapshot';
import {
  formatMoney, propertyStatus, ownerName, groupLabel, groupSwatch, BOARD_LABEL, type PropertyStatus,
} from '../../lib/activeSelectors';
import { useDialogA11y } from '../../hooks/useDialogA11y';

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
export function PropertyCardModal({ property: p, snap, onClose }: {
  property: ActiveProperty;
  snap: ActiveSnapshot;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  useDialogA11y(true, ref, { onEscape: onClose, initialFocusRef: closeRef });
  const status = propertyStatus(p, snap);
  const statusText = status === 'owned' ? `${STATUS_LABEL.owned} (${ownerName(p, snap)})` : STATUS_LABEL[status];

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
          </div>

          <div className="rounded-lg border border-slate-700">
            <Row label="Precio de compra" value={p.is_buyable ? money(p.price) : 'No comprable'} strong />
          </div>

          <div className="overflow-hidden rounded-lg border border-slate-700">
            <p className="border-b border-slate-700 bg-slate-800/60 px-3 py-1.5 text-xs font-semibold text-slate-300">Alquileres</p>
            <div className="divide-y divide-slate-800">
              {rentRows.map(([label, value]) => <Row key={label} label={label} value={money(value)} />)}
            </div>
            {p.kind === 'utility' && <p className="px-3 py-1.5 text-[11px] text-slate-500">El alquiler de los servicios se cobra por los dados (fase posterior).</p>}
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

          <p className="text-[11px] text-slate-500">
            Construir casas/hoteles e hipotecar llegarán en una fase posterior; esta ficha es solo de consulta.
          </p>
        </div>
      </div>
    </div>
  );
}
