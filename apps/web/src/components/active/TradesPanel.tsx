import type { ActiveSnapshot, TradeProposal, TradeStatus } from '../../lib/activeSnapshot';
import { TradeSummary } from './TradeSummary';

const STATUS_LABEL: Record<TradeStatus, string> = {
  pending: 'Pendiente', countered: 'Contraoferta', host_review: 'Pendiente del anfitrión',
  executed: 'Ejecutado', rejected: 'Rechazado', cancelled: 'Cancelado', invalidated: 'Inválido (cambió el estado)',
};

interface TradeActions {
  onAccept: (t: TradeProposal) => void;
  onReject: (t: TradeProposal) => void;
  onCancel: (t: TradeProposal) => void;
  onCounter: (t: TradeProposal) => void;
}

function TradeRow({ t, me, actions }: { t: TradeProposal; me: string; actions: TradeActions }) {
  const canAct = t.pending_party === me && (t.status === 'pending' || t.status === 'countered');
  const canCancel = t.from_ref === me && (t.status === 'pending' || t.status === 'countered' || t.status === 'host_review');
  const otherName = t.from_ref === me ? t.to_name : t.from_name;
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-slate-700 p-2">
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs text-slate-400">{t.from_name} ↔ {t.to_name}</span>
        <span className="rounded bg-slate-800 px-2 py-0.5 text-[10px] text-slate-300">{STATUS_LABEL[t.status]}</span>
      </div>
      <TradeSummary trade={t} meRef={me} />
      {canAct ? (
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={() => actions.onAccept(t)} className="min-h-[36px] flex-1 rounded-lg bg-emerald-600 px-3 text-xs font-semibold">Aceptar</button>
          <button type="button" onClick={() => actions.onCounter(t)} className="min-h-[36px] flex-1 rounded-lg bg-indigo-600 px-3 text-xs font-semibold">Contraofertar</button>
          <button type="button" onClick={() => actions.onReject(t)} className="min-h-[36px] flex-1 rounded-lg border border-slate-600 px-3 text-xs font-semibold">Rechazar</button>
        </div>
      ) : t.status === 'host_review' ? (
        <p className="text-[11px] text-amber-300/90">Esperando la aprobación del anfitrión.</p>
      ) : (
        <p className="text-[11px] text-slate-500">Esperando a {otherName}.</p>
      )}
      {canCancel && !canAct && (
        <button type="button" onClick={() => actions.onCancel(t)} className="min-h-[36px] w-full rounded-lg border border-rose-700 px-3 text-xs font-semibold text-rose-300">Cancelar</button>
      )}
    </div>
  );
}

/** Panel de tratos del jugador: crear, recibidos, enviados e historial reciente. */
export function TradesPanel({ snap, onCreate, actions }: {
  snap: ActiveSnapshot;
  onCreate: () => void;
  actions: TradeActions;
}) {
  const me = snap.me.public_ref;
  const history = snap.recent_trades;
  return (
    <section aria-label="Tratos" className="flex flex-col gap-3 rounded-xl border border-indigo-500/30 p-4">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-sm font-bold text-indigo-300">Tratos</h2>
        <button type="button" onClick={onCreate} disabled={snap.me.is_spectator} className="min-h-[36px] rounded-lg bg-indigo-600 px-3 text-xs font-semibold disabled:opacity-40">Crear trato</button>
      </div>

      {snap.incoming_trades.length > 0 && (
        <div className="flex flex-col gap-2">
          <p className="text-xs font-semibold text-slate-300">Recibidos</p>
          {snap.incoming_trades.map((t) => <TradeRow key={t.trade_ref} t={t} me={me} actions={actions} />)}
        </div>
      )}
      {snap.outgoing_trades.length > 0 && (
        <div className="flex flex-col gap-2">
          <p className="text-xs font-semibold text-slate-300">Enviados</p>
          {snap.outgoing_trades.map((t) => <TradeRow key={t.trade_ref} t={t} me={me} actions={actions} />)}
        </div>
      )}
      {snap.incoming_trades.length === 0 && snap.outgoing_trades.length === 0 && (
        <p className="text-[12px] text-slate-500">No tienes tratos activos. Pulsa «Crear trato» para proponer uno.</p>
      )}

      {history.length > 0 && (
        <details className="rounded-lg bg-slate-800/40 p-2">
          <summary className="cursor-pointer text-xs font-semibold text-slate-300">Historial reciente ({history.length})</summary>
          <div className="mt-2 flex flex-col gap-2">
            {history.map((t) => (
              <div key={t.trade_ref} className="rounded-lg border border-slate-800 p-2 text-xs">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-slate-400">{t.from_name} ↔ {t.to_name}</span>
                  <span className="rounded bg-slate-800 px-2 py-0.5 text-[10px] text-slate-300">{STATUS_LABEL[t.status]}</span>
                </div>
                <div className="mt-1"><TradeSummary trade={t} meRef={me} /></div>
              </div>
            ))}
          </div>
        </details>
      )}
    </section>
  );
}
