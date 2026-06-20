import { useState } from 'react';
import type { ActiveProperty, ActiveSnapshot } from '../../lib/activeSnapshot';
import {
  formatMoney, currentPlayerName, BOARD_LABEL, spaceTypeLabel, canRoll, currentSpaceProperty,
  propertyStatus, canRequestPurchase, canPayRent, ownerName, purchaseBlockReason, junctionChoice,
  physicalAllowed, virtualAllowed, utilityRentInfo, canPayUtilityRent,
} from '../../lib/activeSelectors';
import { PropertyCardModal } from './PropertyCardModal';

const DICE = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];
const face = (n: number) => DICE[n - 1] ?? '🎲';

/** Entrada de dados físicos cómoda en iPhone: dos filas de botones 1–6, total y dobles calculados, y
 *  un botón de confirmar. No usa <input type="number"> (frágil en Safari móvil). */
function PhysicalDiceInput({ busy, label, cta, onSubmit }: { busy: boolean; label: string; cta: string; onSubmit: (d1: number, d2: number) => void; }) {
  const [d1, setD1] = useState<number | null>(null);
  const [d2, setD2] = useState<number | null>(null);
  const ready = d1 !== null && d2 !== null;
  const total = (d1 ?? 0) + (d2 ?? 0);
  const doubles = ready && d1 === d2;
  const row = (name: string, val: number | null, set: (n: number) => void) => (
    <div className="flex flex-col gap-1">
      <p className="text-[11px] text-slate-400">{name}</p>
      <div className="grid grid-cols-6 gap-1">
        {[1, 2, 3, 4, 5, 6].map((n) => (
          <button
            key={n}
            type="button"
            aria-label={`${name}: ${n}`}
            aria-pressed={val === n}
            onClick={() => set(n)}
            disabled={busy}
            className={`min-h-[44px] rounded-lg text-base tabular-nums disabled:opacity-40 ${val === n ? 'bg-sky-600 text-white' : 'border border-slate-600 text-slate-200 active:bg-slate-800'}`}
          >
            {face(n)}
          </button>
        ))}
      </div>
    </div>
  );
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-slate-600 bg-slate-900/40 px-3 py-2">
      <p className="text-[11px] font-medium text-slate-300">{label}</p>
      {row('Dado 1', d1, setD1)}
      {row('Dado 2', d2, setD2)}
      <p className="text-xs text-slate-300">Total: <span className="font-semibold tabular-nums">{ready ? total : '—'}</span>{doubles && <span className="ml-1 text-emerald-300">· dobles</span>}</p>
      <button
        type="button"
        onClick={() => ready && onSubmit(d1, d2)}
        disabled={busy || !ready}
        className="min-h-[44px] rounded-xl bg-emerald-600 px-4 text-sm font-semibold disabled:opacity-40"
      >
        {busy ? 'Procesando…' : cta}
      </button>
    </div>
  );
}

/** Alquiler de un SERVICIO (utility) propiedad de otro: tirada × multiplicador según servicios del
 *  propietario (combinados entre ambos tableros). Si hay tirada válida del pagador, ofrece pagar; si no,
 *  pide una tirada (virtual o física, según el modo). */
function UtilitySection({ prop, snap, busy, onPay }: {
  prop: ActiveProperty; snap: ActiveSnapshot; busy: boolean;
  onPay: (p: ActiveProperty, d1: number | null, d2: number | null) => void;
}) {
  const info = utilityRentInfo(prop, snap);
  return (
    <div className="flex flex-col gap-2">
      <p className="text-[11px] text-slate-300">
        Servicios poseídos por {ownerName(prop, snap)}: <span className="font-semibold">{info.count}/4</span> · Multiplicador <span className="font-semibold">×{info.multiplier}</span>
      </p>
      {info.total !== null ? (
        <>
          <p className="text-[11px] text-slate-300">Tirada: <span className="font-semibold">{info.total}</span> · Alquiler <span className="font-semibold text-amber-200">{formatMoney(info.amount ?? 0)}</span></p>
          <button
            type="button"
            onClick={() => onPay(prop, null, null)}
            disabled={busy || !canPayUtilityRent(prop, snap)}
            className="min-h-[40px] rounded-lg border border-amber-600 px-3 text-xs font-semibold text-amber-200 disabled:opacity-40"
          >
            Pagar alquiler ({formatMoney(info.amount ?? 0)})
          </button>
        </>
      ) : (
        <>
          <p className="text-[11px] text-amber-200/90">Este servicio necesita una tirada para calcular el alquiler.</p>
          {virtualAllowed(snap) && (
            <button
              type="button"
              onClick={() => onPay(prop, null, null)}
              disabled={busy || !snap.me.is_current}
              className="min-h-[40px] rounded-lg bg-emerald-600 px-3 text-xs font-semibold disabled:opacity-40"
            >
              🎲 Tirar dados virtuales para el servicio
            </button>
          )}
          {physicalAllowed(snap) && snap.me.is_current && (
            <PhysicalDiceInput busy={busy} label="Introduce los dados del servicio" cta="Calcular y pagar servicio" onSubmit={(d1, d2) => onPay(prop, d1, d2)} />
          )}
        </>
      )}
    </div>
  );
}

/** Bloque "Movimiento" de la pantalla principal: turno, posición y casilla actuales, última tirada
 *  y resultado del último movimiento. El jugador actual tira dados o mueve manualmente; al caer en
 *  una propiedad ofrece, desde el contexto, solicitar compra o pagar alquiler (reutiliza los flujos).
 *  Las casillas aún no implementadas muestran un aviso de "fase posterior". */
export function MovementPanel({
  snap, busy, onRoll, onMovePhysical, onMoveManual, onOpenBoard, onRequestPurchase, onPayRent, onPayUtilityRent, onResolveJunction,
  onPayJailRelease, onUseJailCard, onPayPending,
}: {
  snap: ActiveSnapshot;
  busy: boolean;
  onRoll: () => void;
  onMovePhysical: (d1: number, d2: number) => void;
  onMoveManual: (steps: number) => void;
  onOpenBoard: () => void;
  onRequestPurchase: (p: ActiveProperty) => void;
  onPayRent: (p: ActiveProperty) => void;
  onPayUtilityRent: (p: ActiveProperty, d1: number | null, d2: number | null) => void;
  onResolveJunction: (dir: 'own' | 'cross') => void;
  onPayJailRelease: () => void;
  onUseJailCard: () => void;
  onPayPending: () => void;
}) {
  const [steps, setSteps] = useState<number | null>(null);
  const [card, setCard] = useState<ActiveProperty | null>(null);
  const choice = junctionChoice(snap);
  const myJail = snap.my_jail;                 // estoy en la cárcel
  const pendingPay = snap.pending_payment;     // pago obligado pendiente (ya viene filtrado a mí)
  const pot = snap.parking_pot;
  const effect = snap.last_move?.effect ?? null;
  const hasJailCard = snap.my_held_cards.some((c) => c.effect_type === 'jail_free');
  // Solo se puede tirar/mover si me toca, no estoy en la cárcel y no tengo pagos/cartas pendientes.
  const mine = canRoll(snap) && !myJail && !pendingPay;
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
          {/* Resultado del intento de dobles en la cárcel (solo para quien tiró). */}
          {roll?.jail && roll.player_ref === snap.me.public_ref && (
            <p className={`text-xs font-medium ${roll.jail === 'doubles' ? 'text-emerald-300' : 'text-amber-300'}`}>
              {roll.jail === 'doubles' && 'Has sacado dobles y sales de la cárcel.'}
              {roll.jail === 'failed' && 'No has sacado dobles. Sigues en la cárcel.'}
              {roll.jail === 'forced_paid' && 'Tercer intento fallido. Pagas 50 ₥ y sales de la cárcel.'}
              {roll.jail === 'forced_pending' && 'Tercer intento fallido. Debes pagar 50 ₥ para salir.'}
            </p>
          )}
          {move && (
            <p className="text-xs text-slate-300">
              {move.method === 'roll' ? 'Tirada' : move.method === 'manual' ? 'Movimiento' : 'Movimiento'}: avanzó {move.steps}{' '}
              a <span className="font-semibold">{move.space_name}</span>
              {move.passed_start && <span className="text-emerald-300"> · pasó por salida (+{formatMoney(move.bonus)})</span>}
            </p>
          )}
          {/* Efecto de la casilla en la que se cayó (impuesto / parking / cárcel / carta). */}
          {effect && effect.type !== 'none' && (
            <p className="text-xs font-medium">
              {effect.type === 'tax' && (effect.paid
                ? <span className="text-rose-300">Has pagado {formatMoney(effect.amount ?? 0)} de impuesto.</span>
                : <span className="text-rose-300">Debes pagar {formatMoney(effect.amount ?? 0)} de impuesto.</span>)}
              {effect.type === 'parking' && ((effect.payout ?? 0) > 0
                ? <span className="text-emerald-300">Has cobrado el bote de Parking: {formatMoney(effect.payout ?? 0)}.</span>
                : <span className="text-slate-400">Parking gratuito. No hay bote acumulado.</span>)}
              {effect.type === 'go_to_jail' && <span className="text-amber-300">Has sido enviado a la cárcel.</span>}
              {effect.type === 'card' && !effect.empty && <span className="text-amber-200">Has robado una carta{effect.title ? `: ${effect.title}` : ''}.</span>}
            </p>
          )}
        </div>
      )}

      {/* Bote del Parking gratuito (compartido entre ambos tableros). */}
      <div className="flex items-center justify-between rounded-lg bg-slate-900/50 px-3 py-1.5 text-xs">
        <span className="text-slate-400">Bote Parking</span>
        <span className="font-semibold tabular-nums text-emerald-200">{formatMoney(pot)}</span>
      </div>

      {/* Inventario de cartas conservables (p. ej. "Sal de la cárcel gratis"). */}
      {snap.my_held_cards.length > 0 && (
        <div className="rounded-lg border border-slate-700 px-3 py-2 text-xs">
          <p className="text-slate-400">Tus cartas</p>
          <ul className="mt-0.5 flex flex-col gap-0.5">
            {snap.my_held_cards.map((c, i) => (
              <li key={`${c.card_ref}-${i}`} className="truncate text-slate-200">🃏 {c.title}</li>
            ))}
          </ul>
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
      ) : pendingPay ? (
        <div className="flex flex-col gap-2 rounded-lg border border-rose-600 bg-rose-950/40 px-3 py-2">
          <p className="text-sm font-semibold text-rose-100">Debes pagar {formatMoney(pendingPay.amount)} ({pendingPay.space_name}).</p>
          <p className="text-[11px] text-rose-200/80">Págalo si puedes; si no, decláralo en bancarrota desde el panel de saldos.</p>
          <button
            type="button"
            onClick={onPayPending}
            disabled={busy || !snap.me.is_current}
            className="min-h-[44px] rounded-xl bg-rose-600 px-4 text-sm font-semibold disabled:opacity-40"
          >
            {busy ? 'Procesando…' : `Pagar ${formatMoney(pendingPay.amount)}`}
          </button>
        </div>
      ) : myJail ? (
        <div className="flex flex-col gap-2 rounded-lg border border-amber-600 bg-amber-950/40 px-3 py-2">
          <p className="text-sm font-semibold text-amber-100">
            🔒 Estás en la cárcel. <span className="font-normal">Intento {Math.min(myJail.jail_turns + 1, 3)}/3.</span>
          </p>
          {!snap.me.is_current ? (
            <p className="text-[11px] text-amber-200/80">Espera tu turno para intentar dobles, pagar la multa o usar una carta.</p>
          ) : myJail.action_taken_this_turn ? (
            // Solo una acción de cárcel por turno: ya la usó este turno → debe finalizar turno.
            <p role="note" className="rounded-lg bg-amber-900/50 px-3 py-2 text-xs text-amber-100">
              Ya has intentado salir de la cárcel en este turno. Debes finalizar turno.
            </p>
          ) : (
            <>
              {virtualAllowed(snap) && (
                <button
                  type="button"
                  onClick={onRoll}
                  disabled={busy}
                  className="min-h-[44px] rounded-xl bg-emerald-600 px-4 text-base font-semibold disabled:opacity-40"
                >
                  🎲 Intentar sacar dobles
                </button>
              )}
              {physicalAllowed(snap) && (
                <PhysicalDiceInput busy={busy} label="Intento con dados físicos" cta="Intentar salir con estos dados" onSubmit={onMovePhysical} />
              )}
              <button
                type="button"
                onClick={onPayJailRelease}
                disabled={busy}
                className="min-h-[44px] rounded-xl bg-amber-600 px-4 text-sm font-semibold disabled:opacity-40"
              >
                {busy ? 'Procesando…' : `Pagar ${formatMoney(myJail.fine)} para salir`}
              </button>
              {hasJailCard && (
                <button
                  type="button"
                  onClick={onUseJailCard}
                  disabled={busy}
                  className="min-h-[44px] rounded-xl border border-amber-500 px-4 text-sm font-semibold text-amber-200 disabled:opacity-40"
                >
                  Usar carta «Sal de la cárcel gratis»
                </button>
              )}
              <p className="text-[11px] text-amber-200/80">Solo una acción por turno. Si no sales antes, al tercer intento pagas 50 ₥ y sales. No puedes mover manualmente.</p>
            </>
          )}
        </div>
      ) : mine ? (
        <div className="flex flex-col gap-2">
          {virtualAllowed(snap) && (
            <button
              type="button"
              onClick={onRoll}
              disabled={busy}
              className="min-h-[44px] rounded-xl bg-emerald-600 px-4 text-base font-semibold disabled:opacity-40"
            >
              🎲 Tirar dados
            </button>
          )}
          {physicalAllowed(snap) && (
            <PhysicalDiceInput busy={busy} label="Introducir tirada física" cta="Mover con estos dados" onSubmit={onMovePhysical} />
          )}
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
              {prop.kind === 'utility' ? (
                <UtilitySection prop={prop} snap={snap} busy={busy} onPay={onPayUtilityRent} />
              ) : prop.base_rent > 0 ? (
                <button
                  type="button"
                  onClick={() => onPayRent(prop)}
                  disabled={busy || !canPayRent(prop, snap)}
                  className="min-h-[40px] rounded-lg border border-amber-600 px-3 text-xs font-semibold text-amber-200 disabled:opacity-40"
                >
                  Pagar alquiler ({formatMoney(prop.base_rent)})
                </button>
              ) : null}
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
