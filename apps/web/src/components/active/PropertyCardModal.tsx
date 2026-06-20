import { useMemo, useRef, useState } from 'react';
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

/** Contexto de navegación entre propiedades desde la ficha (item 5). */
export type CardNavScope = 'mine' | 'all' | `board:${string}`;

const KIND_LABEL: Record<string, string> = {
  street: 'Calle', station: 'Estación', transport: 'Transporte', utility: 'Servicio', special: 'Especial',
};
const STATUS_LABEL: Record<PropertyStatus, string> = {
  mine: 'Tuya', available: 'Disponible', owned: 'De otro jugador', not_buyable: 'No comprable', in_auction: 'En subasta',
};
const PENDING = 'Pendiente de confirmar';
/** Tipos de propiedad con tarjeta de título (los que se pueden navegar/consultar). */
const CARD_KINDS = new Set(['street', 'station', 'transport', 'utility']);
const isStreetKind = (k: string) => k === 'street';
const isStationKind = (k: string) => k === 'station' || k === 'transport';
const isUtilityKind = (k: string) => k === 'utility';

/** Importe formateado o "Pendiente de confirmar" si el dato no existe (no se inventa nada). */
function money(v: number | null | undefined): string {
  return v == null ? PENDING : formatMoney(v);
}

function Row({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  const pending = value === PENDING;
  return (
    <div className="flex items-start justify-between gap-3 px-3 py-2">
      <span className="min-w-0 break-words text-xs text-slate-400">{label}</span>
      <span className={`shrink-0 text-sm tabular-nums ${pending ? 'text-slate-500 italic' : strong ? 'font-bold text-slate-100' : 'text-slate-200'}`}>{value}</span>
    </div>
  );
}

function Cell({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0 rounded-lg bg-slate-800/60 px-3 py-2">
      <p className="text-slate-400">{label}</p>
      <p className="break-words font-semibold text-slate-100">{value}</p>
    </div>
  );
}

/** Ficha de la TARJETA de título: estado, alquileres y acciones, adaptada al tipo (calle/estación/servicio).
 *  Construir/vender pasan por solicitud al anfitrión; hipotecar/deshipotecar son directas. Lee siempre del
 *  snapshot (refresco inmediato) y permite navegar entre propiedades del contexto sin cerrar (item 5). */
export function PropertyCardModal({ property, snap, onClose, busy = false, actions = {}, navScope }: {
  property: ActiveProperty;
  snap: ActiveSnapshot;
  onClose: () => void;
  busy?: boolean;
  actions?: BuildingActions;
  navScope?: CardNavScope;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  useDialogA11y(true, ref, { onEscape: onClose, initialFocusRef: closeRef });

  // Lista de hermanas para navegar (orden tablero + sort_order); null si no hay navegación.
  const siblings = useMemo(() => {
    if (!navScope) return null;
    let list = snap.properties.filter((q) => CARD_KINDS.has(q.kind));
    if (navScope === 'mine') list = list.filter((q) => q.owner_ref === snap.me.public_ref);
    else if (navScope.startsWith('board:')) { const b = navScope.slice(6); list = list.filter((q) => q.board_key === b); }
    return list.slice().sort((a, b) => (a.board_key === b.board_key ? a.sort_order - b.sort_order : a.board_key.localeCompare(b.board_key)));
  }, [navScope, snap.properties, snap.me.public_ref]);

  // Propiedad mostrada: estado interno (navegación) resuelto SIEMPRE contra el snapshot fresco.
  const [currentRef, setCurrentRef] = useState(property.property_ref);
  const order = siblings && siblings.length > 0 ? siblings : [property];
  const idx = Math.max(0, order.findIndex((q) => q.property_ref === currentRef));
  const activeRef = order[idx]?.property_ref ?? currentRef;
  const p = snap.properties.find((x) => x.property_ref === activeRef) ?? property;
  const canNav = order.length > 1;
  const go = (delta: number) => {
    if (!canNav) return;
    const next = (idx + delta + order.length) % order.length;
    setCurrentRef(order[next]!.property_ref);
  };
  // Deslizamiento horizontal en móvil.
  const touchX = useRef<number | null>(null);
  const onTouchStart = (e: React.TouchEvent) => { touchX.current = e.changedTouches[0]?.clientX ?? null; };
  const onTouchEnd = (e: React.TouchEvent) => {
    if (touchX.current == null) return;
    const dx = (e.changedTouches[0]?.clientX ?? touchX.current) - touchX.current;
    if (Math.abs(dx) > 50) go(dx < 0 ? 1 : -1);
    touchX.current = null;
  };

  const pendingAction = (a: 'build_house' | 'build_hotel' | 'sell_house' | 'sell_hotel') =>
    snap.my_building_requests.some((m) => m.property_ref === p.property_ref && m.action === a);
  const status = propertyStatus(p, snap);
  const statusText = p.mortgaged
    ? 'Hipotecada'
    : status === 'owned' ? `${STATUS_LABEL.owned} (${ownerName(p, snap)})` : STATUS_LABEL[status];
  const mine = isMine(p, snap);
  const buildLabel = p.has_hotel ? 'Hotel' : (p.houses ?? 0) > 0 ? `${p.houses} ${p.houses === 1 ? 'casa' : 'casas'}` : 'Sin construir';
  const reason = buildBlockReason(p, snap);
  const showMortgage = p.mortgage_value != null; // hipoteca solo donde aplica (calles; otras si tuvieran valor)

  const rentRows: Array<[string, number | null | undefined]> = [
    ['Alquiler base', p.base_rent],
    ['Con 1 casa', p.rent_1],
    ['Con 2 casas', p.rent_2],
    ['Con 3 casas', p.rent_3],
    ['Con 4 casas', p.rent_4],
    ['Con hotel', p.rent_hotel],
  ];

  // Cada apartado se desliza con el dedo si su contenido no cabe (sin recortes ni overflow horizontal en iPhone).
  const scrollSection = 'max-h-[40vh] overflow-y-auto overflow-x-hidden overscroll-contain';
  const scrollStyle = { WebkitOverflowScrolling: 'touch' as const };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 sm:items-center sm:p-4" onClick={onClose}>
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-label={`Ficha de ${p.name}`}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
        onTouchStart={onTouchStart}
        onTouchEnd={onTouchEnd}
        className="flex max-h-[92dvh] w-full max-w-md flex-col overflow-hidden rounded-t-2xl border border-slate-700 bg-slate-900 shadow-xl sm:rounded-2xl"
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

        <div className="flex flex-col gap-3 overflow-y-auto px-4 py-3">
          <div className="grid grid-cols-2 gap-2 text-xs">
            <Cell label="Tablero" value={BOARD_LABEL[p.board_key] ?? p.board_key} />
            <Cell label="Grupo" value={groupLabel(p.group_key)} />
            <Cell label="Tipo" value={KIND_LABEL[p.kind] ?? p.kind} />
            <Cell label="Estado" value={statusText} />
            {isStreetKind(p.kind) && (
              <>
                <Cell label="Construcción" value={buildLabel} />
                <Cell label="Monopolio" value={p.monopoly ? 'Sí' : 'No'} />
              </>
            )}
          </div>

          {/* Alquiler actual que adeudaría quien cae; en hipotecada, sin alquiler. */}
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

          {/* Alquileres — solo lo que aplica al tipo. */}
          {isStreetKind(p.kind) && (
            <div className="overflow-hidden rounded-lg border border-slate-700">
              <p className="border-b border-slate-700 bg-slate-800/60 px-3 py-2 text-xs font-semibold text-slate-300">Alquileres</p>
              <div className={`divide-y divide-slate-800 ${scrollSection}`} style={scrollStyle}>
                {rentRows.map(([label, value]) => <Row key={label} label={label} value={money(value)} />)}
              </div>
            </div>
          )}
          {isStationKind(p.kind) && (
            <div className="overflow-hidden rounded-lg border border-slate-700">
              <p className="border-b border-slate-700 bg-slate-800/60 px-3 py-2 text-xs font-semibold text-slate-300">Escala de estaciones/transportes</p>
              <div className={scrollSection} style={scrollStyle}>
                <ul className="grid grid-cols-2 gap-x-4 gap-y-1 px-3 py-2 text-sm tabular-nums text-slate-200">
                  <li>1 → 25 €</li><li>2 → 50 €</li><li>3 → 100 €</li><li>4 → 200 €</li>
                  <li>5 → 300 €</li><li>6 → 400 €</li><li>7 → 500 €</li><li>8 → 600 €</li>
                </ul>
                <p className="px-3 pb-2 text-[11px] text-slate-400">Las estaciones y transportes se combinan entre ambos tableros.</p>
              </div>
            </div>
          )}
          {isUtilityKind(p.kind) && (
            <div className="overflow-hidden rounded-lg border border-slate-700">
              <p className="border-b border-slate-700 bg-slate-800/60 px-3 py-2 text-xs font-semibold text-slate-300">Escala de servicios</p>
              <div className={scrollSection} style={scrollStyle}>
                <ul className="grid grid-cols-2 gap-x-4 gap-y-1 px-3 py-2 text-sm tabular-nums text-slate-200">
                  <li>1 servicio: tirada ×4</li><li>2 servicios: tirada ×10</li>
                  <li>3 servicios: tirada ×14</li><li>4 servicios: tirada ×20</li>
                </ul>
                <p className="px-3 pb-2 text-[11px] text-slate-400">Los servicios se combinan entre ambos tableros.</p>
              </div>
            </div>
          )}

          {/* Construcción — solo calles. */}
          {isStreetKind(p.kind) && (
            <div className="overflow-hidden rounded-lg border border-slate-700">
              <p className="border-b border-slate-700 bg-slate-800/60 px-3 py-2 text-xs font-semibold text-slate-300">Construcción</p>
              <div className={`divide-y divide-slate-800 ${scrollSection}`} style={scrollStyle}>
                <Row label="Coste por casa" value={money(p.house_cost)} />
                <Row label="Coste del hotel" value={money(p.hotel_cost)} />
              </div>
            </div>
          )}

          {/* Hipoteca — donde aplica. */}
          {showMortgage && (
            <div className="overflow-hidden rounded-lg border border-slate-700">
              <p className="border-b border-slate-700 bg-slate-800/60 px-3 py-2 text-xs font-semibold text-slate-300">Hipoteca</p>
              <div className={`divide-y divide-slate-800 ${scrollSection}`} style={scrollStyle}>
                <Row label="Valor de hipoteca" value={money(p.mortgage_value)} />
                <Row label="Deshipotecar (hipoteca + 10%)" value={money(p.unmortgage_cost)} />
              </div>
            </div>
          )}

          {/* Acciones del propietario. Construir/vender → solicitud; hipoteca/deshipoteca → directa. Ancho completo. */}
          {mine && (
            <div className="flex flex-col gap-2 border-t border-slate-700 pt-3">
              <p className="text-xs font-semibold text-slate-300">Acciones</p>
              {isStreetKind(p.kind) && reason && <p className="text-[11px] text-amber-300/90">{reason}</p>}
              <div className={`flex flex-col gap-2 ${scrollSection}`} style={scrollStyle}>
              {isStreetKind(p.kind) && ([
                ['build_house', 'Solicitar construir casa', canBuildHouse(p, snap), actions.onBuildHouse, 'bg-orange-600', money(p.house_cost)],
                ['build_hotel', 'Solicitar construir hotel', canBuildHotel(p, snap), actions.onBuildHotel, 'bg-purple-600', money(p.hotel_cost)],
                ['sell_house', 'Solicitar vender casa', canSellHouse(p, snap), actions.onSellHouse, 'border border-slate-600', null],
                ['sell_hotel', 'Solicitar vender hotel', canSellHotel(p, snap), actions.onSellHotel, 'border border-slate-600', null],
              ] as const).map(([action, label, can, cb, cls, amount]) =>
                pendingAction(action) ? (
                  <p key={action} role="note" className="rounded-lg bg-slate-800 px-3 py-2 text-[11px] text-slate-300">
                    {label.replace('Solicitar ', '')}: solicitud pendiente de aprobación.
                  </p>
                ) : can ? (
                  <button key={action} type="button" disabled={busy} onClick={() => cb?.(p)}
                    className={`min-h-[44px] w-full rounded-lg px-3 text-sm font-semibold disabled:opacity-40 ${cls}`}>
                    {label}{amount ? ` (${amount})` : ''}
                  </button>
                ) : null,
              )}
              {canMortgage(p, snap) && (
                <button type="button" disabled={busy} onClick={() => actions.onMortgage?.(p)}
                  className="min-h-[44px] w-full rounded-lg border border-amber-700 px-3 text-sm font-semibold text-amber-200 disabled:opacity-40">
                  Hipotecar ({money(p.mortgage_value)})
                </button>
              )}
              {canUnmortgage(p, snap) && (
                <button type="button" disabled={busy} onClick={() => actions.onUnmortgage?.(p)}
                  className="min-h-[44px] w-full rounded-lg border border-emerald-700 px-3 text-sm font-semibold text-emerald-200 disabled:opacity-40">
                  Deshipotecar ({money(p.unmortgage_cost)})
                </button>
              )}
              </div>
            </div>
          )}
        </div>

        {/* Navegación entre propiedades del contexto (no se cierra la ficha). */}
        {canNav ? (
          <div className="flex items-center justify-between gap-2 border-t border-slate-700 px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
            <button type="button" onClick={() => go(-1)} aria-label="Propiedad anterior"
              className="min-h-[44px] flex-1 rounded-lg border border-slate-600 px-3 text-sm font-semibold">← Anterior</button>
            <span className="shrink-0 text-[11px] tabular-nums text-slate-500">{idx + 1}/{order.length}</span>
            <button type="button" onClick={() => go(1)} aria-label="Propiedad siguiente"
              className="min-h-[44px] flex-1 rounded-lg border border-slate-600 px-3 text-sm font-semibold">Siguiente →</button>
          </div>
        ) : (
          <div className="pb-[max(0.25rem,env(safe-area-inset-bottom))]" />
        )}
      </div>
    </div>
  );
}
