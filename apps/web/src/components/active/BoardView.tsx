import { useEffect, useMemo, useRef, useState } from 'react';
import type { ActiveProperty, ActiveSnapshot, BoardKey, BoardSpace } from '../../lib/activeSnapshot';
import {
  BOARD_LABEL, spaceTypeLabel, groupSwatch, spacesOfBoard, ringSize, playersAtSpace,
  formatMoney, ownerName, canRequestPurchase,
} from '../../lib/activeSelectors';
import { boardGrid } from '../../lib/boardLayout';

const TYPE_COLOR: Record<string, string> = {
  start: '#10b981', tax: '#f43f5e', card: '#38bdf8', jail: '#64748b',
  go_to_jail: '#fb7185', parking: '#818cf8', special: '#a78bfa', property: '#334155',
};
// Paleta estable para las fichas de los jugadores (por orden de turno).
const PLAYER_COLORS = ['#10b981', '#6366f1', '#f59e0b', '#ec4899', '#06b6d4', '#ef4444', '#84cc16', '#a855f7'];

/** Vista de tablero VISUAL (cuadrado, 4 lados, 4 esquinas) usable en móvil. Muestra la posición de
 *  cada jugador POR NOMBRE, resalta mi posición y el jugador actual, y al tocar una casilla abre su
 *  detalle (nombre, tipo, precio, propietario y jugadores presentes). Permite ver ambos tableros. */
export function BoardView({
  snap, onClose, onRequestPurchase,
}: {
  snap: ActiveSnapshot;
  onClose: () => void;
  onRequestPurchase: (p: ActiveProperty) => void;
}) {
  const closeRef = useRef<HTMLButtonElement>(null);
  const [board, setBoard] = useState<BoardKey>(snap.my_position?.board_key ?? 'classic');
  const [selected, setSelected] = useState<number | null>(null);

  useEffect(() => {
    closeRef.current?.focus();
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { if (selected !== null) setSelected(null); else onClose(); } };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, selected]);

  const colorOf = useMemo(() => {
    const map: Record<string, string> = {};
    snap.players.forEach((p, i) => { map[p.public_ref] = PLAYER_COLORS[i % PLAYER_COLORS.length]!; });
    return map;
  }, [snap.players]);
  const nameOf = useMemo(
    () => Object.fromEntries(snap.players.map((p) => [p.public_ref, p.display_name] as const)),
    [snap.players],
  );
  const propByRef = useMemo(
    () => Object.fromEntries(snap.properties.map((p) => [p.property_ref, p] as const)),
    [snap.properties],
  );

  const spaceName = (b: BoardKey, idx: number): string =>
    snap.spaces.find((s) => s.board_key === b && s.space_index === idx)?.name ?? `#${idx}`;
  const guardianToll = snap.spaces.find((s) => s.guardian && s.guardian_toll != null)?.guardian_toll ?? 100;

  const spaces = spacesOfBoard(snap, board);
  const size = ringSize(snap, board);
  const grid = boardGrid(size);
  const byIndex = useMemo(() => {
    const m: Record<number, BoardSpace> = {};
    for (const s of spaces) m[s.space_index] = s;
    return m;
  }, [spaces]);
  const provisional = snap.boards.find((b) => b.board_key === board)?.provisional;

  const tileColor = (s: BoardSpace): string => {
    if (s.property_ref) { const p = propByRef[s.property_ref]; if (p) return groupSwatch(p.group_key); }
    return TYPE_COLOR[s.space_type] ?? '#334155';
  };

  const sel = selected !== null ? byIndex[selected] : undefined;
  const selProp = sel?.property_ref ? propByRef[sel.property_ref] : undefined;
  const selPlayers = sel ? playersAtSpace(snap, board, sel.space_index) : [];

  return (
    <div className="fixed inset-0 z-40 flex flex-col bg-slate-950/95 sm:items-center sm:justify-center sm:bg-slate-950/80 sm:p-4"
      role="dialog" aria-modal="true" aria-label="Tablero">
      <div className="flex h-[100dvh] max-h-[100dvh] w-full flex-col overflow-hidden bg-slate-950 sm:h-auto sm:max-h-[92vh] sm:max-w-2xl sm:rounded-2xl sm:border sm:border-slate-700">
        {/* Cabecera respeta el safe area superior (Dynamic Island / notch / barra de estado). */}
        <header className="flex shrink-0 items-center justify-between gap-2 border-b border-slate-700 px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
          <h2 className="text-base font-bold">Tablero</h2>
          <div className="flex gap-1" role="tablist" aria-label="Elegir tablero">
            {(['classic', 'back_to_the_future'] as BoardKey[]).map((b) => (
              <button key={b} role="tab" aria-selected={board === b} type="button"
                onClick={() => { setBoard(b); setSelected(null); }}
                className={`min-h-[36px] rounded-lg px-2 text-xs font-semibold ${board === b ? 'bg-sky-600' : 'bg-slate-800 text-slate-300'}`}>
                {BOARD_LABEL[b]}
              </button>
            ))}
          </div>
          <button ref={closeRef} type="button" onClick={onClose} className="min-h-[36px] rounded-lg border border-slate-600 px-3 text-sm font-semibold">
            Cerrar
          </button>
        </header>

        <div className="flex-1 overflow-auto p-3">
          {provisional && (
            <p role="note" className="mb-2 rounded-lg bg-amber-950/40 px-3 py-1.5 text-[11px] text-amber-200">
              Orden de {BOARD_LABEL[board]} provisional (pendiente de confirmar el tablero físico).
            </p>
          )}
          {/* Tablero cuadrado: rejilla size×size; las casillas ocupan el perímetro. */}
          <div className="mx-auto grid aspect-square w-full max-w-[560px] gap-0.5"
            style={{ gridTemplateColumns: `repeat(${grid.size}, minmax(0, 1fr))`, gridTemplateRows: `repeat(${grid.size}, minmax(0, 1fr))` }}>
            {grid.cells.map((cell) => {
              const s = byIndex[cell.index];
              if (!s) return null;
              const here = playersAtSpace(snap, board, cell.index);
              const isMine = snap.my_position?.board_key === board && snap.my_position?.space_index === cell.index;
              const prop = s.property_ref ? propByRef[s.property_ref] : undefined;
              return (
                <button key={s.space_ref} type="button"
                  onClick={() => setSelected(cell.index)}
                  aria-label={`Casilla ${cell.index}: ${s.name}${s.guardian ? ' (guardián)' : ''}`}
                  style={{ gridRow: cell.row, gridColumn: cell.col }}
                  className={`relative flex min-h-0 flex-col overflow-hidden rounded-[3px] border text-left ${
                    isMine ? 'border-emerald-400 ring-1 ring-emerald-400'
                      : s.guardian ? 'border-amber-400 ring-1 ring-amber-400' : 'border-slate-700'} bg-slate-900`}>
                  <span className="h-1.5 w-full shrink-0" style={{ backgroundColor: tileColor(s) }} />
                  {s.guardian && <span aria-hidden className="absolute right-0 top-1 text-[7px] sm:text-[9px]">🛡️</span>}
                  <span className="flex-1 px-0.5 pt-0.5 text-[6px] leading-[1.05] text-slate-200 line-clamp-3 sm:text-[8px]">{s.name}</span>
                  {prop && <span className="px-0.5 text-[6px] text-slate-400 sm:text-[8px]">{prop.price}</span>}
                  {here.length > 0 && (
                    <span className="flex flex-wrap gap-px px-0.5 pb-0.5">
                      {here.map((ref) => (
                        <span key={ref} title={nameOf[ref]} aria-hidden
                          className="inline-block h-2 w-2 rounded-full ring-1 ring-slate-950"
                          style={{ backgroundColor: colorOf[ref] ?? '#94a3b8' }} />
                      ))}
                    </span>
                  )}
                </button>
              );
            })}
            {/* Centro del tablero */}
            <div className="flex flex-col items-center justify-center rounded-lg"
              style={{ gridRow: `2 / ${grid.size}`, gridColumn: `2 / ${grid.size}` }}>
              <span className="text-center text-xs font-black uppercase tracking-wider text-slate-500">Monopoly</span>
              <span className="text-center text-[10px] text-slate-600">{BOARD_LABEL[board]}</span>
            </div>
          </div>

          {/* Leyenda de jugadores (por nombre) */}
          <ul className="mt-3 flex flex-wrap gap-2">
            {snap.players.map((p) => (
              <li key={p.public_ref} className="flex items-center gap-1.5 text-xs">
                <span className="inline-block h-2.5 w-2.5 rounded-full" style={{ backgroundColor: colorOf[p.public_ref] }} aria-hidden />
                <span className={p.is_current ? 'font-semibold text-emerald-300' : 'text-slate-300'}>{p.display_name}</span>
                {p.public_ref === snap.me.public_ref && <span className="text-[10px] text-indigo-300">(tú)</span>}
              </li>
            ))}
          </ul>

          {/* Montaje EN CRUZ: la cárcel de un tablero coincide con el Parking del otro; guardián en cada cárcel. */}
          {snap.board_links.length > 0 && (
            <p role="note" className="mt-3 rounded-lg bg-amber-950/40 px-3 py-1.5 text-[11px] text-amber-200">
              🛡️ Los dos tableros se montan en cruz: la cárcel/solo-visitas de un tablero coincide con el Parking
              del otro. Un guardián en cada cárcel custodia el paso (peaje {guardianToll}) hacia el otro tablero o
              hacia su propia calle; pasar por la entrada libre es gratis (cruce automático en fase posterior).
            </p>
          )}
        </div>

        {/* Detalle de casilla (panel inferior) */}
        {sel && (
          <div role="dialog" aria-label={`Detalle de ${sel.name}`} className="shrink-0 border-t border-slate-700 bg-slate-900 px-4 py-3">
            <div className="flex items-start justify-between gap-2">
              <div>
                <p className="text-sm font-bold">{sel.name} <span className="text-[11px] font-normal text-slate-500">#{sel.space_index} · {spaceTypeLabel(sel.space_type)}</span></p>
                {selProp && (
                  <p className="text-xs text-slate-300">
                    {selProp.is_buyable ? <>Precio {formatMoney(selProp.price)}{selProp.base_rent > 0 ? <> · Alquiler {formatMoney(selProp.base_rent)}</> : <> · Alquiler por dados</>}</> : 'No comprable'}
                    {selProp.owner_ref && <> · Propiedad de {ownerName(selProp, snap)}</>}
                  </p>
                )}
                {!selProp && sel.space_type !== 'start' && !sel.guardian && (
                  <p className="text-xs text-slate-400">Esta casilla se resolverá en una fase posterior.</p>
                )}
                {sel.guardian && sel.links_to_board && (
                  <p className="text-xs text-amber-300">
                    🛡️ Guardián (peaje {sel.guardian_toll ?? 100}): custodia el paso entre{' '}
                    <span className="font-semibold">{spaceName(sel.board_key, sel.space_index + 1)}</span> (este tablero) y{' '}
                    <span className="font-semibold">{spaceName(sel.links_to_board, sel.links_to_index ?? -1)}</span> ({BOARD_LABEL[sel.links_to_board]}).
                    Pasar por la entrada libre es gratis; por la custodiada, pagas el peaje (cruce en fase posterior).
                  </p>
                )}
                <p className="mt-1 text-xs text-slate-400">
                  Jugadores aquí: {selPlayers.length ? selPlayers.map((r) => nameOf[r]).join(', ') : '—'}
                </p>
              </div>
              <button type="button" onClick={() => setSelected(null)} className="min-h-[36px] rounded-lg border border-slate-600 px-2 text-xs">Cerrar</button>
            </div>
            {selProp && canRequestPurchase(selProp, snap) && (
              <button type="button" onClick={() => { onRequestPurchase(selProp); setSelected(null); }}
                className="mt-2 min-h-[40px] w-full rounded-lg bg-emerald-600 px-3 text-xs font-semibold">
                Solicitar compra
              </button>
            )}
          </div>
        )}

        <footer className="shrink-0 border-t border-slate-700 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:hidden">
          <button type="button" onClick={onClose} className="min-h-[44px] w-full rounded-xl bg-slate-800 text-sm font-semibold">
            Volver a la partida
          </button>
        </footer>
      </div>
    </div>
  );
}
