import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  getActiveSnapshotByCode, listActiveTokens, endTurn, bankTransfer, playerTransfer,
  hostPlayerTransfer, hostAdjustBalance, hostSetTurn, hostRevertMovement,
  pauseGame, resumeGame, finishGame, resolveLateJoin,
  requestLeaveActive, resolveLeaveActive, removeActivePlayer,
  requestPropertyPurchase, resolvePropertyPurchase, payRent,
  startPropertyAuction, placePropertyBid, closePropertyAuction, cancelPropertyAuction,
  requestBankruptcy, resolveBankruptcy,
  movePlayer, rollAndMove, moveWithPhysicalRoll, hostSetPlayerPosition, resolveJunction,
  payJailRelease, redeemJailCard, resolveCard, payPending, payUtilityRent, setDiceMode,
  requestBuildHouse, requestBuildHotel, requestSellHouse, requestSellHotel, resolveBuildingRequest,
  mortgageProperty, unmortgageProperty,
  createTradeProposal, acceptTradeProposal, rejectTradeProposal, cancelTradeProposal, counterTradeProposal, resolveTradeProposal,
  type ApiResult, type ExitResolution, type BankruptcyKind,
} from '../lib/api';
import { useCardDraw } from '../hooks/useCardDraw';
import { CardModal } from '../components/active/CardModal';
import { useJailSounds } from '../hooks/useJailSounds';
import { useGlobalEvent } from '../hooks/useGlobalEvent';
import { GlobalBanner } from '../components/active/GlobalBanner';
import { primeSfx } from '../lib/sfx';
import { useActiveStore } from '../store/active';
import { useRealtimeStore } from '../store/realtime';
import { useLobbyStore } from '../store/lobby';
import { RecoveryRequestsTray } from '../components/RecoveryRequestsTray';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { isMyTurn, isHost, isPaused, isFinished, canAct, newRequestId } from '../lib/activeSelectors';
import { ConnectionBar } from '../components/ConnectionBar';
import { LiveRegion } from '../components/LiveRegion';
import { TurnBanner } from '../components/active/TurnBanner';
import { MoneyBanner } from '../components/active/MoneyBanner';
import { PlayerBalances } from '../components/active/PlayerBalances';
import { LedgerList } from '../components/active/LedgerList';
import { PlayerTransferForm } from '../components/active/PlayerTransferForm';
import { BankPanel } from '../components/active/BankPanel';
import { HostCorrections } from '../components/active/HostCorrections';
import { RevertDialog } from '../components/active/RevertDialog';
import { GameControlPanel, PausedBanner } from '../components/active/GameControlPanel';
import { FinishedView } from '../components/active/FinishedView';
import { LateJoinTray } from '../components/active/LateJoinTray';
import { PropertiesSummary } from '../components/active/PropertiesSummary';
import { PropertyBoardModal } from '../components/active/PropertyBoardModal';
import { MovementPanel } from '../components/active/MovementPanel';
import { BoardView } from '../components/active/BoardView';
import type { BoardKey } from '../lib/activeSnapshot';
import { PurchaseRequestsTray, LeaveRequestsTray, BankruptcyRequestsTray, BuildingRequestsTray, TradeReviewsTray } from '../components/active/HostRequestTrays';
import { TradesPanel } from '../components/active/TradesPanel';
import { RulesSummary } from '../components/active/RulesSummary';
import { CreateTradeModal, type TradeDraftInitial } from '../components/active/CreateTradeModal';
import { getTradePerspective } from '../lib/activeSelectors';
import type { TradeProposal } from '../lib/activeSnapshot';
import { BankruptcyDialog } from '../components/active/BankruptcyDialog';
import { formatMoney, ownerName } from '../lib/activeSelectors';
import { tokenEmoji } from '../lib/tokenVisual';
import { useReceiveMoney } from '../hooks/useReceiveMoney';
import { rememberGame } from '../lib/gameHistory';
import { isCashSoundEnabled, setCashSoundEnabled, primeCashSound } from '../lib/cashSound';
import type { ActiveProperty } from '../lib/activeSnapshot';

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
  const [leaveOpen, setLeaveOpen] = useState(false);
  const [tradeModal, setTradeModal] = useState<{ mode: 'create' | 'counter'; toRef?: string; tradeRef?: string; meIsFrom?: boolean; initial?: TradeDraftInitial; otherCards?: string[] } | null>(null);
  const [removeTarget, setRemoveTarget] = useState<{ ref: string; name: string } | null>(null);
  const [removeMode, setRemoveMode] = useState<ExitResolution>('to_bank');
  const [buyTarget, setBuyTarget] = useState<ActiveProperty | null>(null);
  const [rentTarget, setRentTarget] = useState<ActiveProperty | null>(null);
  const [bankruptcyOpen, setBankruptcyOpen] = useState(false);
  const [boardOpen, setBoardOpen] = useState(false);
  const [boardViewOpen, setBoardViewOpen] = useState(false);
  const [soundOn, setSoundOn] = useState<boolean>(() => isCashSoundEnabled());

  // Efecto "dinero recibido": suena + flash cuando MI saldo aumenta (no en el primer snapshot).
  const receivedFlash = useReceiveMoney(snap);
  const { show: cardShow, dismiss: dismissCard } = useCardDraw(snap);
  useJailSounds(snap);                          // sirena al entrar / puerta al salir de la cárcel
  const globalBanner = useGlobalEvent(snap);    // banner global (cobro del bote del Parking) para todos

  // Historial local: afina el estado (en curso/pausa/finalizada) y el rol con el snapshot activo.
  const histStatus = snap ? (snap.runtime_status === 'running' ? 'active' : snap.runtime_status) : null;
  const histRole = snap ? (snap.me.is_host ? 'host' : snap.me.is_spectator ? 'spectator' : 'player') : null;
  useEffect(() => {
    if (!snap || !histStatus || !histRole) return;
    rememberGame({
      code: snap.game.code,
      role: histRole,
      display_name: snap.players.find((p) => p.public_ref === snap.me.public_ref)?.display_name ?? null,
      status: histStatus,
    });
    // Solo reescribimos cuando cambia el estado/rol relevante, no en cada snapshot.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [snap?.game.code, histStatus, histRole]);
  // Desbloquear el audio dentro de la primera interacción REAL del usuario. iOS solo lo permite
  // dentro del gesto, así que escuchamos varios eventos de gesto (el primero que llegue desbloquea;
  // primeCashSound es idempotente). passive: no bloquea el scroll/tap.
  useEffect(() => {
    const unlock = () => { primeCashSound(); primeSfx(); };
    const events: (keyof WindowEventMap)[] = ['pointerdown', 'touchend', 'click'];
    events.forEach((e) => window.addEventListener(e, unlock, { once: true, passive: true }));
    return () => events.forEach((e) => window.removeEventListener(e, unlock));
  }, []);
  const toggleSound = useCallback(() => {
    setSoundOn((on) => {
      const next = !on;
      setCashSoundEnabled(next);
      if (next) primeCashSound();
      return next;
    });
  }, []);

  useEffect(() => {
    let active = true;
    void listActiveTokens().then((r) => {
      if (active && r.ok) setIcons(Object.fromEntries(r.data.map((t) => [t.id, tokenEmoji(t.icon)])));
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

  // Solicitud de abandono: si no tengo saldo ni propiedades salgo directo (y dejo de ser miembro);
  // si no, queda pendiente de aprobación del anfitrión. Recargamos para reevaluar la pantalla.
  const doLeave = useCallback(async () => {
    if (controlBusy) return;
    setControlBusy(true);
    setError(null);
    const r = await requestLeaveActive(gameId, newRequestId());
    setControlBusy(false);
    setLeaveOpen(false);
    if (r.ok) await onReload();
    else setError(r.message);
  }, [controlBusy, gameId, onReload]);

  // Declararse en bancarrota: crea solicitud (anfitrión la aprueba). Tras aprobar quedo espectador.
  const doBankruptcy = useCallback((kind: BankruptcyKind, creditorRef: string | null, reason: string) => {
    void run(() => requestBankruptcy(gameId, kind, creditorRef, reason, newRequestId())).then(() => setBankruptcyOpen(false));
  }, [gameId, run]);

  // Expulsión (anfitrión): saldo a la banca (def.) o reparto entre restantes.
  const doRemove = useCallback(() => {
    const t = removeTarget;
    if (!t) return;
    void runControl(() => removeActivePlayer(gameId, t.ref, removeMode, '', newRequestId(), snap?.runtime_version ?? 0))
      .then(() => setRemoveTarget(null));
  }, [removeTarget, removeMode, gameId, snap?.runtime_version, runControl]);

  // Solicitud de compra (jugador activo, en curso). El anfitrión la aprobará. Confirmación previa.
  const doBuy = useCallback(() => {
    const p = buyTarget;
    if (!p) return;
    void run(() => requestPropertyPurchase(gameId, p.property_ref, newRequestId())).then(() => setBuyTarget(null));
  }, [buyTarget, gameId, run]);

  // Pago de alquiler al propietario. Confirmación previa.
  const doPayRent = useCallback(() => {
    const p = rentTarget;
    if (!p) return;
    void run(() => payRent(gameId, p.property_ref, newRequestId(), snap?.runtime_version ?? 0)).then(() => setRentTarget(null));
  }, [rentTarget, gameId, snap?.runtime_version, run]);

  // Movimiento (Fase 4): tirar dados / mover manualmente (jugador actual) y corregir posición (anfitrión).
  const doRoll = useCallback(() => {
    void run(() => rollAndMove(gameId, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);
  const doMovePhysical = useCallback((d1: number, d2: number) => {
    void run(() => moveWithPhysicalRoll(gameId, d1, d2, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);
  const doMoveManual = useCallback((steps: number) => {
    void run(() => movePlayer(gameId, steps, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);
  const doPayUtilityRent = useCallback((p: ActiveProperty, d1: number | null, d2: number | null) => {
    void run(() => payUtilityRent(gameId, p.property_ref, d1, d2, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);
  // Fase 6 — construcción/venta por SOLICITUD (sin versión) e hipoteca/deshipoteca directas (con versión).
  const buildingActions = useMemo(() => {
    const reqCall = (fn: (g: string, p: string, r: string) => Promise<ApiResult<unknown>>) =>
      (p: ActiveProperty) => void run(() => fn(gameId, p.property_ref, newRequestId()));
    const dirCall = (fn: (g: string, p: string, r: string, v: number) => Promise<ApiResult<unknown>>) =>
      (p: ActiveProperty) => void run(() => fn(gameId, p.property_ref, newRequestId(), snap?.runtime_version ?? 0));
    return {
      onBuildHouse: reqCall(requestBuildHouse), onBuildHotel: reqCall(requestBuildHotel),
      onSellHouse: reqCall(requestSellHouse), onSellHotel: reqCall(requestSellHotel),
      onMortgage: dirCall(mortgageProperty), onUnmortgage: dirCall(unmortgageProperty),
    };
  }, [gameId, snap?.runtime_version, run]);
  // El anfitrión aprueba/rechaza una solicitud de construcción.
  const doResolveBuilding = useCallback((requestRef: string, accept: boolean) => {
    void run(() => resolveBuildingRequest(requestRef, accept, snap?.runtime_version ?? 0));
  }, [snap?.runtime_version, run]);

  // ── Fase 7: tratos ──
  const tradeActions = useMemo(() => ({
    onAccept: (t: TradeProposal) => void run(() => acceptTradeProposal(t.trade_ref, snap?.runtime_version ?? 0, newRequestId())),
    onReject: (t: TradeProposal) => void run(() => rejectTradeProposal(t.trade_ref, newRequestId())),
    onCancel: (t: TradeProposal) => void run(() => cancelTradeProposal(t.trade_ref, newRequestId())),
    onCounter: (t: TradeProposal) => {
      const me = snap?.me.public_ref ?? '';
      const persp = getTradePerspective(t, me);
      setTradeModal({ mode: 'counter', toRef: persp.viewerIsFrom ? t.to_ref : t.from_ref, tradeRef: t.trade_ref, meIsFrom: persp.viewerIsFrom,
        initial: { myMoney: persp.youGive.money, theirMoney: persp.youReceive.money,
          myProps: persp.youGive.properties.map((p) => p.property_ref), theirProps: persp.youReceive.properties.map((p) => p.property_ref),
          myCards: persp.youGive.cards.map((c) => c.card_ref), agreement: t.agreement_text },
        otherCards: persp.youReceive.cards.map((c) => c.card_ref) });
    },
  }), [snap?.runtime_version, snap?.me.public_ref, run]);
  const doResolveTrade = useCallback((t: TradeProposal, accept: boolean) => {
    void run(() => resolveTradeProposal(t.trade_ref, accept, snap?.runtime_version ?? 0));
  }, [snap?.runtime_version, run]);
  const doResolveJunction = useCallback((dir: 'own' | 'cross') => {
    void run(() => resolveJunction(gameId, dir, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);
  // Fase 5 — casillas especiales.
  const doPayJailRelease = useCallback(() => {
    void run(() => payJailRelease(gameId, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);
  const doUseJailCard = useCallback(() => {
    void run(() => redeemJailCard(gameId, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);
  const doResolveCard = useCallback(() => {
    void run(() => resolveCard(gameId, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);
  const doPayPending = useCallback(() => {
    void run(() => payPending(gameId, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);
  const doSetPosition = useCallback((ref: string, board: BoardKey, index: number, reason: string) => {
    void run(() => hostSetPlayerPosition(gameId, ref, board, index, reason, newRequestId(), snap?.runtime_version ?? 0));
  }, [gameId, snap?.runtime_version, run]);

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
      <MoneyBanner flash={receivedFlash} />
      <GlobalBanner banner={globalBanner} />
      {cardShow && <CardModal show={cardShow} busy={busy} onAccept={dismissCard} onResolve={doResolveCard} />}
      <ConnectionBar status={channelStatus} onRetry={onReconnect} />

      <header className="rounded-xl border border-slate-700 p-4">
        <h1 className="text-lg font-bold">Partida {snap.game.code}</h1>
        <p className="mt-1 text-sm text-slate-400">Banco digital · {snap.players.length} jugadores</p>
      </header>

      {paused && <PausedBanner />}
      {snap.me.is_spectator && (
        <p role="status" className="rounded-xl border border-amber-700/60 bg-amber-950/40 px-4 py-3 text-sm text-amber-100">
          Estás en bancarrota. Puedes seguir consultando la partida como espectador.
        </p>
      )}

      <div className="lg:grid lg:grid-cols-2 lg:items-start lg:gap-5">
        <div className="flex flex-col gap-3">
          <TurnBanner snap={snap} />
          {canAct(snap) && !snap.me.is_spectator && isMyTurn(snap) && (
            <button
              type="button"
              onClick={() => void run(() => endTurn(gameId, ver, newRequestId()))}
              disabled={busy}
              className="min-h-[44px] rounded-xl bg-emerald-600 px-4 text-base font-semibold disabled:opacity-40"
            >
              {busy ? 'Procesando…' : 'Finalizar turno'}
            </button>
          )}
          <PlayerBalances
            snap={snap}
            icons={icons}
            isHost={host}
            disabled={controlBusy}
            onLeave={() => setLeaveOpen(true)}
            onRemove={(ref, name) => { setRemoveMode('to_bank'); setRemoveTarget({ ref, name }); }}
          />
          {/* Declararse en bancarrota: jugador activo (no anfitrión, no espectador). */}
          {!host && !snap.me.is_spectator && (
            <button
              type="button"
              onClick={() => setBankruptcyOpen(true)}
              disabled={busy || snap.runtime_status === 'finished'}
              className="min-h-[40px] rounded-xl border border-amber-700 px-4 text-sm font-semibold text-amber-200 disabled:opacity-40"
            >
              Declararme en bancarrota
            </button>
          )}
          {error && <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">{error}</p>}
          <MovementPanel
            snap={snap}
            busy={busy}
            onRoll={doRoll}
            onMovePhysical={doMovePhysical}
            onMoveManual={doMoveManual}
            onResolveJunction={doResolveJunction}
            onPayJailRelease={doPayJailRelease}
            onUseJailCard={doUseJailCard}
            onPayPending={doPayPending}
            onOpenBoard={() => setBoardViewOpen(true)}
            onRequestPurchase={(p) => setBuyTarget(p)}
            onPayRent={(p) => setRentTarget(p)}
            onPayUtilityRent={doPayUtilityRent}
            buildingActions={buildingActions}
          />
          <PropertiesSummary snap={snap} onOpenBoard={() => setBoardOpen(true)} buildingActions={buildingActions} busy={busy} />
          <TradesPanel snap={snap} onCreate={() => setTradeModal({ mode: 'create' })} actions={tradeActions} />
          <RulesSummary config={snap.game.config} />
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
          {host && <PurchaseRequestsTray snap={snap} busy={busy}
            onResolve={(r, accept) => void run(() => resolvePropertyPurchase(r.request_ref, accept, ver))}
            onAuction={(r) => void run(() => startPropertyAuction(gameId, r.property_ref, newRequestId(), ver))} />}
          {host && <BuildingRequestsTray snap={snap} busy={busy} onResolve={(r, accept) => doResolveBuilding(r.request_ref, accept)} />}
          {host && <TradeReviewsTray snap={snap} busy={busy} onResolve={doResolveTrade} />}
          {host && <LeaveRequestsTray snap={snap} busy={busy}
            onResolve={(r, accept, resolution) => void run(() => resolveLeaveActive(r.request_ref, accept, resolution, ver))} />}
          {host && <BankruptcyRequestsTray snap={snap} busy={busy}
            onResolve={(r, accept) => void run(() => resolveBankruptcy(r.request_ref, accept, ver))} />}
          {host && <LateJoinTray snap={snap} icons={icons} busy={controlBusy} onResolve={(ref, accept) => void runControl(() => resolveLateJoin(ref, accept, ver))} />}
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
                onHostTransfer={(f, t, amt, reason) => void run(() => hostPlayerTransfer(gameId, f, t, amt, reason, newRequestId(), ver))}
                onSetPosition={doSetPosition}
                onSetDiceMode={(mode) => void run(() => setDiceMode(gameId, mode, newRequestId(), ver))} />
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
            <label className="mt-1 flex items-center gap-2 text-xs text-slate-400">
              <input type="checkbox" checked={soundOn} onChange={toggleSound} className="h-4 w-4" />
              Sonido al recibir dinero
            </label>
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

      <ConfirmDialog
        open={leaveOpen}
        title="Abandonar partida"
        destructive
        busy={controlBusy}
        message={<>¿Seguro que quieres abandonar la partida?<br />Si tienes saldo o propiedades, el anfitrión deberá aprobar tu salida y decidir el destino del dinero; tus propiedades volverán a la banca.</>}
        confirmLabel="Sí, solicitar abandono"
        cancelLabel="No, seguir jugando"
        onConfirm={() => void doLeave()}
        onCancel={() => setLeaveOpen(false)}
      />

      <ConfirmDialog
        open={removeTarget !== null}
        title="Sacar jugador"
        destructive
        busy={controlBusy}
        message={
          <div className="flex flex-col gap-3">
            <p>
              ¿Seguro que quieres sacar a <span className="font-semibold">{removeTarget?.name}</span> de la partida?
              <br />Su saldo se resolverá según la opción seleccionada y dejará de participar.
            </p>
            <fieldset className="flex flex-col gap-2 border-0 p-0">
              <legend className="mb-1 text-xs font-semibold text-slate-200">Destino del saldo</legend>
              <label className="flex items-center gap-2">
                <input
                  type="radio"
                  name="exit-resolution"
                  value="to_bank"
                  checked={removeMode === 'to_bank'}
                  disabled={controlBusy}
                  onChange={() => setRemoveMode('to_bank')}
                />
                <span>Devolver a la banca</span>
              </label>
              <label className="flex items-center gap-2">
                <input
                  type="radio"
                  name="exit-resolution"
                  value="distribute"
                  checked={removeMode === 'distribute'}
                  disabled={controlBusy}
                  onChange={() => setRemoveMode('distribute')}
                />
                <span>Repartir entre jugadores restantes</span>
              </label>
            </fieldset>
          </div>
        }
        confirmLabel="Sí, sacar jugador"
        cancelLabel="Cancelar"
        onConfirm={doRemove}
        onCancel={() => setRemoveTarget(null)}
      />

      <ConfirmDialog
        open={buyTarget !== null}
        title="Solicitar compra"
        busy={busy}
        message={buyTarget ? <>¿Solicitar comprar <span className="font-semibold">{buyTarget.name}</span> por {formatMoney(buyTarget.price)}?<br />El anfitrión deberá aprobarla.</> : ''}
        confirmLabel="Solicitar compra"
        cancelLabel="Cancelar"
        onConfirm={doBuy}
        onCancel={() => setBuyTarget(null)}
      />

      <ConfirmDialog
        open={rentTarget !== null}
        title="Pagar alquiler"
        busy={busy}
        message={rentTarget ? <>¿Pagar {formatMoney(rentTarget.rent_due ?? rentTarget.base_rent)} de alquiler a <span className="font-semibold">{ownerName(rentTarget, snap)}</span> por <span className="font-semibold">{rentTarget.name}</span>?</> : ''}
        confirmLabel="Pagar alquiler"
        cancelLabel="Cancelar"
        onConfirm={doPayRent}
        onCancel={() => setRentTarget(null)}
      />

      <BankruptcyDialog
        open={bankruptcyOpen}
        snap={snap}
        busy={busy}
        onConfirm={doBankruptcy}
        onCancel={() => setBankruptcyOpen(false)}
      />

      {boardOpen && (
        <PropertyBoardModal
          snap={snap}
          isHost={host}
          busy={busy}
          onClose={() => setBoardOpen(false)}
          onRequestPurchase={(p) => setBuyTarget(p)}
          onPayRent={(p) => setRentTarget(p)}
          onBid={(a, amount) => void run(() => placePropertyBid(gameId, a.auction_ref, amount, newRequestId(), ver))}
          onCloseAuction={(a) => void run(() => closePropertyAuction(gameId, a.auction_ref, newRequestId(), ver))}
          onCancelAuction={(a) => void run(() => cancelPropertyAuction(gameId, a.auction_ref, '', newRequestId(), ver))}
          buildingActions={buildingActions}
        />
      )}

      {boardViewOpen && (
        <BoardView
          snap={snap}
          onClose={() => setBoardViewOpen(false)}
          onRequestPurchase={(p) => { setBoardViewOpen(false); setBuyTarget(p); }}
          buildingActions={buildingActions}
          busy={busy}
        />
      )}
      {tradeModal && (
        <CreateTradeModal
          snap={snap}
          busy={busy}
          mode={tradeModal.mode}
          fixedToRef={tradeModal.toRef}
          meIsFrom={tradeModal.meIsFrom ?? true}
          initial={tradeModal.initial}
          otherCards={tradeModal.otherCards}
          onClose={() => setTradeModal(null)}
          onSubmit={(toRef, terms) => {
            const m = tradeModal;
            setTradeModal(null);
            if (m.mode === 'counter' && m.tradeRef) void run(() => counterTradeProposal(m.tradeRef!, terms, newRequestId()));
            else void run(() => createTradeProposal(gameId, toRef, terms, newRequestId()));
          }}
        />
      )}
    </section>
  );
}
