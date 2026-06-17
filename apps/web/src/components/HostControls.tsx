import { useState } from 'react';
import { cancelGame, startGame, updateConfig } from '../lib/api';
import { computeStartState } from '../lib/startState';
import type { SnapCounts, SnapGame, SnapPlayer, SnapRequest } from '../lib/snapshot';
import { GameConfigForm, type ConfigPatch } from './GameConfigForm';
import { StartGamePanel } from './StartGamePanel';
import { ConfirmDialog } from './ConfirmDialog';
import { HostActionError } from './HostActionError';

interface Props {
  game: SnapGame;
  counts: SnapCounts;
  players: SnapPlayer[];
  requests: SnapRequest[];
  reload: () => Promise<void>;
}

/** Controles del anfitrión: configuración, inicio y cancelación. Solo se renderiza si soy host.
 *  Todas las acciones son autoritativas en el servidor; tras cada una se recarga el snapshot. */
export function HostControls({ game, counts, players, requests, reload }: Props) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<null | 'start' | 'cancel'>(null);

  const startState = computeStartState({ isHost: true, status: game.status, players, counts, requests });

  async function runConfig(patch: ConfigPatch) {
    setBusy(true);
    setError(null);
    const r = await updateConfig(game.id, { ...patch } as Record<string, unknown>, game.version); // versión actual del snapshot
    await reload(); // recarga autoritativa (también tras VERSION_CONFLICT); no se mezcla el patch en el store
    if (!r.ok) setError(r.message);
    setBusy(false);
  }
  async function runStart() {
    setBusy(true);
    setError(null);
    const r = await startGame(game.id, game.version);
    await reload();
    if (!r.ok) setError(r.message);
    setBusy(false);
    setConfirm(null);
  }
  async function runCancel() {
    setBusy(true);
    setError(null);
    const r = await cancelGame(game.id);
    await reload();
    if (!r.ok) setError(r.message);
    setBusy(false);
    setConfirm(null);
  }

  return (
    <section aria-label="Controles del anfitrión" className="flex flex-col gap-4 rounded-xl border border-amber-500/30 p-4">
      <h2 className="text-sm font-bold text-amber-300">Controles del anfitrión</h2>
      <HostActionError message={error} />

      <details className="rounded-lg bg-slate-800/40 p-3">
        <summary className="cursor-pointer text-sm font-medium">Configuración de la sala</summary>
        <div className="mt-3">
          <GameConfigForm
            name={game.name}
            minPlayers={counts.min_players}
            maxPlayers={counts.max_players}
            initialMoney={game.config.initial_money}
            currentPlayers={counts.player_count}
            busy={busy}
            onSubmit={runConfig}
          />
        </div>
      </details>

      <StartGamePanel state={startState} busy={busy} onStart={() => setConfirm('start')} />

      <button
        type="button"
        onClick={() => setConfirm('cancel')}
        disabled={busy}
        className="min-h-[44px] rounded-xl border border-rose-500/50 px-4 text-sm font-semibold text-rose-300 disabled:opacity-40"
      >
        Cancelar sala
      </button>

      <ConfirmDialog
        open={confirm === 'start'}
        title="Iniciar partida"
        busy={busy}
        message={
          <>
            Vais a empezar con <b>{counts.player_count}</b> jugadores, todos preparados. El orden de turnos se sorteará{' '}
            <b>una sola vez</b>. ¿Iniciar?
          </>
        }
        confirmLabel="Iniciar"
        onConfirm={() => void runStart()}
        onCancel={() => setConfirm(null)}
      />
      <ConfirmDialog
        open={confirm === 'cancel'}
        title="Cancelar sala"
        destructive
        busy={busy}
        message="Todos los jugadores perderán acceso al lobby. No es un borrado físico. ¿Cancelar la sala?"
        confirmLabel="Sí, cancelar"
        cancelLabel="Volver"
        onConfirm={() => void runCancel()}
        onCancel={() => setConfirm(null)}
      />
    </section>
  );
}
