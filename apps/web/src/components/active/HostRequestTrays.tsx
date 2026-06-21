import type { ActiveSnapshot, PurchaseRequest, LeaveRequest, BankruptcyRequest, BuildingRequest, BuildingAction, TradeProposal } from '../../lib/activeSnapshot';
import type { ExitResolution } from '../../lib/api';
import { TradeSummary } from './TradeSummary';

/** Bandeja del anfitrión: tratos pendientes de aprobación (con propiedades, cartas o acuerdo). */
export function TradeReviewsTray({ snap, busy, onResolve }: {
  snap: ActiveSnapshot; busy: boolean;
  onResolve: (t: TradeProposal, accept: boolean) => void;
}) {
  if (snap.trade_reviews.length === 0) return null;
  return (
    <section aria-label="Tratos a aprobar" className="flex flex-col gap-2 rounded-xl border border-indigo-700/50 p-4">
      <h2 className="text-sm font-bold text-indigo-200">Tratos a aprobar</h2>
      {snap.trade_reviews.map((t) => (
        <div key={t.trade_ref} className="flex flex-col gap-2 rounded-lg border border-slate-700 p-2 text-sm">
          <span className="text-xs text-slate-400"><span className="font-semibold">{t.from_name}</span> ↔ <span className="font-semibold">{t.to_name}</span></span>
          <TradeSummary trade={t} viewerRef={snap.me.public_ref} />
          <div className="flex gap-2">
            <button type="button" onClick={() => onResolve(t, true)} disabled={busy} className="min-h-[36px] flex-1 rounded-lg bg-emerald-600 px-3 text-xs font-semibold disabled:opacity-40">Aprobar</button>
            <button type="button" onClick={() => onResolve(t, false)} disabled={busy} className="min-h-[36px] flex-1 rounded-lg border border-slate-600 px-3 text-xs font-semibold disabled:opacity-40">Rechazar</button>
          </div>
        </div>
      ))}
    </section>
  );
}

const BUILD_LABEL: Record<BuildingAction, string> = {
  build_house: 'construir una casa', build_hotel: 'construir un hotel', sell_house: 'vender una casa', sell_hotel: 'vender un hotel',
};

/** Bandeja: solicitudes de construcción/venta de casas y hoteles (aprobar / rechazar). */
export function BuildingRequestsTray({
  snap, busy, onResolve,
}: {
  snap: ActiveSnapshot; busy: boolean;
  onResolve: (r: BuildingRequest, accept: boolean) => void;
}) {
  if (snap.building_requests.length === 0) return null;
  return (
    <section aria-label="Solicitudes de construcción" className="flex flex-col gap-2 rounded-xl border border-orange-700/50 p-4">
      <h2 className="text-sm font-bold text-orange-200">Solicitudes de construcción</h2>
      {snap.building_requests.map((r) => (
        <div key={r.request_ref} className="flex flex-wrap items-center gap-2 rounded-lg border border-slate-700 px-3 py-2 text-sm">
          <span className="flex-1 truncate"><span className="font-semibold">{r.requester_name}</span> quiere {BUILD_LABEL[r.action]} en {r.property_name}</span>
          <button type="button" onClick={() => onResolve(r, true)} disabled={busy} className="min-h-[36px] rounded-lg bg-emerald-600 px-3 text-xs font-semibold disabled:opacity-40">Aprobar</button>
          <button type="button" onClick={() => onResolve(r, false)} disabled={busy} className="min-h-[36px] rounded-lg border border-slate-600 px-3 text-xs font-semibold disabled:opacity-40">Rechazar</button>
        </div>
      ))}
    </section>
  );
}

/** Bandeja: solicitudes de compra de propiedades (aprobar / rechazar / iniciar subasta). */
export function PurchaseRequestsTray({
  snap, busy, onResolve, onAuction,
}: {
  snap: ActiveSnapshot; busy: boolean;
  onResolve: (r: PurchaseRequest, accept: boolean) => void;
  onAuction: (r: PurchaseRequest) => void;
}) {
  if (snap.purchase_requests.length === 0) return null;
  return (
    <section aria-label="Solicitudes de compra" className="flex flex-col gap-2 rounded-xl border border-emerald-700/50 p-4">
      <h2 className="text-sm font-bold text-emerald-200">Solicitudes de compra</h2>
      {snap.purchase_requests.map((r) => (
        <div key={r.request_ref} className="flex flex-wrap items-center gap-2 rounded-lg border border-slate-700 px-3 py-2 text-sm">
          <span className="flex-1 truncate"><span className="font-semibold">{r.requester_name}</span> quiere {r.property_name}</span>
          <button type="button" onClick={() => onResolve(r, true)} disabled={busy} className="min-h-[36px] rounded-lg bg-emerald-600 px-3 text-xs font-semibold disabled:opacity-40">Aprobar</button>
          <button type="button" onClick={() => onAuction(r)} disabled={busy} className="min-h-[36px] rounded-lg bg-fuchsia-600 px-3 text-xs font-semibold disabled:opacity-40">Subastar</button>
          <button type="button" onClick={() => onResolve(r, false)} disabled={busy} className="min-h-[36px] rounded-lg border border-slate-600 px-3 text-xs font-semibold disabled:opacity-40">Rechazar</button>
        </div>
      ))}
    </section>
  );
}

/** Bandeja: solicitudes de abandono (aprobar eligiendo destino del dinero, o rechazar). */
export function LeaveRequestsTray({
  snap, busy, onResolve,
}: {
  snap: ActiveSnapshot; busy: boolean;
  onResolve: (r: LeaveRequest, accept: boolean, resolution: ExitResolution) => void;
}) {
  if (snap.leave_requests.length === 0) return null;
  return (
    <section aria-label="Solicitudes de abandono" className="flex flex-col gap-2 rounded-xl border border-rose-700/50 p-4">
      <h2 className="text-sm font-bold text-rose-200">Solicitudes de abandono</h2>
      {snap.leave_requests.map((r) => (
        <div key={r.request_ref} className="flex flex-wrap items-center gap-2 rounded-lg border border-slate-700 px-3 py-2 text-sm">
          <span className="flex-1 truncate"><span className="font-semibold">{r.requester_name}</span> quiere abandonar</span>
          <span className="text-[11px] text-slate-400">Destino del dinero:</span>
          <button type="button" onClick={() => onResolve(r, true, 'to_bank')} disabled={busy} className="min-h-[36px] rounded-lg bg-emerald-600 px-3 text-xs font-semibold disabled:opacity-40">Aprobar · a la banca</button>
          <button type="button" onClick={() => onResolve(r, true, 'distribute')} disabled={busy} className="min-h-[36px] rounded-lg bg-emerald-700 px-3 text-xs font-semibold disabled:opacity-40">Aprobar · repartir</button>
          <button type="button" onClick={() => onResolve(r, false, 'to_bank')} disabled={busy} className="min-h-[36px] rounded-lg border border-slate-600 px-3 text-xs font-semibold disabled:opacity-40">Rechazar</button>
        </div>
      ))}
    </section>
  );
}

/** Bandeja: solicitudes de bancarrota (aprobar / rechazar). */
export function BankruptcyRequestsTray({
  snap, busy, onResolve,
}: {
  snap: ActiveSnapshot; busy: boolean;
  onResolve: (r: BankruptcyRequest, accept: boolean) => void;
}) {
  if (snap.bankruptcy_requests.length === 0) return null;
  return (
    <section aria-label="Solicitudes de bancarrota" className="flex flex-col gap-2 rounded-xl border border-amber-700/50 p-4">
      <h2 className="text-sm font-bold text-amber-200">Solicitudes de bancarrota</h2>
      {snap.bankruptcy_requests.map((r) => (
        <div key={r.request_ref} className="flex flex-wrap items-center gap-2 rounded-lg border border-slate-700 px-3 py-2 text-sm">
          <span className="flex-1 truncate">
            <span className="font-semibold">{r.requester_name}</span>{' '}
            {r.kind === 'to_bank' ? 'frente a la banca' : <>frente a <span className="font-semibold">{r.creditor_name}</span></>}
            {r.reason && <span className="ml-1 text-[11px] text-slate-400">· {r.reason}</span>}
          </span>
          <button type="button" onClick={() => onResolve(r, true)} disabled={busy} className="min-h-[36px] rounded-lg bg-amber-600 px-3 text-xs font-semibold disabled:opacity-40">Aprobar</button>
          <button type="button" onClick={() => onResolve(r, false)} disabled={busy} className="min-h-[36px] rounded-lg border border-slate-600 px-3 text-xs font-semibold disabled:opacity-40">Rechazar</button>
        </div>
      ))}
    </section>
  );
}
