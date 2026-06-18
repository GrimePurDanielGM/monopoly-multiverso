// Lógica pura de la partida activa: turnos, importes, permisos y formato. Sin estado ni red.
import type { ActiveSnapshot, ActivePlayer, LedgerEntry, LedgerKind } from './activeSnapshot';

export const MAX_AMOUNT = 10_000_000; // tope por operación (espejo del backend)
export const MAX_BALANCE = 1_000_000_000_000;

/** ¿Es el turno del jugador local? */
export function isMyTurn(snap: ActiveSnapshot): boolean {
  return snap.me.is_current;
}

export const isRunning = (s: ActiveSnapshot): boolean => s.runtime_status === 'running';
export const isPaused = (s: ActiveSnapshot): boolean => s.runtime_status === 'paused';
export const isFinished = (s: ActiveSnapshot): boolean => s.runtime_status === 'finished';
/** ¿Se pueden ejecutar acciones económicas/de turno? (solo en curso). */
export const canAct = (s: ActiveSnapshot): boolean => s.runtime_status === 'running';

/** ¿El jugador local es el anfitrión (banca/correcciones)? */
export function isHost(snap: ActiveSnapshot): boolean {
  return snap.me.is_host;
}

/** Nombre del jugador actual (para la cabecera de turno). */
export function currentPlayerName(snap: ActiveSnapshot): string {
  const p = snap.players.find((x) => x.public_ref === snap.turn.current_player_ref);
  return p?.display_name ?? snap.turn.current_player_ref;
}

export type AmountResult = { ok: true; value: number } | { ok: false; reason: string };

/** Valida un importe introducido por el usuario: entero, 1..MAX_AMOUNT. */
export function parseAmount(raw: string): AmountResult {
  const t = raw.trim();
  if (t === '') return { ok: false, reason: 'Introduce un importe.' };
  if (!/^\d+$/.test(t)) return { ok: false, reason: 'Solo números enteros, sin decimales.' };
  const n = Number(t);
  if (!Number.isSafeInteger(n) || n <= 0) return { ok: false, reason: 'El importe debe ser mayor que 0.' };
  if (n > MAX_AMOUNT) return { ok: false, reason: `Máximo ${formatMoney(MAX_AMOUNT)} por operación.` };
  return { ok: true, value: n };
}

/** Valida un saldo objetivo (ajuste del anfitrión): entero, 0..MAX_BALANCE. */
export function parseBalance(raw: string): AmountResult {
  const t = raw.trim();
  if (t === '') return { ok: false, reason: 'Introduce un saldo.' };
  if (!/^\d+$/.test(t)) return { ok: false, reason: 'Solo números enteros, sin decimales.' };
  const n = Number(t);
  if (!Number.isSafeInteger(n) || n < 0) return { ok: false, reason: 'El saldo no puede ser negativo.' };
  if (n > MAX_BALANCE) return { ok: false, reason: 'Saldo demasiado alto.' };
  return { ok: true, value: n };
}

/** ¿El jugador puede pagar ese importe? */
export function canAfford(balance: number, amount: number): boolean {
  return amount > 0 && balance >= amount;
}

/** Motivo válido para correcciones del anfitrión: 3..500 tras recortar. */
export function isValidReason(reason: string): boolean {
  const t = reason.trim();
  return t.length >= 3 && t.length <= 500;
}

/** ¿El ajuste de saldo sería un no-op (mismo saldo)? */
export function isNoopAdjust(current: number, next: number): boolean {
  return current === next;
}

/** Movimientos estructurales no revertibles desde la UI (semillas, reversiones y salidas). */
const NON_REVERTIBLE: ReadonlySet<LedgerKind> = new Set<LedgerKind>([
  'seed', 'late_join_seed', 'host_revert',
  'player_exit_to_bank', 'player_exit_distribution', 'player_exit_remainder_to_bank',
]);

/** ¿El movimiento puede revertirse desde la UI? (semillas, reversiones y salidas no). */
export function isRevertible(entry: LedgerEntry): boolean {
  return !NON_REVERTIBLE.has(entry.kind) && entry.reverts_ref === null;
}

const KIND_LABEL: Record<LedgerKind, string> = {
  seed: 'Saldo inicial',
  late_join_seed: 'Saldo inicial (entrada tardía)',
  bank_to_player: 'Banco paga',
  player_to_bank: 'Pago al banco',
  player_to_player: 'Transferencia',
  host_player_transfer: 'Ajuste de transferencia',
  host_adjust: 'Ajuste de saldo',
  host_revert: 'Reversión',
  player_exit_to_bank: 'Salida: saldo a la banca',
  player_exit_distribution: 'Salida: reparto a jugador',
  player_exit_remainder_to_bank: 'Salida: resto a la banca',
};
export function kindLabel(kind: LedgerKind): string {
  return KIND_LABEL[kind];
}

/** Formatea un importe entero con separador de miles (.) y la marca monetaria.
 *  Agrupación manual y determinista (no depende de ICU/locale del entorno). */
export function formatMoney(n: number): string {
  const grouped = Math.trunc(Math.abs(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return `${n < 0 ? '-' : ''}${grouped} ₥`;
}

/** Etiqueta de un extremo de movimiento ('Banco' si es null). */
export function refLabel(ref: string | null, players: ActivePlayer[]): string {
  if (ref === null) return 'Banco';
  return players.find((p) => p.public_ref === ref)?.display_name ?? ref;
}

/** Genera un id de operación para idempotencia (uno por intento). */
export function newRequestId(): string {
  return crypto.randomUUID();
}
