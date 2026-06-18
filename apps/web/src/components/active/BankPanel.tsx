import { useState } from 'react';
import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { parseAmount } from '../../lib/activeSelectors';

/** Banca del anfitrión: pagar a un jugador o cobrarle (banco↔jugador). */
export function BankPanel({
  snap,
  busy,
  onBank,
}: {
  snap: ActiveSnapshot;
  busy: boolean;
  onBank: (playerRef: string, direction: 'to_player' | 'from_player', amount: number) => void;
}) {
  const [ref, setRef] = useState(snap.players[0]?.public_ref ?? '');
  const [amount, setAmount] = useState('');
  const parsed = parseAmount(amount);
  const canDo = !!ref && parsed.ok && !busy;

  return (
    <section aria-label="Banca del anfitrión" className="flex flex-col gap-2 rounded-xl border border-amber-500/30 p-4">
      <h3 className="text-sm font-bold text-amber-300">Banca</h3>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-400">Jugador</span>
        <select value={ref} onChange={(e) => setRef(e.target.value)} className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base">
          {snap.players.map((p) => (
            <option key={p.public_ref} value={p.public_ref}>{p.display_name}</option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-400">Importe</span>
        <input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="numeric" autoComplete="off" placeholder="0"
          className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
      </label>
      {amount.trim() !== '' && !parsed.ok && <p className="text-xs text-amber-300">{parsed.reason}</p>}
      <div className="flex gap-2">
        <button type="button" disabled={!canDo} onClick={() => parsed.ok && onBank(ref, 'to_player', parsed.value)}
          className="min-h-[44px] flex-1 rounded-xl bg-emerald-600 px-3 text-sm font-semibold disabled:opacity-40">
          Pagar al jugador
        </button>
        <button type="button" disabled={!canDo} onClick={() => parsed.ok && onBank(ref, 'from_player', parsed.value)}
          className="min-h-[44px] flex-1 rounded-xl border border-rose-500/60 px-3 text-sm font-semibold text-rose-300 disabled:opacity-40">
          Cobrar al jugador
        </button>
      </div>
    </section>
  );
}
