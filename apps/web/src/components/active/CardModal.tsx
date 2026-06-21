import { useRef } from 'react';
import type { CardToShow } from '../../hooks/useCardDraw';
import { deckLabel } from '../../lib/activeSelectors';
import { useDialogA11y } from '../../hooks/useDialogA11y';

/** Modal de carta robada (Fase 5): título, mazo, texto y efecto aplicado. Las cartas con efecto
 *  soportado se cierran con "Aceptar"; las de resolución manual exigen "Marcar como resuelta" (RPC). */
export function CardModal({ show, busy, onAccept, onResolve, onChoice }: {
  show: CardToShow;
  busy: boolean;
  onAccept: () => void;       // descarta el modal de una carta ya aplicada (cliente)
  onResolve: () => void;      // marca como resuelta una carta manual (RPC)
  onChoice: (choice: 'pay' | 'draw') => void; // resuelve una carta de elección
}) {
  const ref = useRef<HTMLDivElement>(null);
  const btnRef = useRef<HTMLButtonElement>(null);
  const { card, mustResolve, choice, instruction } = show;
  // Las cartas manuales no se cierran con Escape (hay que resolverlas).
  useDialogA11y(true, ref, { onEscape: onAccept, escapeEnabled: !mustResolve, initialFocusRef: btnRef });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" onClick={mustResolve ? undefined : onAccept}>
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-label={`Carta: ${card.title}`}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
        className="flex w-full max-w-sm flex-col gap-3 rounded-2xl border border-amber-500/40 bg-slate-900 p-5 shadow-xl"
      >
        <div className="flex items-center gap-2">
          <span aria-hidden className="text-2xl">🃏</span>
          <div className="min-w-0">
            <p className="text-[11px] uppercase tracking-wide text-amber-300">{deckLabel(card.deck_key)}</p>
            <h2 className="text-base font-bold leading-tight">{card.title}</h2>
          </div>
        </div>
        <p className="text-sm text-slate-300">{card.description}</p>
        {card.temporary && (
          <p className="rounded-lg bg-amber-950/40 px-3 py-1.5 text-[11px] text-amber-200">
            Carta temporal — pendiente de sustituir por la carta real.
          </p>
        )}
        {instruction && (
          <p role="note" className="rounded-lg bg-slate-800 px-3 py-2 text-xs text-slate-300">{instruction}</p>
        )}
        {choice ? (
          <div className="flex flex-col gap-2 sm:flex-row">
            <button ref={btnRef} type="button" onClick={() => onChoice('pay')} disabled={busy}
              className="min-h-[44px] flex-1 rounded-xl bg-amber-600 px-4 text-sm font-semibold disabled:opacity-40">
              Pagar 10 € al bote
            </button>
            <button type="button" onClick={() => onChoice('draw')} disabled={busy}
              className="min-h-[44px] flex-1 rounded-xl bg-indigo-600 px-4 text-sm font-semibold disabled:opacity-40">
              Robar carta de Suerte
            </button>
          </div>
        ) : mustResolve ? (
          <>
            {!instruction && (
              <p role="note" className="rounded-lg bg-slate-800 px-3 py-2 text-xs text-slate-300">
                Su efecto aún no está automatizado: aplícalo entre vosotros y márcala como resuelta.
              </p>
            )}
            <button
              ref={btnRef}
              type="button"
              onClick={onResolve}
              disabled={busy}
              className="min-h-[44px] rounded-xl bg-amber-600 px-4 text-sm font-semibold disabled:opacity-40"
            >
              {busy ? 'Procesando…' : 'Marcar como resuelta'}
            </button>
          </>
        ) : (
          <button
            ref={btnRef}
            type="button"
            onClick={onAccept}
            className="min-h-[44px] rounded-xl bg-emerald-600 px-4 text-sm font-semibold"
          >
            Aceptar
          </button>
        )}
      </div>
    </div>
  );
}
