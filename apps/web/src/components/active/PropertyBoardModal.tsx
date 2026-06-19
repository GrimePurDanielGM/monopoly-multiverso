import { useEffect, useRef, useState } from 'react';
import type { ActiveProperty, ActiveSnapshot, PropertyAuction } from '../../lib/activeSnapshot';
import {
  formatMoney, propertyStatus, canRequestPurchase, canPayRent, ownerName,
  propertyGroupsByBoard, purchaseBlockReason,
} from '../../lib/activeSelectors';
import { AuctionsPanel } from './AuctionsPanel';
import { PropertyCardModal } from './PropertyCardModal';

const KIND_LABEL: Record<string, string> = {
  street: 'Calle', station: 'Estación', transport: 'Transporte', utility: 'Servicio', special: 'Especial',
};

/** Tarjeta compacta de una propiedad: franja de color del grupo, precio, alquiler, estado y acción. */
function PropertyCard({
  p, snap, busy, blocked, onRequestPurchase, onPayRent, onViewCard,
}: {
  p: ActiveProperty;
  snap: ActiveSnapshot;
  busy: boolean;
  blocked: boolean;
  onRequestPurchase: (p: ActiveProperty) => void;
  onPayRent: (p: ActiveProperty) => void;
  onViewCard: (p: ActiveProperty) => void;
}) {
  const status = propertyStatus(p, snap);
  return (
    <li className="flex flex-col gap-1.5 rounded-lg border border-slate-700 bg-slate-900/40 p-3">
      <div className="flex items-start justify-between gap-2">
        <span className="text-sm font-semibold leading-tight">{p.name}</span>
        {status === 'mine' && <span className="shrink-0 rounded bg-indigo-600 px-1.5 py-0.5 text-[10px] font-bold uppercase">Tuya</span>}
        {status === 'in_auction' && <span className="shrink-0 rounded bg-fuchsia-700 px-1.5 py-0.5 text-[10px] font-bold uppercase">En subasta</span>}
        {status === 'owned' && <span className="shrink-0 rounded bg-amber-700/80 px-1.5 py-0.5 text-[10px] font-bold uppercase">Ocupada</span>}
        {status === 'available' && <span className="shrink-0 rounded bg-emerald-700 px-1.5 py-0.5 text-[10px] font-bold uppercase">Libre</span>}
        {status === 'not_buyable' && <span className="shrink-0 rounded bg-slate-700 px-1.5 py-0.5 text-[10px] font-bold uppercase">No comprable</span>}
      </div>
      <p className="text-[11px] text-slate-400">{KIND_LABEL[p.kind] ?? p.kind}</p>
      <p className="text-xs text-slate-300">
        {p.is_buyable
          ? <>Precio <span className="font-semibold text-slate-100">{formatMoney(p.price)}</span>{p.base_rent > 0 ? <> · Alquiler {formatMoney(p.base_rent)}</> : <> · Alquiler por dados</>}</>
          : 'No comprable'}
      </p>
      {status === 'owned' && <p className="text-[11px] text-amber-300">Propiedad de {ownerName(p, snap)}</p>}
      <button
        type="button"
        onClick={() => onViewCard(p)}
        className="mt-0.5 min-h-[36px] rounded-lg border border-slate-600 px-3 text-[11px] font-semibold text-slate-300"
      >
        Ver tarjeta
      </button>
      {status === 'available' && !blocked && (
        canRequestPurchase(p, snap) ? (
          <button
            type="button"
            onClick={() => onRequestPurchase(p)}
            disabled={busy}
            className="mt-0.5 min-h-[40px] rounded-lg bg-emerald-600 px-3 text-xs font-semibold disabled:opacity-40"
          >
            Solicitar compra
          </button>
        ) : (
          <p className="mt-0.5 text-[11px] text-slate-400">{purchaseBlockReason(p, snap)}</p>
        )
      )}
      {status === 'owned' && !blocked && p.owner_ref !== snap.me.public_ref && p.base_rent > 0 && (
        <button
          type="button"
          onClick={() => onPayRent(p)}
          disabled={busy || !canPayRent(p, snap)}
          className="mt-0.5 min-h-[40px] rounded-lg border border-amber-600 px-3 text-xs font-semibold text-amber-200 disabled:opacity-40"
        >
          Pagar alquiler
        </button>
      )}
    </li>
  );
}

/** Vista dedicada "Tablero de propiedades": modal a pantalla completa con scroll propio.
 *  Agrupa por tablero (Clásico / Regreso al futuro) y, dentro, por grupo de color/tipo (acordeones,
 *  sin depender de hover). Aquí viven TODAS las acciones de propiedades: solicitar compra, pagar
 *  alquiler y las subastas. Las acciones se bloquean en pausa/finalización y para espectadores. */
export function PropertyBoardModal({
  snap, isHost, busy, onClose, onRequestPurchase, onPayRent, onBid, onCloseAuction, onCancelAuction,
}: {
  snap: ActiveSnapshot;
  isHost: boolean;
  busy: boolean;
  onClose: () => void;
  onRequestPurchase: (p: ActiveProperty) => void;
  onPayRent: (p: ActiveProperty) => void;
  onBid: (a: PropertyAuction, amount: number) => void;
  onCloseAuction: (a: PropertyAuction) => void;
  onCancelAuction: (a: PropertyAuction) => void;
}) {
  const boards = propertyGroupsByBoard(snap);
  const blocked = snap.runtime_status !== 'running' || snap.me.is_spectator;
  const closeRef = useRef<HTMLButtonElement>(null);
  const [card, setCard] = useState<ActiveProperty | null>(null);

  useEffect(() => {
    closeRef.current?.focus();
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-40 flex flex-col bg-slate-950/95 sm:items-center sm:justify-center sm:bg-slate-950/80 sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Tablero de propiedades"
    >
      <div className="flex h-[100dvh] max-h-[100dvh] w-full flex-col overflow-hidden bg-slate-950 sm:h-auto sm:max-h-[90vh] sm:max-w-3xl sm:rounded-2xl sm:border sm:border-slate-700">
        {/* Cabecera respeta el safe area superior (Dynamic Island / notch / barra de estado). */}
        <header className="flex shrink-0 items-center justify-between border-b border-slate-700 px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
          <h2 className="text-base font-bold">Tablero de propiedades</h2>
          <button
            ref={closeRef}
            type="button"
            onClick={onClose}
            className="min-h-[40px] rounded-lg border border-slate-600 px-3 text-sm font-semibold"
          >
            Cerrar
          </button>
        </header>

        <div className="flex-1 overflow-y-auto px-4 py-3">
          {blocked && (
            <p role="note" className="mb-3 rounded-lg bg-slate-800 px-3 py-2 text-xs text-slate-300">
              {snap.me.is_spectator
                ? 'Estás en bancarrota: solo puedes consultar las propiedades.'
                : snap.runtime_status === 'paused'
                  ? 'La partida está pausada; las acciones están deshabilitadas.'
                  : 'La partida ha finalizado; las propiedades no pueden cambiar.'}
            </p>
          )}

          <div className="mb-3">
            <AuctionsPanel
              snap={snap}
              isHost={isHost}
              busy={busy}
              onBid={onBid}
              onClose={onCloseAuction}
              onCancel={onCancelAuction}
            />
          </div>

          {boards.map((b) => (
            <section key={b.board} aria-label={b.label} className="mb-4">
              <h3 className="mb-2 text-sm font-bold text-slate-100">{b.label}</h3>
              <div className="flex flex-col gap-2">
                {b.groups.map((g) => (
                  <details key={g.group} open className="rounded-lg border border-slate-800">
                    <summary className="flex cursor-pointer items-center gap-2 px-3 py-2 text-xs font-semibold text-slate-200">
                      <span aria-hidden className="inline-block h-3 w-3 shrink-0 rounded-sm" style={{ backgroundColor: g.swatch }} />
                      {g.label}
                      <span className="ml-auto text-[11px] font-normal text-slate-500">{g.items.length}</span>
                    </summary>
                    <ul className="grid grid-cols-1 gap-2 px-3 pb-3 sm:grid-cols-2">
                      {g.items.map((p) => (
                        <PropertyCard
                          key={p.property_ref}
                          p={p}
                          snap={snap}
                          busy={busy}
                          blocked={blocked}
                          onRequestPurchase={onRequestPurchase}
                          onPayRent={onPayRent}
                          onViewCard={setCard}
                        />
                      ))}
                    </ul>
                  </details>
                ))}
              </div>
            </section>
          ))}
        </div>

        <footer className="shrink-0 border-t border-slate-700 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:hidden">
          <button
            type="button"
            onClick={onClose}
            className="min-h-[44px] w-full rounded-xl bg-slate-800 text-sm font-semibold"
          >
            Volver a la partida
          </button>
        </footer>
      </div>

      {card && <PropertyCardModal property={card} snap={snap} onClose={() => setCard(null)} />}
    </div>
  );
}
