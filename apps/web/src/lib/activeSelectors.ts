// Lógica pura de la partida activa: turnos, importes, permisos y formato. Sin estado ni red.
import type {
  ActiveSnapshot, ActivePlayer, ActiveProperty, LedgerEntry, LedgerKind,
  BoardKey, BoardSpace, PlayerPosition, SpaceType,
} from './activeSnapshot';

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
  'property_purchase', 'rent_payment', 'property_auction_purchase',
  'bankruptcy_cash_to_bank', 'bankruptcy_cash_to_player',
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
  property_auction_purchase: 'Compra en subasta',
  bankruptcy_cash_to_bank: 'Bancarrota: efectivo a la banca',
  bankruptcy_cash_to_player: 'Bancarrota: efectivo al acreedor',
  pass_start_bonus: 'Bonus por pasar por salida',
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

// ── Propiedades (Fase 3 corrección) ──────────────────────────────────────────────
export type PropertyStatus = 'mine' | 'available' | 'owned' | 'not_buyable' | 'in_auction';

/** ¿Puede actuar el jugador local? (en curso y NO espectador/bancarrota). */
export const canActAsMe = (s: ActiveSnapshot): boolean => canAct(s) && !s.me.is_spectator;

/** Estado de una propiedad respecto al jugador local. */
export function propertyStatus(p: ActiveProperty, snap: ActiveSnapshot): PropertyStatus {
  if (p.owner_ref && p.owner_ref === snap.me.public_ref) return 'mine';
  if (p.owner_ref) return 'owned';
  if (p.in_auction) return 'in_auction';
  if (!p.is_buyable) return 'not_buyable';
  return 'available';
}

/** ¿Estoy (mi ficha) en la casilla de esta propiedad? */
export function amOnProperty(snap: ActiveSnapshot, propertyRef: string): boolean {
  return snap.current_space?.property_ref === propertyRef;
}

/** ¿Puedo SOLICITAR la compra ahora? Solo la propiedad en la que he caído, en mi turno, activo,
 *  en curso, comprable, libre y sin subasta. */
export function canRequestPurchase(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return canActAsMe(snap) && snap.me.is_current && amOnProperty(snap, p.property_ref)
    && p.is_buyable && p.owner_ref === null && !p.in_auction;
}

/** Explicación breve de por qué (no) puedo solicitar comprar una propiedad disponible. null = sí puedo. */
export function purchaseBlockReason(p: ActiveProperty, snap: ActiveSnapshot): string | null {
  if (canRequestPurchase(p, snap)) return null;
  if (p.owner_ref !== null || p.in_auction || !p.is_buyable) return null; // no es "disponible" comprable
  if (snap.me.is_spectator) return 'Estás en bancarrota: no puedes comprar.';
  if (!isRunning(snap)) return 'La partida no está en curso.';
  return 'Solo puedes solicitar comprar la propiedad en la que has caído durante tu turno.';
}

/** ¿Puedo pagar el alquiler de esta propiedad? (en curso, de otro jugador, con alquiler y saldo). */
export function canPayRent(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return (
    canActAsMe(snap) && p.owner_ref !== null && p.owner_ref !== snap.me.public_ref &&
    p.base_rent > 0 && snap.me.balance >= p.base_rent
  );
}

/** ¿Puedo pujar en una subasta? (en curso, no espectador). */
export function canBid(snap: ActiveSnapshot): boolean {
  return canActAsMe(snap);
}

/** Puja mínima válida para una subasta (puja actual + 1, o 1 si no hay). */
export function minBid(a: { high_bid: number | null }): number {
  return (a.high_bid ?? 0) + 1;
}

/** Otros jugadores activos a los que se les puede deber (para bancarrota a jugador). */
export function activeCreditors(snap: ActiveSnapshot): ActivePlayer[] {
  return snap.players.filter((p) => p.status === 'active' && p.public_ref !== snap.me.public_ref);
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

// ── Movimiento y tablero (Fase 4) ────────────────────────────────────────────────
export const SPACE_TYPE_LABEL: Record<SpaceType, string> = {
  start: 'Salida', property: 'Propiedad', tax: 'Impuesto', card: 'Carta',
  jail: 'Cárcel', go_to_jail: 'Ir a la cárcel', parking: 'Parking', special: 'Especial',
};
export function spaceTypeLabel(t: SpaceType): string {
  return SPACE_TYPE_LABEL[t] ?? t;
}

/** ¿Puedo tirar los dados / mover ahora? (en curso, mi turno, no espectador). */
export function canRoll(snap: ActiveSnapshot): boolean {
  return canActAsMe(snap) && snap.me.is_current;
}
/** El anfitrión puede corregir posiciones mientras la partida está en curso. */
export function canHostSetPosition(snap: ActiveSnapshot): boolean {
  return snap.me.is_host && isRunning(snap);
}

/** Tamaño del anillo de un tablero (según el snapshot). Defensivo ante snapshots sin tablero. */
export function ringSize(snap: ActiveSnapshot, board: BoardKey): number {
  return (snap.boards ?? []).find((b) => b.board_key === board)?.ring_size
    ?? (snap.spaces ?? []).filter((s) => s.board_key === board).length;
}

/** Casilla resultante de avanzar `steps` desde `from` en un anillo de tamaño `ring` (espejo del backend). */
export function nextSpaceIndex(from: number, steps: number, ring: number): number {
  if (ring <= 0) return from;
  return (((from + steps) % ring) + ring) % ring;
}

/** ¿Se cruza (o se cae en) la salida al avanzar `steps` desde `from`? (espejo del backend, steps≥1). */
export function passesStart(from: number, steps: number, ring: number): boolean {
  return ring > 0 && steps > 0 && from + steps >= ring;
}

/** Posición (ficha) de un jugador, si la tiene. */
export function positionOf(snap: ActiveSnapshot, ref: string): PlayerPosition | undefined {
  return snap.positions.find((p) => p.player_ref === ref);
}

/** public_ref de los jugadores cuya ficha está en una casilla concreta. */
export function playersAtSpace(snap: ActiveSnapshot, board: BoardKey, index: number): string[] {
  return snap.positions.filter((p) => p.board_key === board && p.space_index === index).map((p) => p.player_ref);
}

/** Casillas de un tablero ordenadas por índice. */
export function spacesOfBoard(snap: ActiveSnapshot, board: BoardKey): BoardSpace[] {
  return snap.spaces.filter((s) => s.board_key === board).sort((a, b) => a.space_index - b.space_index);
}

/** Casillas agrupadas por tablero (orden de anillo). */
export function spacesByBoard(snap: ActiveSnapshot): { board: BoardKey; label: string; items: BoardSpace[] }[] {
  const order: BoardKey[] = [];
  for (const s of snap.spaces) if (!order.includes(s.board_key)) order.push(s.board_key);
  return order.map((board) => ({ board, label: BOARD_LABEL[board] ?? board, items: spacesOfBoard(snap, board) }));
}

/** La propiedad sobre la que está la ficha del jugador local (o null si la casilla no es propiedad). */
export function currentSpaceProperty(snap: ActiveSnapshot): ActiveProperty | null {
  const ref = snap.current_space?.property_ref;
  if (!ref) return null;
  return snap.properties.find((p) => p.property_ref === ref) ?? null;
}

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

/** Metadatos de cada grupo de color/tipo: etiqueta legible y color de la franja (swatch). */
export const GROUP_META: Record<string, { label: string; swatch: string }> = {
  marron: { label: 'Marrón', swatch: '#7c4a13' },
  celeste: { label: 'Celeste', swatch: '#5cc8e6' },
  rosa: { label: 'Rosa', swatch: '#d6489b' },
  naranja: { label: 'Naranja', swatch: '#e3811f' },
  rojo: { label: 'Rojo', swatch: '#d23b34' },
  amarillo: { label: 'Amarillo', swatch: '#e8c83c' },
  verde: { label: 'Verde', swatch: '#2f9e5a' },
  azul: { label: 'Azul', swatch: '#2f5fd0' },
  estaciones: { label: 'Estaciones', swatch: '#94a3b8' },
  transportes: { label: 'Transportes', swatch: '#94a3b8' },
  servicios: { label: 'Servicios', swatch: '#a78bda' },
};
export function groupLabel(groupKey: string): string {
  return GROUP_META[groupKey]?.label ?? groupKey;
}
export function groupSwatch(groupKey: string): string {
  return GROUP_META[groupKey]?.swatch ?? '#64748b';
}

export interface PropertyGroup { group: string; label: string; swatch: string; items: ActiveProperty[] }
export interface PropertyBoardGroups { board: string; label: string; groups: PropertyGroup[] }

/** Propiedades agrupadas por tablero y, dentro, por grupo/color; ambos en orden de tablero
 *  (sort_order). Estructura para la vista "Tablero de propiedades". */
export function propertyGroupsByBoard(snap: ActiveSnapshot): PropertyBoardGroups[] {
  const sorted = [...snap.properties].sort((a, b) => a.sort_order - b.sort_order);
  const boardOrder: string[] = [];
  const byBoard = new Map<string, ActiveProperty[]>();
  for (const p of sorted) {
    if (!byBoard.has(p.board_key)) { byBoard.set(p.board_key, []); boardOrder.push(p.board_key); }
    byBoard.get(p.board_key)!.push(p);
  }
  return boardOrder.map((board) => {
    const groupOrder: string[] = [];
    const byGroup = new Map<string, ActiveProperty[]>();
    for (const p of byBoard.get(board)!) {
      if (!byGroup.has(p.group_key)) { byGroup.set(p.group_key, []); groupOrder.push(p.group_key); }
      byGroup.get(p.group_key)!.push(p);
    }
    return {
      board,
      label: BOARD_LABEL[board] ?? board,
      groups: groupOrder.map((group) => ({
        group, label: groupLabel(group), swatch: groupSwatch(group), items: byGroup.get(group)!,
      })),
    };
  });
}
