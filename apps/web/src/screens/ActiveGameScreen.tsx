import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  getActiveSnapshotByCode, listActiveTokens, endTurn, bankTransfer, playerTransfer,
  hostPlayerTransfer, hostAdjustBalance, hostSetTurn, hostRevertMovement,
  pauseGame, resumeGame, finishGame, type ApiResult,
} from '../lib/api';
import { useActiveStore } from '../store/active';
import { useRealtimeStore } from '../store/realtime';
import { useLobbyStore } from '../store/lobby';
import { RecoveryRequestsTray } from '../components/RecoveryRequestsTray';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { isMyTurn, isHost, isPaused, isFinished, canAct, newRequestId } from '../lib/activeSelectors';
import { ConnectionBar } from '../components/ConnectionBar';
import { LiveRegion } from '../components/LiveRegion';
import { TurnBanner } from '../components/active/TurnBanner';
import { PlayerBalances } from '../components/active/PlayerBalances';
import { LedgerList } from '../components/active/LedgerList';
import { PlayerTransferForm } from '../components/active/PlayerTransferForm';
import { BankPanel } from '../components/active/BankPanel';
import { HostCorrections } from '../components/active/HostCorrections';
import { RevertDialog } from '../components/active/RevertDialog';
import { GameControlPanel, PausedBanner } from '../components/active/GameControlPanel';
import { FinishedView } from '../components/active/FinishedView';

/** Pantalla de partida activa (Fase 2). El snapshot del store es la única fuente de verdad;
 *  cada acción usa runtime_version (concurrencia) y un requestId nuevo (idempotencia). */
export function ActiveGameScreen({
  code,
  gameId,
  onReload,
  onReconnect,
}: {
  code: string;
  gameId: string;
  onReload: () => Promise<void>;
  onReconnect: () => void;
}) {
  const snap = useActiveStore((s) => s.snap);
  const replaceActive = useActiveStore((s) => s.replaceActive);
  const channelStatus = useRealtimeStore((s) => s.channelStatus);
  const requests = useLobbyStore((s) => s.requests);
  const lobbyPlayers = useLobbyStore((s) => s.players);

  const [icons, setIcons] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [revertRef, setRevertRef] = useState<string | null>(null);
  const [controlBusy, setControlBusy] = useState(false);
  const [pauseOpen, setPauseOpen] = useState(false);
  const [finishOpen, setFinishOpen] = useState(false);
  const [reloading, setReloading] = useState(false);
  const [reloadErr, setReloadErr] = useState<string | null>(null);
  const [reloadMsg, setReloadMsg] = useState('');

  useEffect(() => {
    let active = true;
    void listActiveTokens().then((r) => {
      if (active && r.ok) setIcons(Object.fromEntries(r.data.map((t) => [t.id, t.icon])));
    });
    return () => { active = false; };
  }, []);

  const refresh = useCallback(async () => {
    const r = await getActiveSnapshotByCode(code);
    if (r.ok) replaceActive(r.data);
    return r.ok;
  }, [code, replaceActive]);

  useEffect(() => { void refresh(); }, [refresh]);

  // "Recargar partida": reconecta el canal si está caído, recarga el snapshot autoritativo,
  // con feedback accesible, sin recargar la página ni crear sesión nueva. Evita doble pulsación.
  const doReload = useCallback(async () => {
    if (reloading) return;
    setReloading(true);
    setReloadErr(null);
    setReloadMsg('Recargando…');
    if (channelStatus !== 'connected') onReconnect();
    const ok = await refresh();
    if (ok) setReloadMsg('Partida actualizada.');
    else { setReloadMsg(''); setReloadErr('No se pudo recargar. Reintenta.'); }
    setReloading(false);
  }, [reloading, channelStatus, onReconnect, refresh]);

  // Acción económica/de turno: evita doble envío; refresca tras completar.
  const run = useCallback(
    async (fn: () => Promise<ApiResult<unknown>>) => {
      if (busy) return;
      setBusy(true);
      setError(null);
      const r = await fn();
      if (!r.ok) setError(r.message);
      await refresh();
      setBusy(false);
    },
    [busy, refresh],
  );

  // Acción de control (pausa/reanudar/finalizar): independiente, evita doble envío.
  const runControl = useCallback(
    async (fn: () => Promise<ApiResult<unknown>>) => {
      if (controlBusy) return;
      setControlBusy(true);
      setError(null);
      const r = await fn();
      if (!r.ok) setError(r.message);
      await refresh();
      setControlBusy(false);
    },
    [controlBusy, refresh],
  );

  const ver = snap?.runtime_version ?? 0;
  const host = useMemo(() => (snap ? isHost(snap) : false), [snap]);

  if (!snap) {
    return (
      <section className="flex flex-1 items-center justify-center">
        <p role="status" className="text-sm text-slate-400">Cargando partida…</p>
      </section>
    );
  }

  if (isFinished(snap)) {
    return <FinishedView snap={snap} icons={icons} />;
  }

  const paused = isPaused(snap);

  return (
    <section className="flex flex-col gap-3">
      <ConnectionBar status={channelStatus} onRetry={onReconnect} />

      <header className="rounded-xl border border-slate-700 p-4">
        <h1 className="text-lg font-bold">Partida {snap.game.code}</h1>
        <p className="mt-1 text-sm text-slate-400">Banco digital · {snap.players.length} jugadores</p>
      </header>

      {paused && <PausedBanner />}

      <div className="lg:grid lg:grid-cols-2 lg:items-start lg:gap-5">
        <div className="flex flex-col gap-3">
          <TurnBanner snap={snap} />
          {canAct(snap) && isMyTurn(snap) && (
            <button
              type="button"
              onClick={() => void run(() => endTurn(gameId, ver, newRequestId()))}
              disabled={busy}
              className="min-h-[44px] rounded-xl bg-emerald-600 px-4 text-base font-semibold disabled:opacity-40"
            >
              {busy ? 'Procesando…' : 'Finalizar turno'}
            </button>
          )}
          <PlayerBalances snap={snap} icons={icons} />
          {error && <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">{error}</p>}
        </div>

        <div className="mt-3 flex flex-col gap-3 lg:mt-0">
          {host && (
            <GameControlPanel
              snap={snap}
              busy={controlBusy}
              onPause={() => setPauseOpen(true)}
              onResume={() => void runControl(() => resumeGame(gameId, newRequestId(), ver))}
              onFinish={() => setFinishOpen(true)}
            />
          )}
          {host && <RecoveryRequestsTray requests={requests} players={lobbyPlayers} reload={onReload} />}
          {/* En pausa, fieldset deshabilita TODAS las acciones de forma accesible sin alterar etiquetas. */}
          <fieldset disabled={paused} className="m-0 flex min-w-0 flex-col gap-3 border-0 p-0">
            <PlayerTransferForm snap={snap} busy={busy} onTransfer={(to, amt) => void run(() => playerTransfer(gameId, to, amt, newRequestId(), ver))} />
            {host && (
              <BankPanel snap={snap} busy={busy}
                onBank={(ref, dir, amt) => void run(() => bankTransfer(gameId, ref, dir, amt, newRequestId(), ver))} />
            )}
            {host && (
              <HostCorrections snap={snap} busy={busy}
                onAdjust={(t, b, reason) => void run(() => hostAdjustBalance(gameId, t, b, reason, newRequestId(), ver))}
                onSetTurn={(t, reason) => void run(() => hostSetTurn(gameId, t, reason, newRequestId(), ver))}
                onHostTransfer={(f, t, amt, reason) => void run(() => hostPlayerTransfer(gameId, f, t, amt, reason, newRequestId(), ver))} />
            )}
          </fieldset>
          <section aria-label="Movimientos" className="flex flex-col gap-2 rounded-xl border border-slate-700 p-4">
            <h2 className="text-sm font-bold text-slate-200">Movimientos recientes</h2>
            <LedgerList snap={snap} isHost={host && !paused} busy={busy} onRevert={(ref) => setRevertRef(ref)} />
          </section>

          <div className="flex flex-col gap-1">
            <button
              type="button"
              onClick={() => void doReload()}
              disabled={reloading}
              className="min-h-[44px] rounded-xl border border-slate-600 px-4 text-sm font-semibold disabled:opacity-40"
            >
              {reloading ? 'Recargando…' : 'Recargar partida'}
            </button>
            {reloadErr && (
              <p role="alert" className="text-xs text-rose-300">
                {reloadErr}{' '}
                <button type="button" onClick={() => void doReload()} className="underline">Reintentar</button>
              </p>
            )}
            <LiveRegion message={reloadMsg} tone="success" />
          </div>
        </div>
      </div>

      <LiveRegion message={busy ? 'Procesando operación…' : ''} tone="info" />

      <RevertDialog
        open={revertRef !== null}
        busy={busy}
        onCancel={() => setRevertRef(null)}
        onConfirm={(reason) => {
          const ref = revertRef;
          setRevertRef(null);
          if (ref) void run(() => hostRevertMovement(gameId, ref, reason, newRequestId(), ver));
        }}
      />

      <ConfirmDialog
        open={pauseOpen}
        title="Pausar partida"
        busy={controlBusy}
        message="Mientras esté pausada, nadie podrá hacer turnos ni movimientos hasta que la reanudes."
        confirmLabel="Pausar"
        onConfirm={() => void runControl(() => pauseGame(gameId, '', newRequestId(), ver)).then(() => setPauseOpen(false))}
        onCancel={() => setPauseOpen(false)}
      />

      <ConfirmDialog
        open={finishOpen}
        title="Finalizar partida"
        destructive
        busy={controlBusy}
        message={<>¿Estás seguro de que quieres finalizar la partida?<br />Esta acción impedirá realizar nuevos turnos, transferencias o movimientos.</>}
        confirmLabel="Sí, finalizar partida"
        cancelLabel="No, continuar jugando"
        onConfirm={() => void runControl(() => finishGame(gameId, '', newRequestId(), ver)).then(() => setFinishOpen(false))}
        onCancel={() => setFinishOpen(false)}
      />
    </section>
  );
}
