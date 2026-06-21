import { useMemo, useRef, useState } from 'react';
import type { ActiveSnapshot, ActiveProperty } from '../../lib/activeSnapshot';
import type { TradeTerms } from '../../lib/api';
import { formatMoney, propertiesOf } from '../../lib/activeSelectors';
import { useDialogA11y } from '../../hooks/useDialogA11y';

const MAX_MONEY = 10_000_000;
const hasBuildings = (p: ActiveProperty) => (p.houses ?? 0) > 0 || p.has_hotel === true;

function toInt(v: string): number {
  const n = parseInt(v, 10);
  return Number.isNaN(n) || n < 0 ? 0 : Math.min(n, MAX_MONEY);
}

/** Lista de propiedades de un jugador con casillas para incluirlas en el trato. Las que tienen construcciones
 *  no se pueden seleccionar; las hipotecadas se marcan. */
function PropertyPicker({ title, props, selected, onToggle }: {
  title: string; props: ActiveProperty[]; selected: Set<string>; onToggle: (ref: string) => void;
}) {
  if (props.length === 0) return <p className="text-[11px] text-slate-500">{title}: sin propiedades.</p>;
  return (
    <div className="flex flex-col gap-1">
      <p className="text-[11px] font-semibold text-slate-400">{title}</p>
      <div className="flex max-h-40 flex-col gap-1 overflow-y-auto overscroll-contain pr-1">
        {props.map((p) => {
          const blocked = hasBuildings(p);
          return (
            <label key={p.property_ref} className={`flex items-center gap-2 rounded-lg border px-2 py-1.5 text-sm ${blocked ? 'border-slate-800 opacity-50' : 'border-slate-700'}`}>
              <input type="checkbox" disabled={blocked} checked={selected.has(p.property_ref)} onChange={() => onToggle(p.property_ref)} className="h-4 w-4" />
              <span className="flex-1 break-words">{p.name}</span>
              {p.mortgaged && <span className="rounded bg-amber-900/60 px-1 text-[10px] text-amber-200">Hipotecada</span>}
              {blocked && <span className="text-[10px] text-slate-500">No disponible: tiene construcciones</span>}
            </label>
          );
        })}
      </div>
    </div>
  );
}

/** Términos iniciales en perspectiva del que mira (lo que YO doy / lo que pido). */
export interface TradeDraftInitial { myMoney: number; theirMoney: number; myProps: string[]; theirProps: string[]; myCards: string[]; agreement?: string | null }

/** Modal para crear (o contraofertar) un trato: dinero, propiedades y cartas de cada lado + acuerdo personal.
 *  Siempre en perspectiva del que mira ("Tú ofreces" = mi lado). `meIsFrom` indica si soy el lado "from" del
 *  modelo (creador) para mapear correctamente al enviar la propuesta/contraoferta. */
export function CreateTradeModal({ snap, busy = false, mode = 'create', fixedToRef, meIsFrom = true, initial, otherCards, onClose, onSubmit }: {
  snap: ActiveSnapshot;
  busy?: boolean;
  mode?: 'create' | 'counter';
  fixedToRef: string | undefined;
  meIsFrom?: boolean;
  initial: TradeDraftInitial | undefined;
  otherCards?: string[] | undefined;
  onClose: () => void;
  onSubmit: (toRef: string, terms: TradeTerms) => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  useDialogA11y(true, ref, { onEscape: onClose, initialFocusRef: closeRef });

  const me = snap.me.public_ref;
  const others = snap.players.filter((p) => p.public_ref !== me && p.status === 'active');
  const [toRef, setToRef] = useState(fixedToRef ?? others[0]?.public_ref ?? '');
  const [myMoney, setMyMoney] = useState(String(initial?.myMoney ?? 0));
  const [theirMoney, setTheirMoney] = useState(String(initial?.theirMoney ?? 0));
  const [myProps, setMyProps] = useState<Set<string>>(new Set(initial?.myProps ?? []));
  const [theirProps, setTheirProps] = useState<Set<string>>(new Set(initial?.theirProps ?? []));
  const [myCards, setMyCards] = useState<Set<string>>(new Set(initial?.myCards ?? []));
  const [agreement, setAgreement] = useState(initial?.agreement ?? '');

  const myProperties = useMemo(() => propertiesOf(me, snap), [me, snap]);
  const theirProperties = useMemo(() => (toRef ? propertiesOf(toRef, snap) : []), [toRef, snap]);
  const toName = others.find((p) => p.public_ref === toRef)?.display_name ?? '';

  const toggle = (set: React.Dispatch<React.SetStateAction<Set<string>>>, refStr: string) =>
    set((prev) => { const n = new Set(prev); if (n.has(refStr)) n.delete(refStr); else n.add(refStr); return n; });

  // Lado del que mira → lados from/to del modelo, según meIsFrom. Las cartas de la OTRA parte (no editables) se conservan.
  const myMoneyN = toInt(myMoney); const theirMoneyN = toInt(theirMoney);
  const mp = [...myProps]; const tp = [...theirProps]; const mc = [...myCards]; const oc = otherCards ?? [];
  const agree = agreement.trim() || null;
  const terms: TradeTerms = meIsFrom
    ? { fromMoney: myMoneyN, toMoney: theirMoneyN, fromProps: mp, toProps: tp, fromCards: mc, toCards: oc, agreement: agree }
    : { fromMoney: theirMoneyN, toMoney: myMoneyN, fromProps: tp, toProps: mp, fromCards: oc, toCards: mc, agreement: agree };
  const isEmpty = myMoneyN === 0 && theirMoneyN === 0 && mp.length === 0 && tp.length === 0 && mc.length === 0 && oc.length === 0 && !agree;
  const valid = toRef !== '' && !isEmpty && myMoneyN <= snap.me.balance;

  return (
    <div className="fixed inset-0 z-50 touch-pan-y overflow-y-auto overscroll-contain bg-black/60" onClick={onClose} style={{ WebkitOverflowScrolling: 'touch' }}>
      <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
        <div ref={ref} role="dialog" aria-modal="true" aria-label="Crear trato" tabIndex={-1} onClick={(e) => e.stopPropagation()}
          className="flex w-full max-w-md flex-col rounded-t-2xl border border-slate-700 bg-slate-900 shadow-xl sm:rounded-2xl">
          <header className="flex items-center justify-between gap-2 border-b border-slate-700 px-4 py-3 pt-[max(0.75rem,env(safe-area-inset-top))] sm:pt-3">
            <h2 className="text-base font-bold">{mode === 'counter' ? 'Contraoferta' : 'Crear trato'}</h2>
            <button ref={closeRef} type="button" onClick={onClose} aria-label="Cerrar" className="min-h-[36px] rounded-lg border border-slate-600 px-3 text-sm font-semibold">Cerrar</button>
          </header>

          <div className="flex flex-col gap-3 px-4 py-3">
            <label className="flex flex-col gap-1 text-sm">
              <span className="text-slate-300">Con quién</span>
              <select aria-label="Jugador" value={toRef} disabled={mode === 'counter'} onChange={(e) => { setToRef(e.target.value); setTheirProps(new Set()); }}
                className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base disabled:opacity-60">
                {others.map((p) => <option key={p.public_ref} value={p.public_ref}>{p.display_name}</option>)}
              </select>
            </label>

            <div className="rounded-lg border border-indigo-700/50 p-2">
              <p className="mb-1 text-xs font-semibold text-indigo-200">Tú ofreces (saldo: {formatMoney(snap.me.balance)})</p>
              <label className="flex items-center justify-between gap-2 text-sm">
                <span className="text-slate-300">Dinero</span>
                <input aria-label="Dinero que ofrezco" type="text" inputMode="numeric" value={myMoney} onChange={(e) => setMyMoney(e.target.value)}
                  className="min-h-[40px] w-28 rounded-lg border border-slate-600 bg-slate-800 px-2 text-right text-base tabular-nums" />
              </label>
              <div className="mt-2"><PropertyPicker title="Mis propiedades" props={myProperties} selected={myProps} onToggle={(r) => toggle(setMyProps, r)} /></div>
              {snap.my_held_cards.length > 0 && (
                <div className="mt-2 flex flex-col gap-1">
                  <p className="text-[11px] font-semibold text-slate-400">Mis cartas conservables</p>
                  {snap.my_held_cards.map((c) => (
                    <label key={c.card_ref} className="flex items-center gap-2 rounded-lg border border-slate-700 px-2 py-1.5 text-sm">
                      <input type="checkbox" checked={myCards.has(c.card_ref)} onChange={() => toggle(setMyCards, c.card_ref)} className="h-4 w-4" />
                      <span className="flex-1 break-words">🃏 {c.title}</span>
                    </label>
                  ))}
                </div>
              )}
            </div>

            <div className="rounded-lg border border-emerald-700/50 p-2">
              <p className="mb-1 text-xs font-semibold text-emerald-200">Pides a {toName || 'la otra parte'}</p>
              <label className="flex items-center justify-between gap-2 text-sm">
                <span className="text-slate-300">Dinero</span>
                <input aria-label="Dinero que pido" type="text" inputMode="numeric" value={theirMoney} onChange={(e) => setTheirMoney(e.target.value)}
                  className="min-h-[40px] w-28 rounded-lg border border-slate-600 bg-slate-800 px-2 text-right text-base tabular-nums" />
              </label>
              <div className="mt-2"><PropertyPicker title={`Propiedades de ${toName || '—'}`} props={theirProperties} selected={theirProps} onToggle={(r) => toggle(setTheirProps, r)} /></div>
            </div>

            <label className="flex flex-col gap-1 text-sm">
              <span className="text-slate-300">Acuerdo personal (opcional)</span>
              <textarea aria-label="Acuerdo personal" value={agreement} onChange={(e) => setAgreement(e.target.value)} maxLength={280} rows={2}
                placeholder="Ej.: No te cobro alquiler durante 1 turno"
                className="rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-base" />
              {agreement.trim() && <span className="text-[11px] text-amber-300/90">Este acuerdo queda registrado, pero la app no lo hará cumplir automáticamente.</span>}
            </label>

            {myMoneyN > snap.me.balance && <p className="text-[11px] text-amber-300">No puedes ofrecer más dinero del que tienes.</p>}

            <button type="button" disabled={!valid || busy} onClick={() => onSubmit(toRef, terms)}
              className="min-h-[44px] w-full rounded-xl bg-indigo-600 px-4 text-sm font-semibold disabled:opacity-40 pb-[env(safe-area-inset-bottom)]">
              {mode === 'counter' ? 'Enviar contraoferta' : 'Enviar propuesta'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
