// Máquina de estados de conexión del lobby (lógica pura; el hook gestiona los temporizadores).
export type ConnStatus = 'connecting' | 'connected' | 'reconnecting' | 'disconnected' | 'offline';
export type ConnEvent = 'subscribed' | 'lost' | 'timeout' | 'online' | 'offline';

/** Solo se marca "disconnected" tras 12 s de no recuperar el canal. */
export const DISCONNECT_MS = 12_000;
/** Heartbeat aproximado. */
export const HEARTBEAT_MS = 25_000;
/** Re-sincronización periódica del snapshot (red de seguridad por si se pierde un broadcast: el
 *  anfitrión pasivo o una pestaña en segundo plano que vuelve al foco se autorreparan a tiempo). */
export const RESYNC_MS = 8_000;
/** Agrupación de señales consecutivas antes de recargar el snapshot. */
export const EVENT_DEBOUNCE_MS = 250;

/**
 * Reduce el estado de conexión ante un evento. `offline` (sin red) tiene prioridad.
 * El paso reconnecting -> disconnected lo dispara el evento 'timeout' (temporizador de 12 s).
 */
export function reduceConn(prev: ConnStatus, ev: ConnEvent, online: boolean): ConnStatus {
  if (ev === 'offline') return 'offline';
  if (!online) return 'offline';
  switch (ev) {
    case 'online':
      return prev === 'offline' ? 'connecting' : prev;
    case 'subscribed':
      return 'connected';
    case 'lost':
      // Un microcorte no marca desconectado: pasa a reconnecting (el temporizador decide).
      return prev === 'disconnected' ? 'reconnecting' : prev === 'offline' ? 'connecting' : 'reconnecting';
    case 'timeout':
      return prev === 'reconnecting' ? 'disconnected' : prev;
    default:
      return prev;
  }
}

/** Estado visual por jugador: "reconnecting" solo cuando el estado global lo es. */
export function playerPresenceStatus(global: ConnStatus, isPresent: boolean): 'connected' | 'reconnecting' | 'disconnected' {
  if (global === 'reconnecting') return 'reconnecting';
  if (global === 'connected') return isPresent ? 'connected' : 'disconnected';
  return 'disconnected';
}
