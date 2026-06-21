import type { TradeProposal, TradeProperty, TradeCard } from '../../lib/activeSnapshot';
import { formatMoney, getTradePerspective } from '../../lib/activeSelectors';

/** Lista los elementos de un lado del trato (dinero, propiedades, cartas). */
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

function SideBox({ title, side }: { title: string; side: { money: number; properties: TradeProperty[]; cards: TradeCard[] } }) {
  return (
    <div className="min-w-0 rounded-lg bg-slate-800/60 p-2">
      <p className="mb-1 text-[11px] font-semibold text-slate-400">{title}</p>
      <ul className="flex flex-col gap-0.5 text-slate-200">
        <SideItems money={side.money} props={side.properties} cards={side.cards} />
      </ul>
    </div>
  );
}

/** Resumen de un trato. Si `viewerRef` es participante, se orienta a su perspectiva (Tú entregas / Tú recibes);
 *  si no (p. ej. el anfitrión que solo aprueba), se muestra neutral con los nombres de ambos jugadores. */
export function TradeSummary({ trade, viewerRef }: { trade: TradeProposal; viewerRef?: string }) {
  const persp = viewerRef ? getTradePerspective(trade, viewerRef) : null;
  if (persp?.isParticipant) {
    return (
      <div className="flex flex-col gap-2 text-sm">
        <div className="grid grid-cols-2 gap-2">
          <SideBox title="Tú entregas" side={persp.youGive} />
          <SideBox title="Tú recibes" side={persp.youReceive} />
        </div>
        {trade.agreement_text && <AgreementNote text={trade.agreement_text} />}
      </div>
    );
  }
  // Vista neutral (no participante): nombres de ambos lados.
  return (
    <div className="flex flex-col gap-2 text-sm">
      <div className="grid grid-cols-2 gap-2">
        <SideBox title={`${trade.from_name} entrega`} side={{ money: trade.from_money, properties: trade.from_properties, cards: trade.from_cards }} />
        <SideBox title={`${trade.to_name} entrega`} side={{ money: trade.to_money, properties: trade.to_properties, cards: trade.to_cards }} />
      </div>
      {trade.agreement_text && <AgreementNote text={trade.agreement_text} />}
    </div>
  );
}

function AgreementNote({ text }: { text: string }) {
  return (
    <div className="rounded-lg border border-slate-700 p-2 text-[12px]">
      <p className="text-slate-300"><span className="font-semibold">Acuerdo:</span> {text}</p>
      <p className="mt-1 text-[11px] text-amber-300/90">Este acuerdo queda registrado, pero la app no lo hará cumplir automáticamente.</p>
    </div>
  );
}
