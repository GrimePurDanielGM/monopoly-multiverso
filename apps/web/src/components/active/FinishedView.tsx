import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import { currentPlayerName } from '../../lib/activeSelectors';
import { PlayerBalances } from './PlayerBalances';
import { LedgerList } from './LedgerList';

/** Pantalla de partida finalizada: resumen final, sin acciones económicas. */
export function FinishedView({ snap, icons }: { snap: ActiveSnapshot; icons: Record<string, string> }) {
  return (
    <section className="flex flex-col gap-3">
      <header className="rounded-xl border border-slate-700 bg-slate-900 p-4 text-center">
        <h1 className="text-2xl font-bold">Partida finalizada</h1>
        <p className="mt-1 text-sm text-slate-400">Sala {snap.game.code}</p>
      </header>

      <div className="rounded-xl border border-slate-700 p-4">
        <h2 className="mb-2 text-sm font-bold text-slate-200">Saldos finales</h2>
        <PlayerBalances snap={snap} icons={icons} />
        <p className="mt-3 text-sm text-slate-400">Último turno: {currentPlayerName(snap)} · turno {snap.turn.turn_number}</p>
      </div>

      <section aria-label="Movimientos" className="flex flex-col gap-2 rounded-xl border border-slate-700 p-4">
        <h2 className="text-sm font-bold text-slate-200">Movimientos recientes</h2>
        <LedgerList snap={snap} isHost={false} busy={false} onRevert={() => {}} />
      </section>
    </section>
  );
}
