import { useState } from 'react';
import type { ActiveProperty, ActiveSnapshot } from '../../lib/activeSnapshot';
import {
  formatMoney, currentPlayerName, BOARD_LABEL, spaceTypeLabel, canRoll, currentSpaceProperty,
  propertyStatus, canRequestPurchase, canPayRent, ownerName, purchaseBlockReason, junctionChoice,
} from '../../lib/activeSelectors';
import { PropertyCardModal } from './PropertyCardModal';

const DICE = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];
const face = (n: number) => DICE[n - 1] ?? '🎲';

/** Bloque "Movimiento" de la pantalla principal: turno, posición y casilla actuales, última tirada
 *  y resultado del último movimiento. El jugador actual tira dados o mueve manualmente; al caer en
 *  una propiedad ofrece, desde el contexto, solicitar compra o pagar alquiler (reutiliza los flujos).
 *  Las casillas aún no implementadas muestran un aviso de "fase posterior". */
export function MovementPanel({
  snap, busy, onRoll, onMoveManual, onOpenBoard, onRequestPurchase, onPayRent, onResolveJunction,
}: {
  snap: ActiveSnapshot;
  busy: boolean;
  onRoll: () => void;
  onMoveManual: (steps: number) => void;
  onOpenBoard: () => void;
  onRequestPurchase: (p: ActiveProperty) => void;
  onPayRent: (p: ActiveProperty) => void;
  onResolveJunction: (dir: 'own' | 'cross') => void;
}) {
  const [steps, setSteps] = useState<number | null>(null);
  const [card, setCard] = useState<ActiveProperty | null>(null);
  const choice = junctionChoice(snap);
  const mine = canRoll(snap);
  const myPos = snap.my_position;
  const cur = snap.current_space;
  const roll = snap.last_roll;
  const move = snap.last_move;
  const prop = currentSpaceProperty(snap);
  const status = prop ? propertyStatus(prop, snap) : null;
  const blockedNote = snap.me.is_spectator
    ? 'Estás en bancarrota: puedes consultar el tablero, pero no mover.'
    : snap.runtime_status === 'paused' ? 'La partida está en pausa.'
    : snap.runtime_status === 'finished' ? 'La partida ha finalizado.'
    : !snap.me.is_current ? `No es tu turno (juega ${currentPlayerName(snap)}).` : null;

  return (
    <section aria-label="Movimiento" className="flex flex-col gap-3 rounded-xl border border-slate-700 p-4">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-sm font-bold text-slate-200">Movimiento</h2>
        <button type="button" onClick={onOpenBoard} className="min-h-[40px] rounded-lg bg-sky-600 px-3 text-xs font-semibold">
          Ver tablero
        </button>
      </div>

      {/* Posición y casilla actuales del jugador local */}
      <div className="grid grid-cols-2 gap-2 text-sm">
        <div className="rounded-lg bg-slate-900/50 px-3 py-2">
          <p className="text-[11px] uppercase tracking-wide text-slate-400">Tablero</p>
          <p className="font-semibold">{myPos ? (BOARD_LABEL[myPos.board_key] ?? myPos.board_key) : '—'}</p>
        </div>
        <div className="rounded-lg bg-slate-900/50 px-3 py-2">
          <p className="text-[11px] uppercase tracking-wide text-slate-400">Mi casilla</p>
          <p className="font-semibold truncate">{cur ? cur.name : '—'}</p>
          {cur && <p className="text-[11px] text-slate-400">{spaceTypeLabel(cur.space_type)}{myPos ? ` · #${myPos.space_index}` : ''}</p>}
        </div>
      </div>

      {/* Última tirada + resultado del movimiento */}
      {(roll || move) && (
        <div className="flex flex-col gap-1 rounded-lg bg-slate-900/40 px-3 py-2 text-sm">
          {roll && (
            <p>
              <span className="mr-2 text-lg" aria-hidden>{face(roll.d1)} {face(roll.d2)}</span>
              Última tirada: <span className="font-semibold">{roll.d1} + {roll.d2} = {roll.total}</span>
            </p>
          )}
          {move && (
            <p className="text-xs text-slate-300">
              {move.method === 'roll' ? 'Tirada' : move.method === 'manual' ? 'Movimiento' : 'Movimiento'}: avanzó {move.steps}{' '}
              a <span className="font-semibold">{move.space_name}</span>
              {move.passed_start && <span className="text-emerald-300"> · pasó por salida (+{formatMoney(move.bonus)})</span>}
            </p>
          )}
        </div>
      )}

      {/* Decisión de cruce: has llegado a la cárcel-guardián y debes elegir destino (no avanza solo). */}
      {choice ? (
        <div className="flex flex-col gap-2 rounded-lg border border-amber-600 bg-amber-950/40 px-3 py-2">
          <p className="text-sm font-semibold text-amber-100">🛡️ Has llegado a la cárcel: elige por dónde seguir ({choice.remaining} {choice.remaining === 1 ? 'casilla' : 'casillas'}).</p>
          {[choice.own, choice.cross].map((opt) => (
            <button
              key={opt.dir}
              type="button"
              onClick={() => onResolveJunction(opt.dir)}
              disabled={busy}
              className={`min-h-[44px] rounded-xl px-4 text-sm font-semibold disabled:opacity-40 ${opt.guarded ? 'border border-amber-500 text-amber-200' : 'bg-emerald-600'}`}
            >
              {opt.dir === 'own' ? 'Seguir' : 'Cruzar'} → {opt.name}
              {opt.dir === 'cross' && <span className="text-[11px] font-normal"> ({BOARD_LABEL[opt.board]})</span>}
              {opt.guarded ? <span className="ml-1 text-[11px] font-normal">· peaje {formatMoney(opt.toll)}</span> : <span className="ml-1 text-[11px] font-normal">· gratis</span>}
            </button>
          ))}
        </div>
      ) : mine ? (
        <div className="flex flex-col gap-2">
          <button
            type="button"
            onClick={onRoll}
            disabled={busy}
            className="min-h-[44px] rounded-xl bg-emerald-600 px-4 text-base font-semibold disabled:opacity-40"
          >
            🎲 Tirar dados
          </button>
          {/* Mover manualmente: selector de pasos 1–12 con botones grandes (cómodo en iPhone, sin
              depender de <input type="number">, que en Safari móvil no ofrece flechas y complica los
              dígitos). El botón Mover queda deshabilitado hasta elegir un valor válido (1–12). */}
          <div role="group" aria-label="Mover manualmente" className="flex flex-col gap-2">
            <p className="text-[11px] text-slate-400">Mover manualmente (casillas)</p>
            <div className="grid grid-cols-6 gap-1">
              {Array.from({ length: 12 }, (_, i) => i + 1).map((n) => (
                <button
                  key={n}
                  type="button"
                  aria-label={`${n} ${n === 1 ? 'casilla' : 'casillas'}`}
                  aria-pressed={steps === n}
                  onClick={() => setSteps(n)}
                  disabled={busy}
                  className={`min-h-[44px] rounded-lg text-sm font-semibold tabular-nums disabled:opacity-40 ${
                    steps === n ? 'bg-sky-600 text-white' : 'border border-slate-600 text-slate-200 active:bg-slate-800'
                  }`}
                >
                  {n}
                </button>
              ))}
            </div>
            <button
              type="button"
              onClick={() => steps !== null && onMoveManual(steps)}
              disabled={busy || steps === null}
              className="min-h-[44px] rounded-xl border border-slate-600 px-3 text-sm font-semibold disabled:opacity-40"
            >
              {steps !== null ? `Mover ${steps}` : 'Mover'}
            </button>
          </div>
        </div>
      ) : (
        blockedNote && <p role="note" className="rounded-lg bg-slate-800 px-3 py-2 text-xs text-slate-300">{blockedNote}</p>
      )}

      {/* Contexto de la casilla en la que estoy: propiedad u otra */}
      {cur && prop && status && (
        <div className="flex flex-col gap-2 rounded-lg border border-slate-700 px-3 py-2 text-sm">
          {status === 'available' && (
            <>
              <p>Has caído en <span className="font-semibold">{prop.name}</span> · Disponible para compra ({formatMoney(prop.price)}).</p>
              {canRequestPurchase(prop, snap) ? (
                <button
                  type="button"
                  onClick={() => onRequestPurchase(prop)}
                  disabled={busy}
                  className="min-h-[40px] rounded-lg bg-emerald-600 px-3 text-xs font-semibold disabled:opacity-40"
                >
                  Solicitar compra
                </button>
              ) : (
                <p className="text-[11px] text-slate-400">{purchaseBlockReason(prop, snap)}</p>
              )}
            </>
          )}
          {status === 'mine' && <p>Has caído en <span className="font-semibold">tu propiedad</span> ({prop.name}).</p>}
          {status === 'owned' && (
            <>
              <p>Has caído en propiedad de <span className="font-semibold">{ownerName(prop, snap)}</span> ({prop.name}).</p>
              {prop.base_rent > 0 && (
                <button
                  type="button"
                  onClick={() => onPayRent(prop)}
                  disabled={busy || !canPayRent(prop, snap)}
                  className="min-h-[40px] rounded-lg border border-amber-600 px-3 text-xs font-semibold text-amber-200 disabled:opacity-40"
                >
                  Pagar alquiler ({formatMoney(prop.base_rent)})
                </button>
              )}
            </>
          )}
          {status === 'in_auction' && <p>{prop.name} está en subasta.</p>}
          <button
            type="button"
            onClick={() => setCard(prop)}
            className="min-h-[36px] rounded-lg border border-slate-600 px-3 text-[11px] font-semibold text-slate-300"
          >
            Ver tarjeta
          </button>
        </div>
      )}
      {cur && !prop && cur.space_type !== 'start' && (
        <p role="note" className="rounded-lg bg-slate-800 px-3 py-2 text-xs text-slate-300">
          Has caído en {cur.name}. Esta casilla se resolverá en una fase posterior.
        </p>
      )}
      {cur && cur.space_type === 'start' && (
        <p className="rounded-lg bg-slate-800 px-3 py-2 text-xs text-slate-300">Estás en la casilla de salida.</p>
      )}

      {card && <PropertyCardModal property={card} snap={snap} onClose={() => setCard(null)} />}
    </section>
  );
}
