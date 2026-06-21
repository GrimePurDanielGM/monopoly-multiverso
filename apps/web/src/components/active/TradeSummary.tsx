import type { TradeProposal, TradeProperty, TradeCard } from '../../lib/activeSnapshot';
import { formatMoney } from '../../lib/activeSelectors';

/** Lista los elementos que entrega un lado del trato (dinero, propiedades, cartas). */
function SideItems({ money, props, cards }: { money: number; props: TradeProperty[]; cards: TradeCard[] }) {
  const empty = money <= 0 && props.length === 0 && cards.length === 0;
  if (empty) return <li className="text-slate-500">Nada</li>;
  return (
    <>
      {money > 0 && <li className="tabular-nums">{formatMoney(money)}</li>}
      {props.map((p) => (
        <li key={p.property_ref} className="break-words">
          {p.name}{p.mortgaged && <span className="ml-1 rounded bg-amber-900/60 px-1 text-[10px] text-amber-200">Hipotecada</span>}
        </li>
      ))}
      {cards.map((c) => <li key={c.card_ref} className="break-words">🃏 {c.title}</li>)}
    </>
  );
}

/** Resumen claro de un trato: qué entrega cada lado y el acuerdo personal si lo hay. */
export function TradeSummary({ trade, meRef }: { trade: TradeProposal; meRef?: string }) {
  const label = (ref: string, name: string) => (ref === meRef ? `${name} (tú)` : name);
  return (
    <div className="flex flex-col gap-2 text-sm">
      <div className="grid grid-cols-2 gap-2">
        <div className="rounded-lg bg-slate-800/60 p-2">
          <p className="mb-1 text-[11px] font-semibold text-slate-400">{label(trade.from_ref, trade.from_name)} entrega</p>
          <ul className="flex flex-col gap-0.5 text-slate-200">
            <SideItems money={trade.from_money} props={trade.from_properties} cards={trade.from_cards} />
          </ul>
        </div>
        <div className="rounded-lg bg-slate-800/60 p-2">
          <p className="mb-1 text-[11px] font-semibold text-slate-400">{label(trade.to_ref, trade.to_name)} entrega</p>
          <ul className="flex flex-col gap-0.5 text-slate-200">
            <SideItems money={trade.to_money} props={trade.to_properties} cards={trade.to_cards} />
          </ul>
        </div>
      </div>
      {trade.agreement_text && (
        <div className="rounded-lg border border-slate-700 p-2 text-[12px]">
          <p className="text-slate-300"><span className="font-semibold">Acuerdo:</span> {trade.agreement_text}</p>
          <p className="mt-1 text-[11px] text-amber-300/90">Este acuerdo queda registrado, pero la app no lo hará cumplir automáticamente.</p>
        </div>
      )}
    </div>
  );
}
