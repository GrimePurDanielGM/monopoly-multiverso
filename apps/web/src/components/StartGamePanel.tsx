import type { StartState } from '../lib/startState';

/** Indicadores de inicio + botón. La autoridad final es start_game (el botón solo anticipa). */
export function StartGamePanel({ state, busy, onStart }: { state: StartState; busy: boolean; onStart: () => void }) {
  return (
    <div className="flex flex-col gap-2">
      <ul className="space-y-0.5 text-xs text-slate-400">
        <li>
          Jugadores: {state.playerCount}/{state.minPlayers} mínimo {state.enoughPlayers ? '✓' : '— faltan'}
        </li>
        <li>
          Preparados: {state.readyCount}/{state.playerCount} {state.allReady ? '✓' : ''}
        </li>
        {state.withoutToken > 0 && <li className="text-amber-300">{state.withoutToken} sin ficha</li>}
        {state.pendingRequests > 0 && <li className="text-amber-300">{state.pendingRequests} solicitudes pendientes</li>}
      </ul>
      <button
        type="button"
        onClick={onStart}
        disabled={!state.canStart || busy}
        className="min-h-[44px] rounded-xl bg-emerald-600 px-4 text-sm font-semibold disabled:opacity-40"
      >
        {busy ? 'Iniciando…' : 'Iniciar partida'}
      </button>
    </div>
  );
}
