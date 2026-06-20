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
  guardian_toll: 'Peaje del guardián',
  tax_payment: 'Pago de impuesto',
  parking_pot_payout: 'Cobro del bote de Parking',
  jail_release_payment: 'Salida de la cárcel',
  card_bank_payment: 'Carta: cobras de la banca',
  card_bank_charge: 'Carta: pagas a la banca',
  card_player_payment: 'Carta: pagas a un jugador',
  card_player_charge: 'Carta: cobras de un jugador',
  building_purchase: 'Compra de casa',
  building_sale: 'Venta de casa',
  hotel_purchase: 'Compra de hotel',
  hotel_sale: 'Venta de hotel',
  mortgage_received: 'Hipoteca recibida',
  unmortgage_payment: 'Deshipoteca',
};
export function kindLabel(kind: LedgerKind): string {
  return KIND_LABEL[kind];
}

// ── Fase 5: cartas, cárcel, impuestos ──
const DECK_LABEL: Record<string, string> = {
  chance: 'Suerte', community_chest: 'Caja de Comunidad', past: 'Pasado', future: 'Futuro',
};
/** Etiqueta legible de un mazo de cartas. */
export function deckLabel(deck: string): string {
  return DECK_LABEL[deck] ?? deck;
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
  if (!(canActAsMe(snap) && p.owner_ref !== null && p.owner_ref !== snap.me.public_ref)) return false;
  if (snap.current_landing_rent_resolved) return false;             // ya pagado en esta caída
  const due = p.kind === 'station' || p.kind === 'transport' ? stationRentInfo(p, snap).amount : p.base_rent;
  return due > 0 && snap.me.balance >= due;
}

// ── Estaciones / transportes (Fase 5 corrección): alquiler acumulativo entre ambos tableros ──────────
const STATION_SCALE = [0, 25, 50, 100, 200, 300, 400, 500, 600] as const;
/** Alquiler de estación/transporte según cuántas posea el propietario (1→25 … 8→600). */
export function stationRent(count: number): number {
  return STATION_SCALE[Math.min(Math.max(count, 0), 8)] ?? 0;
}
/** Nº de estaciones/transportes ACTIVOS de un jugador (combinando ambos tableros). */
export function playerStationCount(snap: ActiveSnapshot, ownerRef: string | null): number {
  if (!ownerRef) return 0;
  return snap.properties.filter((p) => (p.kind === 'station' || p.kind === 'transport') && p.owner_ref === ownerRef).length;
}
export interface StationRentInfo { count: number; amount: number; }
export function stationRentInfo(p: ActiveProperty, snap: ActiveSnapshot): StationRentInfo {
  const count = playerStationCount(snap, p.owner_ref);
  return { count, amount: stationRent(count) };
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

// ── Servicios / utilities (Fase 5 corrección ampliada) ──────────────────────────────
/** Multiplicador de alquiler de servicios según cuántos posea el propietario (1→×4 … 4→×20). */
export function utilityMultiplier(count: number): number {
  return count >= 4 ? 20 : count === 3 ? 14 : count === 2 ? 10 : 4;
}

/** Nº de servicios ACTIVOS de un jugador (combinando ambos tableros). */
export function playerUtilityCount(snap: ActiveSnapshot, ownerRef: string | null): number {
  if (!ownerRef) return 0;
  return snap.properties.filter((p) => p.kind === 'utility' && p.owner_ref === ownerRef).length;
}

/** Modo de dados de la partida (por defecto 'virtual_only'). */
export function diceMode(snap: ActiveSnapshot): 'virtual_only' | 'physical_allowed' | 'physical_only' {
  return snap.game.config.dice_mode ?? 'virtual_only';
}
export function physicalAllowed(snap: ActiveSnapshot): boolean { return diceMode(snap) !== 'virtual_only'; }
export function virtualAllowed(snap: ActiveSnapshot): boolean { return diceMode(snap) !== 'physical_only'; }

/** Datos para mostrar/cobrar el alquiler de un servicio. `total` es la tirada del pagador que le hizo
 *  caer (si existe y es suya); si falta, hay que pedir una tirada. `amount` = total × multiplicador. */
export interface UtilityRentInfo {
  count: number;
  multiplier: number;
  total: number | null;   // tirada válida del pagador, o null si hay que pedirla
  amount: number | null;  // total × multiplier, o null
}
export function utilityRentInfo(p: ActiveProperty, snap: ActiveSnapshot): UtilityRentInfo {
  const count = playerUtilityCount(snap, p.owner_ref);
  const multiplier = utilityMultiplier(count);
  const roll = snap.last_roll;
  const total = roll && roll.player_ref === snap.me.public_ref ? roll.total : null;
  return { count, multiplier, total, amount: total === null ? null : total * multiplier };
}

// ── Construcciones e hipotecas (Fase 6, solo calles) ────────────────────────────────
/** ¿La propiedad es mía? */
export function isMine(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return p.owner_ref !== null && p.owner_ref === snap.me.public_ref;
}
const isStreet = (p: ActiveProperty) => p.kind === 'street';
/** ¿Es elegible para construir? Monopolio del grupo, o regla "sin monopolio" activada y la propiedad es mía.
 *  (El backend valida igual: `_p6_build_eligible` = monopolio OR allow_build_without_monopoly.) */
export function buildEligible(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  if (p.monopoly === true) return true;
  return snap.game.config.allow_build_without_monopoly === true && isMine(p, snap);
}
/** ¿Puedo construir una casa? (mía, calle, elegible, no hipotecada, <4 casas, sin hotel, saldo). */
export function canBuildHouse(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return isMine(p, snap) && isStreet(p) && !p.mortgaged && buildEligible(p, snap) && !p.has_hotel
    && (p.houses ?? 0) < 4 && p.house_cost != null && snap.me.balance >= p.house_cost;
}
/** ¿Puedo construir un hotel? (mía, calle, elegible, 4 casas, sin hotel, saldo). */
export function canBuildHotel(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return isMine(p, snap) && isStreet(p) && !p.mortgaged && buildEligible(p, snap) && !p.has_hotel
    && (p.houses ?? 0) === 4 && p.hotel_cost != null && snap.me.balance >= p.hotel_cost;
}
/** ¿Puedo vender una casa? (mía, calle, con casas y sin hotel). */
export function canSellHouse(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return isMine(p, snap) && isStreet(p) && !p.has_hotel && (p.houses ?? 0) > 0;
}
/** ¿Puedo vender un hotel? (mía, calle, con hotel). */
export function canSellHotel(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return isMine(p, snap) && isStreet(p) && p.has_hotel === true;
}
/** ¿Puedo hipotecar? (mía, calle, no hipotecada, sin construcciones en esta propiedad). */
export function canMortgage(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return isMine(p, snap) && isStreet(p) && !p.mortgaged && !p.has_hotel && (p.houses ?? 0) === 0;
}
/** ¿Puedo deshipotecar? (mía, calle, hipotecada, saldo suficiente). */
export function canUnmortgage(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  return isMine(p, snap) && isStreet(p) && p.mortgaged === true && p.unmortgage_cost != null && snap.me.balance >= p.unmortgage_cost;
}
/** Explicación breve de por qué no hay acciones de construcción disponibles (para la ficha). */
export function buildBlockReason(p: ActiveProperty, snap: ActiveSnapshot): string | null {
  if (!isMine(p, snap) || !isStreet(p)) return null;
  if (p.mortgaged) return 'Propiedad hipotecada. Deshipoteca para volver a construir.';
  // Con la regla "construir sin grupo completo" activada, no se exige monopolio.
  if (!buildEligible(p, snap)) return 'Necesitas tener el grupo de color completo para construir.';
  return null;
}

/** ¿Puedo pagar el alquiler de un servicio? (mi turno, dueño ajeno, hay tirada y saldo suficiente). */
export function canPayUtilityRent(p: ActiveProperty, snap: ActiveSnapshot): boolean {
  if (!(canActAsMe(snap) && p.kind === 'utility' && p.owner_ref !== null && p.owner_ref !== snap.me.public_ref)) return false;
  if (snap.current_landing_rent_resolved) return false;             // ya pagado en esta caída
  const info = utilityRentInfo(p, snap);
  return info.amount !== null && snap.me.balance >= info.amount;
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

export interface JunctionOption { dir: 'own' | 'cross'; board: BoardKey; name: string; guarded: boolean; toll: number; }
export interface JunctionChoice { board: BoardKey; remaining: number; own: JunctionOption; cross: JunctionOption; }

/** Si el jugador local tiene una decisión de cruce pendiente, devuelve los dos destinos (seguir/cruzar),
 *  cuál está custodiado (peaje) y cuál es libre. null si no hay decisión pendiente para mí. */
export function junctionChoice(snap: ActiveSnapshot): JunctionChoice | null {
  const pj = snap.pending_junction;
  if (!pj || pj.player_ref !== snap.me.public_ref) return null;
  const jail = snap.spaces.find((s) => s.board_key === pj.board_key && s.guardian && s.space_index === pj.junction_index);
  if (!jail || !jail.links_to_board || jail.links_to_index == null) return null;
  const guards = snap.guardians.find((g) => g.board_key === pj.board_key)?.guards ?? 'cross';
  const toll = jail.guardian_toll ?? 0;
  const nameAt = (b: BoardKey, idx: number): string =>
    snap.spaces.find((s) => s.board_key === b && s.space_index === idx)?.name ?? `#${idx}`;
  return {
    board: pj.board_key,
    remaining: pj.remaining,
    own: { dir: 'own', board: pj.board_key, name: nameAt(pj.board_key, pj.junction_index + 1), guarded: guards === 'own', toll },
    cross: { dir: 'cross', board: jail.links_to_board, name: nameAt(jail.links_to_board, jail.links_to_index), guarded: guards === 'cross', toll },
  };
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
