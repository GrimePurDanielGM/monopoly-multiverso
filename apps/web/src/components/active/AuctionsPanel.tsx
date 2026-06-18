import { useState } from 'react';
import type { ActiveSnapshot, PropertyAuction } from '../../lib/activeSnapshot';
import { formatMoney, canBid, minBid, refLabel, parseAmount } from '../../lib/activeSelectors';

/** Subastas activas: puja actual visible para todos; los jugadores activos pujan; el anfitrión cierra/cancela. */
export function AuctionsPanel({
  snap,
  isHost,
  busy,
  onBid,
  onClose,
  onCancel,
}: {
  snap: ActiveSnapshot;
  isHost: boolean;
  busy: boolean;
  onBid: (a: PropertyAuction, amount: number) => void;
  onClose: (a: PropertyAuction) => void;
  onCancel: (a: PropertyAuction) => void;
}) {
  if (snap.auctions.length === 0) return null;
  return (
    <section aria-label="Subastas activas" className="flex flex-col gap-3 rounded-xl border border-fuchsia-700/50 p-4">
      <h2 className="text-sm font-bold text-fuchsia-200">Subastas activas</h2>
      {snap.auctions.map((a) => (
        <AuctionRow key={a.auction_ref} a={a} snap={snap} isHost={isHost} busy={busy} onBid={onBid} onClose={onClose} onCancel={onCancel} />
      ))}
    </section>
  );
}

function AuctionRow({
  a, snap, isHost, busy, onBid, onClose, onCancel,
}: {
  a: PropertyAuction; snap: ActiveSnapshot; isHost: boolean; busy: boolean;
  onBid: (a: PropertyAuction, amount: number) => void; onClose: (a: PropertyAuction) => void; onCancel: (a: PropertyAuction) => void;
}) {
  const [raw, setRaw] = useState('');
  const parsed = parseAmount(raw);
  const min = minBid(a);
  const valid = parsed.ok && parsed.value >= min && parsed.value <= snap.me.balance;
  const allowBid = canBid(snap);
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-slate-700 px-3 py-2">
      <div className="flex items-center justify-between gap-2 text-sm">
        <span className="truncate font-semibold">{a.property_name}</span>
        <span className="text-xs text-slate-300">
          {a.high_bid !== null ? <>Puja: {formatMoney(a.high_bid)} ({refLabel(a.high_bidder_ref, snap.players)})</> : 'Sin pujas'}
        </span>
      </div>
      {allowBid && (
        <form
          className="flex items-center gap-2"
          onSubmit={(e) => { e.preventDefault(); if (valid && parsed.ok) { onBid(a, parsed.value); setRaw(''); } }}
        >
          <label className="sr-only" htmlFor={`bid-${a.auction_ref}`}>Tu puja</label>
          <input
            id={`bid-${a.auction_ref}`}
            inputMode="numeric"
            placeholder={`mín. ${min}`}
            value={raw}
            onChange={(e) => setRaw(e.target.value)}
            className="min-h-[36px] w-28 rounded-lg border border-slate-600 bg-slate-800 px-2 text-sm"
          />
          <button type="submit" disabled={busy || !valid} className="min-h-[36px] rounded-lg bg-fuchsia-600 px-3 text-xs font-semibold disabled:opacity-40">
            Pujar
          </button>
          {raw.trim() !== '' && !valid && <span className="text-xs text-rose-300">{parsed.ok ? `Debe ser ≥ ${min} y ≤ tu saldo` : parsed.reason}</span>}
        </form>
      )}
      {isHost && (
        <div className="flex gap-2">
          <button type="button" onClick={() => onClose(a)} disabled={busy} className="min-h-[36px] flex-1 rounded-lg bg-indigo-600 px-3 text-xs font-semibold disabled:opacity-40">
            Cerrar subasta
          </button>
          <button type="button" onClick={() => onCancel(a)} disabled={busy} className="min-h-[36px] flex-1 rounded-lg border border-slate-600 px-3 text-xs font-semibold disabled:opacity-40">
            Cancelar
          </button>
        </div>
      )}
    </div>
  );
}
