import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from './supabase';

/**
 * Prueba de Realtime de Fase 0 — SOLO Broadcast (sin tablas, sin Postgres
 * Changes, sin lógica de juego). Cubre: conexión, envío/recepción en el mismo
 * cliente, desconexión, reconexión con el mismo identificador lógico y un
 * segundo evento. Timeout explícito por fase y limpieza total al terminar.
 */

export type RealtimeStep =
  | 'idle'
  | 'connecting'
  | 'connected'
  | 'event-roundtrip'
  | 'disconnected'
  | 'reconnecting'
  | 'recovered'
  | 'error';

export interface RealtimeEventPayload {
  id: string;
  timestamp: string;
  counter: number;
}

export interface RealtimeProbeResult {
  step: RealtimeStep;
  lastEvent: RealtimeEventPayload | null;
  log: string[];
}

const EVENT_NAME = 'fase0-ping';
const PHASE_TIMEOUT_MS = 5000;
const RECONNECT_DELAY_MS = 500;

/** Promesa con timeout que SIEMPRE limpia su temporizador (sin promesas colgadas). */
function withTimeout<T>(promise: Promise<T>, ms: number, phase: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`timeout (${ms} ms) en ${phase}`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  });
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Espera a SUBSCRIBED; rechaza ante error/cierre. No reenvía tras quedar resuelta. */
function waitSubscribed(channel: RealtimeChannel, phase: string): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    let settled = false;
    channel.subscribe((status, err) => {
      if (settled) return;
      if (status === 'SUBSCRIBED') {
        settled = true;
        resolve();
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        settled = true;
        reject(new Error(`${phase}: estado ${status}${err ? ` (${err.message})` : ''}`));
      }
    });
  });
}

/**
 * Crea un canal con el listener de broadcast registrado ANTES de suscribirse.
 * `broadcast.self = true` es lo que permite recibir el propio evento (la causa
 * del bloqueo anterior). `waitEvent()` resuelve con el siguiente evento recibido.
 */
function makeChannel(
  client: NonNullable<typeof supabase>,
  name: string,
): { channel: RealtimeChannel; waitEvent: () => Promise<RealtimeEventPayload> } {
  const channel = client.channel(name, { config: { broadcast: { self: true } } });
  let resolver: ((p: RealtimeEventPayload) => void) | null = null;
  channel.on('broadcast', { event: EVENT_NAME }, ({ payload }) => {
    if (resolver) {
      const r = resolver;
      resolver = null;
      r(payload as RealtimeEventPayload);
    }
  });
  const waitEvent = () =>
    new Promise<RealtimeEventPayload>((resolve) => {
      resolver = resolve;
    });
  return { channel, waitEvent };
}

export async function runRealtimeProbe(
  onUpdate: (r: RealtimeProbeResult) => void,
): Promise<RealtimeProbeResult> {
  const log: string[] = [];
  let lastEvent: RealtimeEventPayload | null = null;
  let counter = 0;
  const created: RealtimeChannel[] = [];
  // Identificador lógico único, reutilizado en la reconexión.
  const logicalId = `fase0-probe-${Math.random().toString(36).slice(2, 10)}`;

  const push = (step: RealtimeStep, msg: string) => {
    log.push(msg);
    onUpdate({ step, lastEvent, log: [...log] });
  };

  const client = supabase;
  if (!client) {
    push('error', 'Supabase no configurado (faltan VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY).');
    return { step: 'error', lastEvent, log };
  }

  try {
    // 1) Conexión
    push('connecting', '1) Conectando…');
    const c1 = makeChannel(client, logicalId);
    created.push(c1.channel);
    await withTimeout(waitSubscribed(c1.channel, 'suscripción inicial'), PHASE_TIMEOUT_MS, 'suscripción inicial');
    push('connected', '1) Conectado.');

    // 2) Envío y recepción en el mismo cliente
    push('event-roundtrip', '2) Enviando evento…');
    const wait1 = c1.waitEvent();
    counter += 1;
    await c1.channel.send({
      type: 'broadcast',
      event: EVENT_NAME,
      payload: { id: crypto.randomUUID(), timestamp: new Date().toISOString(), counter },
    });
    lastEvent = await withTimeout(wait1, PHASE_TIMEOUT_MS, 'recepción del evento');
    push('event-roundtrip', '2) Evento recibido.');

    // Eliminar canal -> desconexión
    await client.removeChannel(c1.channel);
    created.splice(created.indexOf(c1.channel), 1);
    push('disconnected', '3) Desconectado.');

    // Esperar brevemente
    await delay(RECONNECT_DELAY_MS);

    // 4) Reconexión con el mismo identificador lógico
    push('reconnecting', '4) Reconectando…');
    const c2 = makeChannel(client, logicalId);
    created.push(c2.channel);
    await withTimeout(waitSubscribed(c2.channel, 'resuscripción'), PHASE_TIMEOUT_MS, 'resuscripción');
    push('reconnecting', '4) Reconectado.');

    // 5) Segundo evento tras reconexión
    const wait2 = c2.waitEvent();
    counter += 1;
    await c2.channel.send({
      type: 'broadcast',
      event: EVENT_NAME,
      payload: { id: crypto.randomUUID(), timestamp: new Date().toISOString(), counter },
    });
    lastEvent = await withTimeout(wait2, PHASE_TIMEOUT_MS, 'recepción posterior a reconexión');
    push('recovered', '5) Evento posterior a reconexión recibido.');
    push('recovered', 'Prueba completada correctamente.');

    return { step: 'recovered', lastEvent, log };
  } catch (e) {
    const paso = log.length > 0 ? log[log.length - 1] : '(inicio)';
    push('error', `Error en "${paso}": ${e instanceof Error ? e.message : String(e)}`);
    return { step: 'error', lastEvent, log };
  } finally {
    // Limpiar TODOS los canales que sigan abiertos.
    for (const ch of created) {
      try {
        await client.removeChannel(ch);
      } catch {
        /* limpieza best-effort */
      }
    }
  }
}
