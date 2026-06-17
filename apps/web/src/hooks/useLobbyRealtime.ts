// Orquestación Realtime del lobby: canal privado room:<CODE>, Presence (solo public_ref),
// heartbeat, reconexión y segundo plano. El snapshot sigue siendo la ÚNICA fuente
// autoritativa: los eventos solo disparan una recarga (resync). Guarda de generación para
// ignorar callbacks de suscripciones antiguas y limpieza total al desmontar/cambiar de sala.
import { useCallback, useEffect, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { heartbeat } from '../lib/api';
import { ensureAnonSession } from '../lib/session';
import { roomTopic } from '../lib/codes';
import { createDebouncer } from '../lib/debounce';
import { filterPresentRefs, presenceRefsFromState } from '../lib/presence';
import { reduceConn, DISCONNECT_MS, HEARTBEAT_MS, EVENT_DEBOUNCE_MS, type ConnEvent } from '../lib/connState';
import { useRealtimeStore } from '../store/realtime';

const OFFICIAL_EVENTS = ['lobby_changed', 'game_started', 'game_cancelled', 'recovery_requested'] as const;

interface Params {
  code: string;
  gameId: string | null;
  myPublicRef: string | null;
  knownRefs: Set<string>;
  resync: () => Promise<void>;
}

export function useLobbyRealtime({ code, gameId, myPublicRef, knownRefs, resync }: Params): { reconnect: () => void } {
  // El callback de resync y los public_ref conocidos cambian con cada snapshot:
  // los mantenemos en refs para NO re-suscribir el canal en cada recarga.
  const resyncRef = useRef(resync);
  const knownRef = useRef(knownRefs);
  const reconnectRef = useRef<() => void>(() => {});
  resyncRef.current = resync;
  knownRef.current = knownRefs;

  useEffect(() => {
    const sb = supabase;
    if (!sb || !gameId || !code || !myPublicRef) return;

    // Guarda de generación por efecto: ignora callbacks de esta suscripción tras limpiarla.
    let cancelled = false;
    const isCurrent = () => !cancelled;
    const rt = useRealtimeStore.getState;

    let channel: ReturnType<typeof sb.channel> | null = null;
    let disconnectTimer: ReturnType<typeof setTimeout> | undefined;

    const clearDisconnect = () => {
      if (disconnectTimer !== undefined) {
        clearTimeout(disconnectTimer);
        disconnectTimer = undefined;
      }
    };

    const doResync = async () => {
      await resyncRef.current();
      if (isCurrent()) rt().markSync(Date.now());
    };
    const debouncer = createDebouncer(() => {
      if (isCurrent()) void doResync();
    }, EVENT_DEBOUNCE_MS);

    const dispatch = (ev: ConnEvent) => {
      if (!isCurrent()) return;
      const next = reduceConn(rt().channelStatus, ev, navigator.onLine);
      rt().setChannelStatus(next);
      if (next === 'reconnecting' && disconnectTimer === undefined) {
        disconnectTimer = setTimeout(() => dispatch('timeout'), DISCONNECT_MS);
      }
      if (next === 'connected' || next === 'offline') clearDisconnect();
    };

    const updatePresence = () => {
      if (!channel || !isCurrent()) return;
      rt().setPresence(filterPresentRefs(presenceRefsFromState(channel.presenceState()), knownRef.current));
    };

    const connect = () => {
      if (channel) {
        sb.removeChannel(channel);
        channel = null;
      }
      rt().setChannelStatus('connecting');
      const ch = sb.channel(roomTopic(code), { config: { private: true, presence: { key: myPublicRef } } });
      for (const ev of OFFICIAL_EVENTS) {
        ch.on('broadcast', { event: ev }, () => {
          if (!isCurrent()) return;
          rt().markEvent(Date.now());
          debouncer.call(); // agrupa señales consecutivas sin perder la última
        });
      }
      ch.on('presence', { event: 'sync' }, updatePresence);
      ch.subscribe((status) => {
        if (!isCurrent()) return;
        if (status === 'SUBSCRIBED') {
          dispatch('subscribed');
          rt().setTransportError(null);
          void ch.track({ public_ref: myPublicRef }); // Presence: SOLO public_ref
          void doResync();
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          dispatch('lost');
        }
      });
      channel = ch;
    };

    const foreground = async () => {
      if (!isCurrent()) return;
      rt().setVisible(true);
      const session = await ensureAnonSession();
      if (!isCurrent()) return;
      if (session !== 'ready') return;
      const token = (await sb.auth.getSession()).data.session?.access_token;
      if (!isCurrent()) return;
      if (token) await sb.realtime.setAuth(token);
      connect(); // teardown + recreate: nunca canales duplicados
    };

    const onOnline = () => {
      dispatch('online');
      void foreground();
    };
    const onOffline = () => dispatch('offline');
    const onVisibility = () => {
      if (document.visibilityState === 'visible') void foreground();
      else rt().setVisible(false);
    };
    const onPageShow = () => void foreground();

    reconnectRef.current = () => void foreground(); // reintento manual desde la UI

    window.addEventListener('online', onOnline);
    window.addEventListener('offline', onOffline);
    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('pageshow', onPageShow);

    const hb = setInterval(() => {
      if (!isCurrent()) return;
      if (!navigator.onLine || document.hidden) return; // no heartbeat offline / oculto
      void heartbeat(gameId); // fallos transitorios NO borran el snapshot
    }, HEARTBEAT_MS);

    rt().setVisible(document.visibilityState === 'visible');
    if (!navigator.onLine) rt().setChannelStatus('offline');
    else connect();

    return () => {
      cancelled = true; // invalida callbacks de esta suscripción
      clearDisconnect();
      clearInterval(hb);
      debouncer.cancel();
      window.removeEventListener('online', onOnline);
      window.removeEventListener('offline', onOffline);
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('pageshow', onPageShow);
      if (channel) sb.removeChannel(channel);
      reconnectRef.current = () => {};
    };
  }, [code, gameId, myPublicRef]);

  return { reconnect: useCallback(() => reconnectRef.current(), []) };
}
