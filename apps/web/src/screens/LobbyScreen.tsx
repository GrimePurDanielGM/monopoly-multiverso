import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  chooseToken,
  getLobbySnapshotByCode,
  listActiveTokens,
  setReady,
  type PublicToken,
} from '../lib/api';
import { ensureAnonSession } from '../lib/session';
import { normalizeCode } from '../lib/codes';
import { useLobbyStore } from '../store/lobby';
import { useRealtimeStore } from '../store/realtime';
import { canSetReady, isMe, takenTokenIds } from '../lib/lobbySelectors';
import { playerPresenceStatus } from '../lib/connState';
import { useLobbyRealtime } from '../hooks/useLobbyRealtime';
import { TokenPicker } from '../components/TokenPicker';
import { ConnectionBar, PresenceDot } from '../components/ConnectionBar';

const STATUS_LABEL: Record<string, string> = {
  lobby: 'En sala de espera',
  active: 'Partida en curso',
  cancelled: 'Cancelada',
};

/** Sala sincronizada (Bloque 3): snapshot autoritativo + Realtime (broadcast/presence/heartbeat). */
export function LobbyScreen() {
  const { code: codeParam = '' } = useParams();
  const code = normalizeCode(codeParam);

  const game = useLobbyStore((s) => s.game);
  const players = useLobbyStore((s) => s.players);
  const me = useLobbyStore((s) => s.me);
  const counts = useLobbyStore((s) => s.counts);
  const snapshotStatus = useLobbyStore((s) => s.snapshotStatus);
  const error = useLobbyStore((s) => s.error);
  const replaceSnapshot = useLobbyStore((s) => s.replaceSnapshot);
  const setStatus = useLobbyStore((s) => s.setStatus);
  const setError = useLobbyStore((s) => s.setError);

  const channelStatus = useRealtimeStore((s) => s.channelStatus);
  const presentPublicRefs = useRealtimeStore((s) => s.presentPublicRefs);

  const [tokens, setTokens] = useState<PublicToken[]>([]);
  const [actionBusy, setActionBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  // Carga "ruidosa" (inicial / manual): muestra estado de carga.
  const load = useCallback(async () => {
    setStatus('loading');
    setActionError(null);
    const session = await ensureAnonSession();
    if (session !== 'ready') {
      setError('error', session === 'unconfigured' ? 'La app no está configurada.' : 'No se pudo iniciar sesión.');
      return;
    }
    const r = await getLobbySnapshotByCode(code);
    if (!r.ok) {
      setError(r.code === 'NOT_ACTIVE_MEMBER' ? 'not_member' : 'error', r.message);
      return;
    }
    replaceSnapshot(r.data, Date.now());
    const tk = await listActiveTokens(r.data.game.config.token_catalog_version);
    if (tk.ok) setTokens(tk.data);
  }, [code, replaceSnapshot, setStatus, setError]);

  // Resync "silencioso" (disparado por eventos Realtime / foreground): sin parpadeo de carga.
  // Errores transitorios NO borran el snapshot; solo NOT_ACTIVE_MEMBER cambia el estado.
  const resync = useCallback(async () => {
    const r = await getLobbySnapshotByCode(code);
    if (r.ok) replaceSnapshot(r.data, Date.now());
    else if (r.code === 'NOT_ACTIVE_MEMBER') setError('not_member', r.message);
  }, [code, replaceSnapshot, setError]);

  useEffect(() => {
    void load();
  }, [load]);

  // Limpieza del estado de transporte al salir de la sala.
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

  // --- Estados sin sala cargada ---
  if (snapshotStatus === 'not_member') {
    return (
      <section className="flex flex-col gap-4">
        <h1 className="text-xl font-bold">Sala {code}</h1>
        <p role="alert" className="rounded-lg bg-slate-800 px-3 py-2 text-sm text-slate-200">
          {error ?? 'No formas parte de esta sala.'}
        </p>
        <Link to="/unirse" className="rounded-xl bg-indigo-600 px-4 py-3 text-center text-base font-semibold">
          Unirse a la partida
        </Link>
        <p className="text-xs text-slate-500">
          Si ya jugabas en esta sala desde otro dispositivo, la recuperación de jugador llegará en un bloque posterior.
        </p>
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
    return (
      <section className="flex flex-1 flex-col items-center justify-center gap-3 text-center">
        <h1 className="text-2xl font-bold">La partida ha comenzado</h1>
        <p className="text-sm text-slate-400">Sala {game.code}</p>
      </section>
    );
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
                {tk ? tk.icon : '·'}
              </span>
              <span className="flex-1 truncate text-sm">
                {p.name}
                {host && <span className="ml-2 text-xs text-amber-300">Anfitrión</span>}
                {mine && <span className="ml-2 rounded bg-indigo-600 px-1 text-[10px] font-semibold">Tú</span>}
              </span>
              <span className={`text-xs font-medium ${p.status === 'ready' ? 'text-emerald-400' : 'text-slate-400'}`}>
                {p.status === 'ready' ? 'Preparado' : 'No preparado'}
              </span>
            </li>
          );
        })}
      </ul>

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
          className={`rounded-xl px-4 py-3 text-base font-semibold disabled:opacity-40 ${
            meIsReady ? 'border border-slate-600' : 'bg-indigo-600'
          }`}
        >
          {actionBusy ? 'Guardando…' : meIsReady ? 'Marcar No preparado' : 'Marcar Preparado'}
        </button>

        <button type="button" onClick={() => void load()} className="text-sm text-slate-400 underline">
          Recargar sala
        </button>
      </div>
    </section>
  );
}
