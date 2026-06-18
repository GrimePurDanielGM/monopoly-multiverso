import { useState } from 'react';
import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { parseAmount, canAfford, formatMoney } from '../../lib/activeSelectors';

/** Transferencia del jugador local a otro (permitida en cualquier momento). */
export function PlayerTransferForm({
  snap,
  busy,
  onTransfer,
}: {
  snap: ActiveSnapshot;
  busy: boolean;
  onTransfer: (toRef: string, amount: number) => void;
}) {
  const others = snap.players.filter((p) => p.public_ref !== snap.me.public_ref);
  const [to, setTo] = useState(others[0]?.public_ref ?? '');
  const [amount, setAmount] = useState('');
  const parsed = parseAmount(amount);
  const afford = parsed.ok && canAfford(snap.me.balance, parsed.value);
  const canSend = !!to && parsed.ok && afford && !busy;

  return (
    <form
      className="flex flex-col gap-2 rounded-xl border border-slate-700 p-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (canSend && parsed.ok) onTransfer(to, parsed.value);
      }}
    >
      <p className="text-sm font-medium text-slate-300">Pagar a otro jugador</p>
      <p className="text-xs text-slate-500">Tu saldo: {formatMoney(snap.me.balance)}</p>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-400">Destinatario</span>
        <select
          value={to}
          onChange={(e) => setTo(e.target.value)}
          className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base"
        >
          {others.map((p) => (
            <option key={p.public_ref} value={p.public_ref}>{p.display_name}</option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-400">Importe</span>
        <input
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          inputMode="numeric"
          autoComplete="off"
          placeholder="0"
          className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base"
        />
      </label>
      {amount.trim() !== '' && !parsed.ok && <p className="text-xs text-amber-300">{parsed.reason}</p>}
      {parsed.ok && !afford && <p className="text-xs text-amber-300">Saldo insuficiente.</p>}
      <button
        type="submit"
        disabled={!canSend}
        className="min-h-[44px] rounded-xl bg-indigo-600 px-4 text-sm font-semibold disabled:opacity-40"
      >
        {busy ? 'Enviando…' : 'Enviar'}
      </button>
    </form>
  );
}
