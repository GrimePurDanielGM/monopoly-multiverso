import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  chooseToken,
  getActiveSnapshotByCode,
  getLobbySnapshotByCode,
  getMyStatus,
  kickPlayer,
  listActiveTokens,
  peekGame,
  setReady,
  type PublicToken,
} from '../lib/api';
import { useActiveStore } from '../store/active';
import { ActiveGameScreen } from './ActiveGameScreen';
import { ensureAnonSession } from '../lib/session';
import { rememberGame, statusFromLobby } from '../lib/gameHistory';
import type { LobbySnapshot } from '../lib/snapshot';
import { tokenEmoji } from '../lib/tokenVisual';
import { normalizeCode } from '../lib/codes';
import { useLobbyStore } from '../store/lobby';
import { useRealtimeStore } from '../store/realtime';
import { canSetReady, isMe, takenTokenIds } from '../lib/lobbySelectors';
import { playerPresenceStatus } from '../lib/connState';
import type { SnapPlayer } from '../lib/snapshot';
import { useLobbyRealtime } from '../hooks/useLobbyRealtime';
import { TokenPicker } from '../components/TokenPicker';
import { ConnectionBar, PresenceDot } from '../components/ConnectionBar';
import { HostControls } from '../components/HostControls';
import { HostActionError } from '../components/HostActionError';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { RecoveryRequestsTray } from '../components/RecoveryRequestsTray';
import { ReentryForm } from '../components/ReentryForm';
import { SharePanel } from '../components/SharePanel';

const STATUS_LABEL: Record<string, string> = {
  lobby: 'En sala de espera',
  active: 'Partida en curso',
  cancelled: 'Cancelada',
};

/** Apunta esta partida en el historial local (saneado) a partir del snapshot de sala. Cubre de forma
 *  uniforme todas las vías de entrada (crear/unirse/recuperar/late-join/volver), pues todas pasan por aquí. */
function recordLobbyHistory(s: LobbySnapshot): void {
  const meName = s.players.find((p) => p.public_ref === s.me.public_ref)?.name ?? null;
  rememberGame({
    code: s.game.code,
    role: s.me.is_host ? 'host' : 'player',
    display_name: meName,
    status: statusFromLobby(s.game.status),
    game_title: s.game.name,
  });
}

/** Sala sincronizada (Bloque 4): + controles del anfitrión, expulsión, configuración, cancelación, inicio. */
export function LobbyScreen() {
  const { code: codeParam = '' } = useParams();
  const code = normalizeCode(codeParam);

  const game = useLobbyStore((s) => s.game);
  const players = useLobbyStore((s) => s.players);
  const me = useLobbyStore((s) => s.me);
  const counts = useLobbyStore((s) => s.counts);
  const requests = useLobbyStore((s) => s.requests);
  const snapshotStatus = useLobbyStore((s) => s.snapshotStatus);
  const error = useLobbyStore((s) => s.error);
  const replaceSnapshot = useLobbyStore((s) => s.replaceSnapshot);
  const setStatus = useLobbyStore((s) => s.setStatus);
  const setError = useLobbyStore((s) => s.setError);

  const channelStatus = useRealtimeStore((s) => s.channelStatus);
  const presentPublicRefs = useRealtimeStore((s) => s.presentPublicRefs);
  const replaceActive = useActiveStore((s) => s.replaceActive);

  // Cuando la partida está activa, trae también el snapshot económico/turno (Fase 2).
  const loadActiveIfNeeded = useCallback(
    async (status: string) => {
      if (status !== 'active') return;
      const a = await getActiveSnapshotByCode(code);
      if (a.ok) replaceActive(a.data);
    },
    [code, replaceActive],
  );

  const [tokens, setTokens] = useState<PublicToken[]>([]);
  const [actionBusy, setActionBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [kickTarget, setKickTarget] = useState<SnapPlayer | null>(null);
  const [kickBusy, setKickBusy] = useState(false);
  const [kickError, setKickError] = useState<string | null>(null);
  const [roomStatus, setRoomStatus] = useState<string | null>(null); // estado de la sala para no-miembros

  // Distingue expulsado de no-miembro consultando my_status con el game_id previo.
  const applyNotMember = useCallback(
    async (prevGameId: string | null) => {
      if (prevGameId) {
        const ms = await getMyStatus(prevGameId);
        if (ms.ok && ms.data === 'kicked') {
          setError('kicked', 'Has sido expulsado de la sala.');
          return;
        }
      }
      // Para no-miembros, el estado de la sala decide las acciones (unirse vs recuperar).
      const pk = await peekGame(code);
      setRoomStatus(pk.ok ? pk.data.status : null);
      setError('not_member', 'No formas parte de esta sala.');
    },
    [code, setError],
  );

  const load = useCallback(async () => {
    const prevGameId = useLobbyStore.getState().game?.id ?? null;
    setStatus('loading');
    setActionError(null);
    const session = await ensureAnonSession();
    if (session !== 'ready') {
      setError('error', session === 'unconfigured' ? 'La app no está configurada.' : 'No se pudo iniciar sesión.');
      return;
    }
    const r = await getLobbySnapshotByCode(code);
    if (!r.ok) {
      if (r.code === 'NOT_ACTIVE_MEMBER') return applyNotMember(prevGameId);
      setError('error', r.message);
      return;
    }
    replaceSnapshot(r.data, Date.now());
    recordLobbyHistory(r.data);
    const tk = await listActiveTokens(r.data.game.config.token_catalog_version);
    if (tk.ok) setTokens(tk.data);
    await loadActiveIfNeeded(r.data.game.status);
  }, [code, replaceSnapshot, setStatus, setError, applyNotMember, loadActiveIfNeeded]);

  // Resync silencioso (eventos Realtime / foreground): sin parpadeo; errores transitorios no borran el snapshot.
  const resync = useCallback(async () => {
    const prevGameId = useLobbyStore.getState().game?.id ?? null;
    const r = await getLobbySnapshotByCode(code);
    if (r.ok) {
      replaceSnapshot(r.data, Date.now());
      recordLobbyHistory(r.data);
      await loadActiveIfNeeded(r.data.game.status);
    } else if (r.code === 'NOT_ACTIVE_MEMBER') await applyNotMember(prevGameId);
  }, [code, replaceSnapshot, applyNotMember, loadActiveIfNeeded]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => () => useRealtimeStore.getState().reset(), []);

  const knownRefs = useMemo(() => new Set(players.map((p) => p.public_ref)), [players]);
  const { reconnect } = useLobbyRealtime({
    code,
    gameId: game?.id ?? null,
    myPublicRef: me?.public_ref ?? null,
    knownRefs,
    resync,
  });

  const onChoose = useCallback(
    async (tokenId: string) => {
      if (!game || actionBusy) return;
      setActionBusy(true);
      setActionError(null);
      const r = await chooseToken(game.id, tokenId);
      await load();
      if (!r.ok) setActionError(r.message);
      setActionBusy(false);
    },
    [game, actionBusy, load],
  );

  const onToggleReady = useCallback(async () => {
    if (!game || !me || actionBusy) return;
    const next = me.join_status !== 'ready';
    if (!canSetReady(me, next)) {
      setActionError('Elige una ficha antes de marcarte como preparado.');
      return;
    }
    setActionBusy(true);
    setActionError(null);
    const r = await setReady(game.id, next);
    await load();
    if (!r.ok) setActionError(r.message);
    setActionBusy(false);
  }, [game, me, actionBusy, load]);

  const onKick = useCallback(async () => {
    if (!game || !kickTarget || kickBusy) return;
    setKickBusy(true);
    setKickError(null);
    const r = await kickPlayer(game.id, kickTarget.public_ref); // por public_ref, nunca id interno
    await load();
    if (!r.ok) setKickError(r.message);
    setKickBusy(false);
    setKickTarget(null);
  }, [game, kickTarget, kickBusy, load]);

  // --- Estado: expulsado -> puede solicitar reentrada ---
  if (snapshotStatus === 'kicked') {
    return (
      <section className="flex flex-col gap-4">
        <h1 className="text-xl font-bold">Has sido expulsado de esta sala</h1>
        <p className="text-sm text-slate-400">Puedes solicitar volver a entrar; el anfitrión debe aprobarlo.</p>
        <ReentryForm code={code} onApproved={() => void load()} />
        <div className="flex gap-2">
          <Link to="/" className="rounded-lg border border-slate-600 px-4 py-2 text-sm font-semibold">
            Inicio
          </Link>
          <Link to="/unirse" className="rounded-lg border border-slate-600 px-4 py-2 text-sm font-semibold">
            Unirse a otra
          </Link>
        </div>
      </section>
    );
  }

  if (snapshotStatus === 'not_member') {
    const active = roomStatus === 'active';
    return (
      <section className="flex flex-col gap-4">
        <h1 className="text-xl font-bold">Sala {code}</h1>
        <p role="alert" className="rounded-lg bg-slate-800 px-3 py-2 text-sm text-slate-200">
          {active ? 'Esta partida ya ha comenzado. Si ya formabas parte, recupera tu jugador.' : (error ?? 'No formas parte de esta sala.')}
        </p>
        {/* En partida activa no se puede unir: la vía es recuperar el jugador existente. */}
        <Link to={`/sala/${code}/recuperar-jugador`} className="rounded-xl bg-indigo-600 px-4 py-3 text-center text-base font-semibold">
          Recuperar mi jugador
        </Link>
        {active ? (
          <Link to="/recuperar" className="rounded-xl border border-slate-600 px-4 py-3 text-center text-base font-semibold">
            Recuperar partida como anfitrión
          </Link>
        ) : (
          <Link to="/unirse" className="rounded-xl border border-slate-600 px-4 py-3 text-center text-base font-semibold">
            Unirse a la partida
          </Link>
        )}
      </section>
    );
  }

  if (!game || !me || !counts) {
    if (snapshotStatus === 'error') {
      return (
        <section className="flex flex-col gap-4">
          <h1 className="text-xl font-bold">Sala {code}</h1>
          <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
            {error ?? 'No se pudo cargar la sala.'}
          </p>
          <button type="button" onClick={() => void load()} className="rounded-xl border border-slate-600 px-4 py-3 text-base font-semibold">
            Reintentar
          </button>
        </section>
      );
    }
    return (
      <section className="flex flex-1 items-center justify-center">
        <p role="status" className="text-sm text-slate-400">
          Cargando sala…
        </p>
      </section>
    );
  }

  // --- Sala cargada ---
  if (game.status === 'cancelled') {
    return (
      <section className="flex flex-1 flex-col items-center justify-center gap-3 text-center">
        <h1 className="text-xl font-bold">La partida ha sido cancelada</h1>
        <Link to="/" className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold">
          Volver al inicio
        </Link>
      </section>
    );
  }
  if (game.status === 'active') {
    return <ActiveGameScreen code={code} gameId={game.id} onReload={load} onReconnect={reconnect} />;
  }

  // lobby interactivo
  const taken = takenTokenIds(players);
  const meIsReady = me.join_status === 'ready';
  const readyDisabled = actionBusy || !canSetReady(me, !meIsReady);

  return (
    <section className="flex flex-col gap-3">
      <ConnectionBar status={channelStatus} onRetry={reconnect} />

      <header className="rounded-xl border border-slate-700 p-4">
        <div className="flex items-center justify-between">
          <h1 className="text-lg font-bold">{game.name}</h1>
          {me.is_host && (
            <span className="rounded-full bg-amber-500/20 px-2 py-0.5 text-xs font-semibold text-amber-300">Anfitrión</span>
          )}
        </div>
        <p className="mt-1 text-sm text-slate-400">
          Código <span className="font-semibold tracking-[0.2em] text-slate-200">{game.code}</span> ·{' '}
          {STATUS_LABEL[game.status] ?? game.status}
        </p>
      </header>

      <div className="lg:grid lg:grid-cols-2 lg:items-start lg:gap-5">
        <div className="flex flex-col gap-3">
      <div className="grid grid-cols-3 gap-2 text-center">
        <div className="rounded-lg bg-slate-800 p-2">
          <p className="text-lg font-bold">{counts.player_count}/{counts.max_players}</p>
          <p className="text-[11px] text-slate-400">Jugadores</p>
        </div>
        <div className="rounded-lg bg-slate-800 p-2">
          <p className="text-lg font-bold">{counts.ready_count}/{counts.player_count}</p>
          <p className="text-[11px] text-slate-400">Preparados</p>
        </div>
        <div className="rounded-lg bg-slate-800 p-2">
          <p className="text-lg font-bold">{counts.min_players}</p>
          <p className="text-[11px] text-slate-400">Mínimo</p>
        </div>
      </div>

      {me.is_host && <HostActionError message={kickError} />}

      <ul className="flex flex-col gap-2">
        {players.map((p) => {
          const tk = tokens.find((t) => t.id === p.token_id);
          const host = p.public_ref === game.host_public_ref;
          const mine = isMe(p, me);
          const presence = playerPresenceStatus(channelStatus, presentPublicRefs.includes(p.public_ref));
          return (
            <li
              key={p.public_ref}
              className={`flex items-center gap-3 rounded-lg border px-3 py-2 ${mine ? 'border-indigo-500 bg-indigo-950/40' : 'border-slate-700'}`}
            >
              <PresenceDot status={presence} />
              <span aria-hidden className="text-2xl leading-none">
                {tk ? tokenEmoji(tk.icon) : '·'}
              </span>
              <span className="flex-1 truncate text-sm">
                {p.name}
                {host && <span className="ml-2 text-xs text-amber-300">Anfitrión</span>}
                {mine && <span className="ml-2 rounded bg-indigo-600 px-1 text-[10px] font-semibold">Tú</span>}
              </span>
              <span className={`text-xs font-medium ${p.status === 'ready' ? 'text-emerald-400' : 'text-slate-400'}`}>
                {p.status === 'ready' ? 'Preparado' : 'No preparado'}
              </span>
              {me.is_host && !host && (
                <button
                  type="button"
                  onClick={() => setKickTarget(p)}
                  aria-label={`Expulsar a ${p.name}`}
                  className="min-h-[36px] rounded-lg border border-rose-500/50 px-2 text-xs font-semibold text-rose-300"
                >
                  Expulsar
                </button>
              )}
            </li>
          );
        })}
      </ul>
        </div>

        <div className="mt-3 flex flex-col gap-3 lg:mt-0">
          <SharePanel code={game.code} />

      <div className="flex flex-col gap-3 rounded-xl border border-slate-700 p-4">
        <p className="text-sm font-medium text-slate-300">Tu ficha</p>
        <TokenPicker tokens={tokens} takenIds={taken} selectedId={me.token_id} disabled={actionBusy} onSelect={onChoose} />

        {actionError && (
          <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
            {actionError}
          </p>
        )}

        <button
          type="button"
          onClick={() => void onToggleReady()}
          disabled={readyDisabled}
          className={`min-h-[44px] rounded-xl px-4 text-base font-semibold disabled:opacity-40 ${
            meIsReady ? 'border border-slate-600' : 'bg-indigo-600'
          }`}
        >
          {actionBusy ? 'Guardando…' : meIsReady ? 'Marcar No preparado' : 'Marcar Preparado'}
        </button>

        <button type="button" onClick={() => void load()} className="text-sm text-slate-400 underline">
          Recargar sala
        </button>
      </div>

      {me.is_host && <RecoveryRequestsTray requests={requests} players={players} reload={load} />}
      {me.is_host && <HostControls game={game} counts={counts} players={players} requests={requests} reload={load} />}
        </div>
      </div>

      <ConfirmDialog
        open={kickTarget !== null}
        title="Expulsar jugador"
        destructive
        busy={kickBusy}
        message={<>¿Expulsar a <b>{kickTarget?.name}</b> de la sala?</>}
        confirmLabel="Expulsar"
        onConfirm={() => void onKick()}
        onCancel={() => setKickTarget(null)}
      />
    </section>
  );
}
