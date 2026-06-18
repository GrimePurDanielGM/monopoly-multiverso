import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { formatMoney } from '../../lib/activeSelectors';

/** Lista de jugadores con saldo visible para todos, ficha, indicador de turno y "Tú". */
export function PlayerBalances({ snap, icons }: { snap: ActiveSnapshot; icons: Record<string, string> }) {
  return (
    <ul aria-label="Saldos de los jugadores" className="flex flex-col gap-2">
      {snap.players.map((p) => {
        const mine = p.public_ref === snap.me.public_ref;
        return (
          <li
            key={p.public_ref}
            className={`flex items-center gap-3 rounded-lg border px-3 py-2 ${
              p.is_current ? 'border-emerald-500 bg-emerald-950/30' : mine ? 'border-indigo-500 bg-indigo-950/40' : 'border-slate-700'
            }`}
          >
            <span aria-hidden className="text-2xl leading-none">{p.token_id ? icons[p.token_id] ?? '·' : '·'}</span>
            <span className="flex-1 truncate text-sm">
              {p.display_name}
              {mine && <span className="ml-2 rounded bg-indigo-600 px-1 text-[10px] font-semibold">Tú</span>}
              {p.is_current && <span className="ml-2 text-xs text-emerald-400">en turno</span>}
            </span>
            <span className="text-sm font-semibold tabular-nums">{formatMoney(p.balance)}</span>
          </li>
        );
      })}
    </ul>
  );
}
