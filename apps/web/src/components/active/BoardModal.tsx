import { useEffect, useMemo, useRef, useState } from 'react';
import type { ActiveSnapshot, BoardKey } from '../../lib/activeSnapshot';
import {
  formatMoney, BOARD_LABEL, spaceTypeLabel, spacesByBoard, playersAtSpace, ownerName,
  ringSize, isValidReason,
} from '../../lib/activeSelectors';

/** Vista dedicada "Ver tablero": el recorrido (anillo) de cada tablero como lista de casillas con
 *  nombre, tipo, precio/propietario y las fichas de los jugadores presentes (resaltando mi posición y
 *  el jugador actual). El anfitrión puede corregir la posición de un jugador (motivo obligatorio).
 *  Usable en móvil (scroll propio, acordeones, sin depender de hover). */
export function BoardModal({
  snap, icons, busy, onClose, onSetPosition,
}: {
  snap: ActiveSnapshot;
  icons: Record<string, string>;
  busy: boolean;
  onClose: () => void;
  onSetPosition: (playerRef: string, board: BoardKey, index: number, reason: string) => void;
}) {
  const boards = spacesByBoard(snap);
  const closeRef = useRef<HTMLButtonElement>(null);
  const playerByRef = useMemo(
    () => Object.fromEntries(snap.players.map((p) => [p.public_ref, p])),
    [snap.players],
  );

  useEffect(() => {
    closeRef.current?.focus();
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  // Estado del formulario de corrección del anfitrión.
  const [fixRef, setFixRef] = useState(snap.players[0]?.public_ref ?? '');
  const [fixBoard, setFixBoard] = useState<BoardKey>(snap.my_position?.board_key ?? 'classic');
  const [fixIndex, setFixIndex] = useState(0);
  const [fixReason, setFixReason] = useState('');
  const maxIndex = ringSize(snap, fixBoard) - 1;
  const canFix = snap.me.is_host && snap.runtime_status === 'running';
  const fixValid = fixRef !== '' && fixIndex >= 0 && fixIndex <= maxIndex && isValidReason(fixReason);

  return (
    <div
      className="fixed inset-0 z-40 flex flex-col bg-slate-950/95 sm:items-center sm:justify-center sm:bg-slate-950/80 sm:p-4"
      role="dialog" aria-modal="true" aria-label="Tablero"
    >
      <div className="flex h-full w-full flex-col overflow-hidden bg-slate-950 sm:h-auto sm:max-h-[90vh] sm:max-w-3xl sm:rounded-2xl sm:border sm:border-slate-700">
        <header className="flex shrink-0 items-center justify-between border-b border-slate-700 px-4 py-3">
          <h2 className="text-base font-bold">Tablero</h2>
          <button ref={closeRef} type="button" onClick={onClose} className="min-h-[40px] rounded-lg border border-slate-600 px-3 text-sm font-semibold">
            Cerrar
          </button>
        </header>

        <div className="flex-1 overflow-y-auto px-4 py-3">
          {/* Corrección de posición (anfitrión) */}
          {canFix && (
            <details className="mb-3 rounded-lg border border-slate-800">
              <summary className="cursor-pointer px-3 py-2 text-xs font-semibold text-slate-200">Corregir posición (anfitrión)</summary>
              <div className="flex flex-col gap-2 px-3 pb-3">
                <label className="flex flex-col text-[11px] text-slate-400">Jugador
                  <select aria-label="Jugador" value={fixRef} onChange={(e) => setFixRef(e.target.value)} className="mt-0.5 rounded-lg border border-slate-600 bg-slate-900 px-2 py-1.5 text-sm text-slate-100">
                    {snap.players.map((p) => <option key={p.public_ref} value={p.public_ref}>{p.display_name}</option>)}
                  </select>
                </label>
                <div className="flex gap-2">
                  <label className="flex flex-1 flex-col text-[11px] text-slate-400">Tablero
                    <select aria-label="Tablero destino" value={fixBoard} onChange={(e) => { setFixBoard(e.target.value as BoardKey); setFixIndex(0); }} className="mt-0.5 rounded-lg border border-slate-600 bg-slate-900 px-2 py-1.5 text-sm text-slate-100">
                      <option value="classic">{BOARD_LABEL.classic}</option>
                      <option value="back_to_the_future">{BOARD_LABEL.back_to_the_future}</option>
                    </select>
                  </label>
                  <label className="flex w-24 flex-col text-[11px] text-slate-400">Casilla (0–{maxIndex})
                    <input type="number" min={0} max={maxIndex} value={fixIndex}
                      onChange={(e) => setFixIndex(Math.max(0, Math.min(maxIndex, Number(e.target.value) || 0)))}
                      className="mt-0.5 rounded-lg border border-slate-600 bg-slate-900 px-2 py-1.5 text-sm text-slate-100" />
                  </label>
                </div>
                <label className="flex flex-col text-[11px] text-slate-400">Motivo (obligatorio)
                  <input value={fixReason} onChange={(e) => setFixReason(e.target.value)} placeholder="motivo de la corrección"
                    className="mt-0.5 rounded-lg border border-slate-600 bg-slate-900 px-2 py-1.5 text-sm text-slate-100" />
                </label>
                <button type="button" disabled={busy || !fixValid}
                  onClick={() => onSetPosition(fixRef, fixBoard, fixIndex, fixReason.trim())}
                  className="min-h-[40px] rounded-lg bg-indigo-600 px-3 text-xs font-semibold disabled:opacity-40">
                  Corregir posición
                </button>
              </div>
            </details>
          )}

          {boards.map((b) => (
            <section key={b.board} aria-label={b.label} className="mb-4">
              <h3 className="mb-2 text-sm font-bold text-slate-100">{b.label}</h3>
              <ul className="flex flex-col gap-1">
                {b.items.map((s) => {
                  const here = playersAtSpace(snap, b.board, s.space_index);
                  const prop = s.property_ref ? snap.properties.find((p) => p.property_ref === s.property_ref) : undefined;
                  const isMine = snap.my_position?.board_key === b.board && snap.my_position?.space_index === s.space_index;
                  return (
                    <li key={s.space_ref}
                      className={`flex items-center gap-2 rounded-lg border px-3 py-2 ${isMine ? 'border-emerald-600 bg-emerald-950/30' : 'border-slate-800'}`}>
                      <span className="w-6 shrink-0 text-[11px] text-slate-500">{s.space_index}</span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium">
                          {s.name}
                          <span className="ml-2 text-[11px] text-slate-500">{spaceTypeLabel(s.space_type)}</span>
                        </p>
                        {prop && (
                          <p className="text-[11px] text-slate-400">
                            {prop.is_buyable ? <>Precio {formatMoney(prop.price)}</> : 'No comprable'}
                            {prop.owner_ref && <> · {ownerName(prop, snap)}</>}
                          </p>
                        )}
                      </div>
                      {here.length > 0 && (
                        <div className="flex shrink-0 flex-wrap items-center gap-1" aria-label="Jugadores aquí">
                          {here.map((ref) => {
                            const pl = playerByRef[ref];
                            const isCurrent = ref === snap.turn.current_player_ref;
                            return (
                              <span key={ref}
                                title={pl?.display_name ?? ref}
                                className={`inline-flex h-6 min-w-6 items-center justify-center rounded-full px-1 text-sm ${isCurrent ? 'bg-emerald-600' : 'bg-slate-700'}`}>
                                {(pl?.token_id && icons[pl.token_id]) || (pl?.display_name?.[0] ?? '•')}
                              </span>
                            );
                          })}
                        </div>
                      )}
                    </li>
                  );
                })}
              </ul>
            </section>
          ))}
        </div>

        <footer className="shrink-0 border-t border-slate-700 px-4 py-3 sm:hidden">
          <button type="button" onClick={onClose} className="min-h-[44px] w-full rounded-xl bg-slate-800 text-sm font-semibold">
            Volver a la partida
          </button>
        </footer>
      </div>
    </div>
  );
}
