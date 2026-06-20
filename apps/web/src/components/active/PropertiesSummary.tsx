import { useState } from 'react';
import type { ActiveProperty, ActiveSnapshot } from '../../lib/activeSnapshot';
import { formatMoney, myProperties, propertiesOf } from '../../lib/activeSelectors';
import { PropertyCardModal, type BuildingActions } from './PropertyCardModal';

/** Resumen LIGERO de propiedades en la pantalla principal: mis propiedades + recuento por jugador.
 *  No lista el catálogo completo ni incluye acciones de compra: esas viven en "Tablero de propiedades",
 *  que se abre con el botón. Mantiene la vista principal ligera y sin scroll infinito. */
export function PropertiesSummary({
  snap,
  onOpenBoard,
  buildingActions,
  busy = false,
}: {
  snap: ActiveSnapshot;
  onOpenBoard: () => void;
  buildingActions?: BuildingActions;
  busy?: boolean;
}) {
  const mine = myProperties(snap);
  const others = snap.players
    .filter((pl) => pl.public_ref !== snap.me.public_ref)
    .map((pl) => ({ player: pl, items: propertiesOf(pl.public_ref, snap) }))
    .filter((x) => x.items.length > 0);
  const [card, setCard] = useState<ActiveProperty | null>(null);

  return (
    <section aria-label="Propiedades" className="flex flex-col gap-3 rounded-xl border border-slate-700 p-4">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-sm font-bold text-slate-200">Propiedades</h2>
        <button
          type="button"
          onClick={onOpenBoard}
          className="min-h-[40px] rounded-lg bg-sky-600 px-3 text-xs font-semibold"
        >
          Ver tablero de propiedades
        </button>
      </div>

      {/* Mis propiedades */}
      <div className="flex flex-col gap-1">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">
          Mis propiedades: {mine.length}
        </h3>
        {mine.length === 0 ? (
          <p className="text-xs text-slate-500">Todavía no tienes propiedades.</p>
        ) : (
          <ul className="flex flex-col gap-0.5">
            {mine.map((p) => (
              <li key={p.property_ref}>
                <button type="button" onClick={() => setCard(p)}
                  className="flex w-full items-center justify-between gap-2 rounded-lg px-1 py-1 text-left text-sm active:bg-slate-800">
                  <span className="truncate underline decoration-slate-600 decoration-dotted underline-offset-2">{p.name}</span>
                  <span className="shrink-0 text-xs text-slate-400">
                    {p.base_rent > 0 ? <>Alquiler {formatMoney(p.base_rent)}</> : 'Servicio'}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      {/* Propiedades de los jugadores (resumen, sin acciones) */}
      {others.length > 0 && (
        <div className="flex flex-col gap-1 border-t border-slate-700 pt-3">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">
            Propiedades de los jugadores
          </h3>
          <ul className="flex flex-col gap-1">
            {others.map(({ player, items }) => (
              <li key={player.public_ref}>
                <details className="rounded-lg bg-slate-900/40">
                  <summary className="flex cursor-pointer items-center justify-between gap-2 px-3 py-2 text-sm">
                    <span className="truncate">{player.display_name}</span>
                    <span className="shrink-0 text-xs text-slate-400">{items.length} propiedades</span>
                  </summary>
                  <ul className="flex flex-col gap-0.5 px-3 pb-2 text-xs text-slate-300">
                    {items.map((p) => (
                      <li key={p.property_ref}>
                        <button type="button" onClick={() => setCard(p)}
                          className="w-full truncate text-left underline decoration-slate-600 decoration-dotted underline-offset-2 active:text-slate-100">
                          {p.name}
                        </button>
                      </li>
                    ))}
                  </ul>
                </details>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Resumen de banco (Fase 6): stock físico de casas y hoteles disponibles. */}
      {snap.building_stock && (
        <div className="grid grid-cols-2 gap-2 border-t border-slate-700 pt-3 text-xs">
          <div className="rounded-lg bg-slate-800/60 px-3 py-2"><p className="text-slate-400">Casas disponibles</p><p className="text-base font-bold text-orange-300">{snap.building_stock.houses_available}</p></div>
          <div className="rounded-lg bg-slate-800/60 px-3 py-2"><p className="text-slate-400">Hoteles disponibles</p><p className="text-base font-bold text-purple-300">{snap.building_stock.hotels_available}</p></div>
        </div>
      )}

      {card && <PropertyCardModal property={card} snap={snap} busy={busy} actions={buildingActions ?? {}} navScope="mine" onClose={() => setCard(null)} />}
    </section>
  );
}
