// Lógica pura de la partida activa: turnos, importes, permisos y formato. Sin estado ni red.
import type { ActiveSnapshot, ActivePlayer, ActiveProperty, LedgerEntry, LedgerKind } from './activeSnapshot';

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

/** Movimientos estructurales no revertibles desde la UI (semillas, reversiones, salidas y propiedades). */
const NON_REVERTIBLE: ReadonlySet<LedgerKind> = new Set<LedgerKind>([
  'seed', 'late_join_seed', 'host_revert',
  'player_exit_to_bank', 'player_exit_distribution', 'player_exit_remainder_to_bank',
  'property_purchase', 'rent_payment',
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
  property_purchase: 'Compra de propiedad',
  rent_payment: 'Pago de alquiler',
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

// ── Propiedades (Fase 3) ─────────────────────────────────────────────────────────
export type PropertyStatus = 'mine' | 'available' | 'owned' | 'not_buyable';

/** Estado de una propiedad respecto al jugador local. */
export function propertyStatus(p: ActiveProperty, snap: ActiveSnapshot): PropertyStatus {
  if (p.owner_ref && p.owner_ref === snap.me.public_ref) return 'mine';
  if (p.owner_ref) return 'owned';
  if (!p.is_buyable) return 'not_buyable';
  return 'available';
}

/** ¿Puedo comprar esta propiedad ahora? (en curso, comprable, libre y con saldo). */
export function canBuyProperty(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return canAct(snap) && p.is_buyable && p.owner_ref === null && snap.me.balance >= p.price;
}

/** ¿Puedo pagar el alquiler de esta propiedad? (en curso, de otro jugador, con alquiler y saldo). */
export function canPayRent(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return (
    canAct(snap) && p.owner_ref !== null && p.owner_ref !== snap.me.public_ref &&
    p.base_rent > 0 && snap.me.balance >= p.base_rent
  );
}

/** Nombre del propietario (o "Banca" si está libre / "—" si no se encuentra). */
export function ownerName(p: ActiveProperty, snap: ActiveSnapshot): string {
  if (p.owner_ref === null) return 'Banca';
  return snap.players.find((x) => x.public_ref === p.owner_ref)?.display_name ?? p.owner_ref;
}

/** Propiedades que posee el jugador local. */
export function myProperties(snap: ActiveSnapshot): ActiveProperty[] {
  return snap.properties.filter((p) => p.owner_ref === snap.me.public_ref);
}

/** Número de propiedades activas por jugador (public_ref -> cantidad). */
export function propertyCountByPlayer(snap: ActiveSnapshot): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const p of snap.properties) {
    if (p.owner_ref) counts[p.owner_ref] = (counts[p.owner_ref] ?? 0) + 1;
  }
  return counts;
}

/** Propiedades de un jugador concreto. */
export function propertiesOf(ref: string, snap: ActiveSnapshot): ActiveProperty[] {
  return snap.properties.filter((p) => p.owner_ref === ref);
}

export const BOARD_LABEL: Record<string, string> = {
  classic: 'Clásico',
  back_to_the_future: 'Regreso al futuro',
};

/** Propiedades agrupadas por tablero, preservando el orden del snapshot. */
export function propertiesByBoard(snap: ActiveSnapshot): { board: string; label: string; items: ActiveProperty[] }[] {
  const order: string[] = [];
  const map = new Map<string, ActiveProperty[]>();
  for (const p of snap.properties) {
    if (!map.has(p.board_key)) { map.set(p.board_key, []); order.push(p.board_key); }
    map.get(p.board_key)!.push(p);
  }
  return order.map((board) => ({ board, label: BOARD_LABEL[board] ?? board, items: map.get(board)! }));
}
