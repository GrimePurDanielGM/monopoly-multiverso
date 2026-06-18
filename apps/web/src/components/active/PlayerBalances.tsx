import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { formatMoney } from '../../lib/activeSelectors';

/** Lista de jugadores con saldo visible para todos, ficha, indicador de turno y "Tú".
 *  Acciones de salida por fila: "Abandonar partida" (mi propia fila, si no soy anfitrión)
 *  y "Sacar jugador" (solo el anfitrión, sobre otros jugadores). No se muestran a no-anfitriones
 *  sobre otros, ni sobre la fila del anfitrión (no puede salir sin dejar la partida sin control). */
export function PlayerBalances({
  snap,
  icons,
  isHost = false,
  disabled = false,
  onLeave,
  onRemove,
}: {
  snap: ActiveSnapshot;
  icons: Record<string, string>;
  isHost?: boolean;
  disabled?: boolean;
  onLeave?: () => void;
  onRemove?: (ref: string, name: string) => void;
}) {
  return (
    <ul aria-label="Saldos de los jugadores" className="flex flex-col gap-2">
      {snap.players.map((p) => {
        const mine = p.public_ref === snap.me.public_ref;
        const canLeave = mine && !isHost && onLeave;            // mi jugador (no anfitrión)
        const canRemove = isHost && !mine && onRemove;          // el anfitrión saca a otro
        return (
          <li
            key={p.public_ref}
            className={`flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg border px-3 py-2 ${
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
            {canLeave && (
              <button
                type="button"
                onClick={onLeave}
                disabled={disabled}
                className="min-h-[36px] basis-full rounded-lg border border-rose-700 px-3 text-xs font-semibold text-rose-200 disabled:opacity-40 sm:basis-auto"
              >
                Abandonar partida
              </button>
            )}
            {canRemove && (
              <button
                type="button"
                onClick={() => onRemove(p.public_ref, p.display_name)}
                disabled={disabled}
                className="min-h-[36px] basis-full rounded-lg border border-rose-700 px-3 text-xs font-semibold text-rose-200 disabled:opacity-40 sm:basis-auto"
              >
                Sacar jugador
              </button>
            )}
          </li>
        );
      })}
    </ul>
  );
}
