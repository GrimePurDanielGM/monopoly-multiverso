// Contrato saneado de get_active_snapshot_by_code + validación en runtime.
// Solo public_ref / ledger_ref: rechaza claves internas prohibidas (el id de sesión) y tipos inválidos.
import { hasForbiddenKey } from './snapshot';

export type LedgerKind =
  | 'seed' | 'late_join_seed' | 'bank_to_player' | 'player_to_bank' | 'player_to_player'
  | 'host_player_transfer' | 'host_adjust' | 'host_revert'
  | 'player_exit_to_bank' | 'player_exit_distribution' | 'player_exit_remainder_to_bank'
  | 'property_purchase' | 'rent_payment' | 'property_auction_purchase'
  | 'bankruptcy_cash_to_bank' | 'bankruptcy_cash_to_player'
  | 'pass_start_bonus' | 'guardian_toll'
  // Fase 5 — casillas especiales
  | 'tax_payment' | 'parking_pot_payout' | 'jail_release_payment'
  | 'card_bank_payment' | 'card_bank_charge' | 'card_player_payment' | 'card_player_charge'
  // Fase 6 — construcciones e hipotecas
  | 'building_purchase' | 'building_sale' | 'hotel_purchase' | 'hotel_sale' | 'mortgage_received' | 'unmortgage_payment'
  // Fase 7 — tratos entre jugadores (dinero)
  | 'trade_money';

export type BoardKey = 'classic' | 'back_to_the_future';
export type DeckKey = 'chance' | 'community_chest' | 'past' | 'future';
export type CardEffectType =
  | 'bank_credit' | 'bank_debit' | 'each_player_credit' | 'each_player_debit'
  | 'to_start' | 'to_jail' | 'back_steps' | 'jail_free' | 'manual'
  | 'to_space' | 'to_nearest' | 'repairs' | 'choice';
export type SpaceType = 'start' | 'property' | 'tax' | 'card' | 'jail' | 'go_to_jail' | 'parking' | 'special';
export type PropertyKind = 'street' | 'station' | 'transport' | 'utility' | 'special';
export interface ActiveProperty {
  property_ref: string;
  board_key: BoardKey;
  group_key: string;
  name: string;
  kind: PropertyKind;
  price: number;
  base_rent: number;
  is_buyable: boolean;
  sort_order: number;
  owner_ref: string | null; // null = disponible en banca
  in_auction: boolean;
  // Campos de la tarjeta de título (solo consulta). Opcionales (snapshots antiguos no los traen);
  // null/undefined = no aplica / pendiente de confirmar. El parser siempre los rellena (número o null).
  rent_1?: number | null;
  rent_2?: number | null;
  rent_3?: number | null;
  rent_4?: number | null;
  rent_hotel?: number | null;
  house_cost?: number | null;
  hotel_cost?: number | null;
  mortgage_value?: number | null;
  unmortgage_cost?: number | null;
  // Fase 6 — estado de construcción/hipoteca y alquiler actual adeudado
  houses?: number | null;        // 0–4 casas (calles)
  has_hotel?: boolean | null;    // hotel presente (calles)
  mortgaged?: boolean | null;    // hipotecada (bloquea alquiler)
  monopoly?: boolean | null;     // el dueño posee todo el grupo (habilita construir)
  rent_due?: number | null;      // alquiler actual que adeudaría quien cae (calle/estación); null si no aplica
}

export interface PropertyAuction {
  auction_ref: string;
  property_ref: string;
  property_name: string;
  high_bid: number | null;
  high_bidder_ref: string | null;
  started_by_ref: string;
}
export interface PurchaseRequest {
  request_ref: string;
  property_ref: string;
  property_name: string;
  requester_ref: string;
  requester_name: string;
}
export interface LeaveRequest {
  request_ref: string;
  requester_ref: string;
  requester_name: string;
}
export type BankruptcyKind = 'to_bank' | 'to_player';
export interface BankruptcyRequest {
  request_ref: string;
  requester_ref: string;
  requester_name: string;
  kind: BankruptcyKind;
  creditor_ref: string | null;
  creditor_name: string | null;
  reason: string | null;
}

/** Modo de dados configurable por el anfitrión (Fase 5 corrección ampliada). */
export type DiceMode = 'virtual_only' | 'physical_allowed' | 'physical_only';

/** Normaliza el dice_mode del snapshot; ante cualquier valor desconocido cae a 'virtual_only'. */
export function parseDiceMode(v: unknown): DiceMode {
  return v === 'physical_allowed' || v === 'physical_only' ? v : 'virtual_only';
}

/** Acción de construcción/venta sujeta a aprobación del anfitrión (Fase 6 pulido). */
export type BuildingAction = 'build_house' | 'build_hotel' | 'sell_house' | 'sell_hotel';
export interface BuildingRequest {
  request_ref: string;
  property_ref: string;
  property_name: string;
  action: BuildingAction;
  requester_ref: string;
  requester_name: string;
}

// ── Fase 7: tratos entre jugadores ────────────────────────────────────────────
export type TradeStatus = 'pending' | 'countered' | 'host_review' | 'executed' | 'rejected' | 'cancelled' | 'invalidated';
export interface TradeProperty { property_ref: string; name: string; mortgaged: boolean }
export interface TradeCard { card_ref: string; title: string }
export interface TradeProposal {
  trade_ref: string;
  from_ref: string; from_name: string;
  to_ref: string; to_name: string;
  from_money: number; to_money: number;
  from_properties: TradeProperty[]; to_properties: TradeProperty[];
  from_cards: TradeCard[]; to_cards: TradeCard[];
  agreement_text: string | null;
  status: TradeStatus;
  requires_host: boolean;
  pending_party: string | null;   // de quién se espera la próxima acción (public_ref) o null
  created_at: string;
}

export interface ActiveConfig {
  initial_money: number;
  min_players: number;
  max_players: number;
  allow_late_join: boolean;
  start_bonus: number;
  dice_mode: DiceMode;
  initial_houses_available: number;
  initial_hotels_available: number;
  allow_build_without_monopoly: boolean;
  allow_trade_built_properties: boolean;
  parking_mode: 'pot' | 'roulette';
  start_invest_pct: number;
}

// ── Fase 4: tablero, casillas y posiciones ────────────────────────────────────────
export interface BoardInfo {
  board_key: BoardKey;
  ring_size: number;
  start_bonus: number;
  provisional: boolean; // true = orden por confirmar (RdF en Fase 4)
}
export interface BoardSpace {
  space_ref: string;
  board_key: BoardKey;
  space_index: number;
  name: string;
  space_type: SpaceType;
  property_ref: string | null;
  is_start: boolean;
  provisional?: boolean;
  guardian?: boolean;               // cárcel con guardián/centinela (montaje de doble tablero)
  links_to_board?: BoardKey | null; // tablero del otro lado del montaje (en cruz)
  links_to_index?: number | null;   // casilla del otro tablero con la que coincide esta esquina
  guardian_toll?: number | null;    // peaje del guardián (si esta casilla tiene guardián)
}
// Enlace de montaje entre tableros (esquina que coincide con otra del otro tablero).
export interface BoardLink {
  board_key: BoardKey;
  space_index: number;
  space_type: SpaceType;
  links_to_board: BoardKey | null;
  links_to_index: number | null;
  guardian: boolean;
}
export type GuardDir = 'own' | 'cross';
// Posición dinámica del guardián de un tablero (qué entrada custodia).
export interface GuardianState {
  board_key: BoardKey;
  guards: GuardDir;
}
// Decisión de cruce pendiente: el jugador llegó a la cárcel-guardián con pasos restantes.
export interface PendingJunction {
  player_ref: string;
  board_key: BoardKey;
  junction_index: number;
  remaining: number;
  passed_start?: boolean;
}
export interface PlayerPosition {
  player_ref: string;
  board_key: BoardKey;
  space_index: number;
}
export interface MyPosition {
  board_key: BoardKey;
  space_index: number;
}
export interface CurrentSpace {
  space_ref: string;
  board_key: BoardKey;
  space_index: number;
  name: string;
  space_type: SpaceType;
  property_ref: string | null;
  is_start: boolean;
}
export type JailRollResult = 'doubles' | 'failed' | 'forced_paid' | 'forced_pending';
export interface LastRoll {
  d1: number;
  d2: number;
  total: number;
  player_ref: string;
  jail?: JailRollResult | null; // si la tirada fue un intento de dobles dentro de la cárcel
}
/** Evento global de partida (Fase 5 corrección): p. ej. alguien cobra el bote del Parking → banner a todos. */
export interface GlobalEvent {
  kind: string;          // 'parking_pot_payout' | 'parking_roulette'
  player_ref: string;
  amount: number;
  event_id: string;      // identificador único para no repetir el banner
  outcome?: string | undefined;      // ruleta: collect_pot | draw_card | go_to_jail | lose_most_valuable | lose_least_valuable | pay_500
  property_ref?: string | null | undefined; // ruleta: propiedad expropiada
}
/** Efecto de la casilla al caer (Fase 5): impuesto, parking (bote), ir a la cárcel o carta. */
export interface LandingEffect {
  type: 'tax' | 'parking' | 'go_to_jail' | 'card' | 'none';
  name?: string;            // tax: nombre del impuesto
  amount?: number | null;   // tax: importe; card: importe de la carta
  paid?: boolean;           // tax: ¿se cobró?
  pending?: boolean;        // tax: quedó pendiente por falta de saldo
  payout?: number;          // parking: bote cobrado
  jailed?: boolean;         // go_to_jail
  board?: string;           // go_to_jail
  deck?: string;            // card
  card_ref?: string;        // card
  title?: string;           // card
  effect_type?: string;     // card
  manual?: boolean;         // card: requiere resolución manual
  keepable?: boolean;       // card: conservable
  empty?: boolean;          // card: mazo vacío
}
export interface LastMove {
  player_ref: string;
  board: BoardKey;
  from: number;
  to: number;
  steps: number;
  method: string;
  passed_start: boolean;
  bonus: number;
  space_ref: string;
  space_name: string;
  space_type: SpaceType;
  property_ref: string | null;
  effect?: LandingEffect | null;
}
export interface JailEntry { player_ref: string; board_key: BoardKey; jail_turns: number; }
export interface MyJail { board_key: BoardKey; jail_turns: number; fine: number; action_taken_this_turn: boolean; }
export interface CardDeckSummary { deck_key: DeckKey; board_key: BoardKey; draw_count: number; discard_count: number; }
export interface LastCardDraw {
  draw_id: string; player_ref: string; deck_key: DeckKey; board_key: BoardKey; card_ref: string;
  title: string; description: string; effect_type: CardEffectType; amount: number | null;
  keepable: boolean; temporary: boolean; manual: boolean; manual_instruction: string | null;
}
export interface HeldCardCount { player_ref: string; count: number; }
/** Transferencia de carta «a cada jugador» que YO (el pagador) debo autorizar. */
export interface CardTransfer { transfer_ref: string; amount: number; payer_ref: string; payee_ref: string; payer_name: string; payee_name: string; }
export interface MyHeldCard { card_ref: string; title: string; description: string; deck_key: DeckKey; effect_type: CardEffectType; }
export interface PendingCard { player_ref: string; card_ref: string; deck_key: DeckKey; title: string; description: string; kind: 'manual' | 'choice'; manual_instruction: string | null; amount: number | null; }
export interface PendingPayment { kind: string; player_ref: string; amount: number; board: BoardKey; space_index: number; space_name: string; }
export interface LateJoinRequest {
  request_ref: string;
  name: string;
  token: string;
  device_label: string | null;
}
export interface ActiveGameInfo {
  code: string;
  status: 'active';
  config: ActiveConfig;
}
export interface ActiveMe {
  public_ref: string;
  is_host: boolean;
  balance: number;
  is_current: boolean;
  is_spectator: boolean; // en bancarrota: consulta pero no actúa
}
export interface ActiveTurn {
  turn_number: number;
  current_player_ref: string;
  order: string[];
}
export type PlayerStatus = 'active' | 'bankrupt';
export interface ActivePlayer {
  public_ref: string;
  display_name: string;
  token_id: string | null;
  balance: number | null; // null = saldo ajeno oculto (privacidad: solo ves el tuyo)
  is_current: boolean;
  status: PlayerStatus;
}
export interface LedgerEntry {
  ledger_ref: string;
  seq: number;
  kind: LedgerKind;
  from_ref: string | null;
  to_ref: string | null;
  amount: number;
  before_balance: number | null;
  after_balance: number | null;
  reason: string | null;
  actor_ref: string | null;
  reverts_ref: string | null;
  created_at: string;
}
export type RuntimeStatus = 'running' | 'paused' | 'finished';
export interface ActiveControl {
  paused_by_ref: string | null;
  finished_by_ref: string | null;
  reason: string | null;
}
export interface ActiveSnapshot {
  game: ActiveGameInfo;
  me: ActiveMe;
  turn: ActiveTurn;
  players: ActivePlayer[];
  ledger_recent: LedgerEntry[];
  properties: ActiveProperty[];
  auctions: PropertyAuction[];
  purchase_requests: PurchaseRequest[];
  leave_requests: LeaveRequest[];
  bankruptcy_requests: BankruptcyRequest[];
  late_join_requests: LateJoinRequest[];
  boards: BoardInfo[];
  spaces: BoardSpace[];
  board_links: BoardLink[];
  guardians: GuardianState[];
  pending_junction: PendingJunction | null;
  positions: PlayerPosition[];
  my_position: MyPosition | null;
  current_space: CurrentSpace | null;
  last_roll: LastRoll | null;
  last_move: LastMove | null;
  // Fase 5 — casillas especiales
  parking_pot: number;
  jail: JailEntry[];
  my_jail: MyJail | null;
  card_decks: CardDeckSummary[];
  last_card_draw: LastCardDraw | null;
  held_cards: HeldCardCount[];
  my_held_cards: MyHeldCard[];
  pending_card: PendingCard | null;
  pending_payment: PendingPayment | null;
  last_global_event: GlobalEvent | null;
  runtime_status: RuntimeStatus;
  /** ¿la caída actual ya tiene su alquiler resuelto? (bloqueo de doble pago) */
  current_landing_rent_resolved: boolean;
  /** Stock físico del banco (Fase 6): casas/hoteles disponibles. */
  building_stock: { houses_available: number; hotels_available: number } | null;
  /** Solicitudes de construcción pendientes (solo el anfitrión las recibe). */
  building_requests: BuildingRequest[];
  /** Mis solicitudes de construcción pendientes (para mostrar "pendiente" en la ficha). */
  my_building_requests: Array<{ property_ref: string; action: BuildingAction }>;
  /** Fase 7 — tratos: dirigidos a mí (activos), creados por mí (activos), a revisar por el anfitrión, e historial. */
  incoming_trades: TradeProposal[];
  outgoing_trades: TradeProposal[];
  trade_reviews: TradeProposal[];
  recent_trades: TradeProposal[];
  my_card_transfers: CardTransfer[];
  control: ActiveControl;
  runtime_version: number;
}

function isObj(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}
const isStr = (v: unknown): v is string => typeof v === 'string';
const isBuildingAction = (v: unknown): v is BuildingAction => v === 'build_house' || v === 'build_hotel' || v === 'sell_house' || v === 'sell_hotel';
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isBool = (v: unknown): v is boolean => typeof v === 'boolean';
const isStrOrNull = (v: unknown): v is string | null => v === null || typeof v === 'string';
const isNumOrNull = (v: unknown): v is number | null => v === null || isNum(v);

const KINDS: ReadonlySet<string> = new Set([
  'seed', 'late_join_seed', 'bank_to_player', 'player_to_bank', 'player_to_player', 'host_player_transfer', 'host_adjust', 'host_revert',
  'player_exit_to_bank', 'player_exit_distribution', 'player_exit_remainder_to_bank',
  'property_purchase', 'rent_payment', 'property_auction_purchase', 'bankruptcy_cash_to_bank', 'bankruptcy_cash_to_player',
  'pass_start_bonus', 'guardian_toll',
  'tax_payment', 'parking_pot_payout', 'jail_release_payment',
  'card_bank_payment', 'card_bank_charge', 'card_player_payment', 'card_player_charge',
  'building_purchase', 'building_sale', 'hotel_purchase', 'hotel_sale', 'mortgage_received', 'unmortgage_payment',
  'trade_money',
]);
const TRADE_STATUSES: ReadonlySet<string> = new Set(['pending', 'countered', 'host_review', 'executed', 'rejected', 'cancelled', 'invalidated']);

function parseTradeProps(v: unknown): TradeProperty[] {
  return Array.isArray(v) ? v.filter(isObj).map((p) => ({
    property_ref: String(p.property_ref), name: isStr(p.name) ? p.name : String(p.property_ref), mortgaged: p.mortgaged === true })) : [];
}
function parseTradeCards(v: unknown): TradeCard[] {
  return Array.isArray(v) ? v.filter(isObj).map((c) => ({ card_ref: String(c.card_ref), title: isStr(c.title) ? c.title : '' })) : [];
}
/** Parsea una colección de tratos del snapshot (saneada, tolerante). */
function parseTrades(v: unknown): TradeProposal[] {
  if (!Array.isArray(v)) return [];
  return v.filter(isObj).filter((t) => isStr(t.trade_ref) && typeof t.status === 'string' && TRADE_STATUSES.has(t.status)).map((t) => ({
    trade_ref: String(t.trade_ref),
    from_ref: String(t.from_ref), from_name: isStr(t.from_name) ? t.from_name : String(t.from_ref),
    to_ref: String(t.to_ref), to_name: isStr(t.to_name) ? t.to_name : String(t.to_ref),
    from_money: isNum(t.from_money) ? t.from_money : 0, to_money: isNum(t.to_money) ? t.to_money : 0,
    from_properties: parseTradeProps(t.from_properties), to_properties: parseTradeProps(t.to_properties),
    from_cards: parseTradeCards(t.from_cards), to_cards: parseTradeCards(t.to_cards),
    agreement_text: isStr(t.agreement_text) ? t.agreement_text : null,
    status: t.status as TradeStatus, requires_host: t.requires_host === true,
    pending_party: isStr(t.pending_party) ? t.pending_party : null,
    created_at: isStr(t.created_at) ? t.created_at : '',
  }));
}
const DECKS: ReadonlySet<string> = new Set(['chance', 'community_chest', 'past', 'future']);
const CARD_EFFECTS: ReadonlySet<string> = new Set([
  'bank_credit', 'bank_debit', 'each_player_credit', 'each_player_debit', 'to_start', 'to_jail', 'back_steps', 'jail_free', 'manual',
  'to_space', 'to_nearest', 'repairs', 'choice',
]);
const isDeck = (v: unknown): v is DeckKey => typeof v === 'string' && DECKS.has(v);
const isCardEffect = (v: unknown): v is CardEffectType => typeof v === 'string' && CARD_EFFECTS.has(v);
const BOARDS: ReadonlySet<string> = new Set(['classic', 'back_to_the_future']);
const PKINDS: ReadonlySet<string> = new Set(['street', 'station', 'transport', 'utility', 'special']);
const SPACE_TYPES: ReadonlySet<string> = new Set(['start', 'property', 'tax', 'card', 'jail', 'go_to_jail', 'parking', 'special']);
const isBoard = (v: unknown): v is BoardKey => v === 'classic' || v === 'back_to_the_future';

/** Parseo tolerante del efecto de casilla en last_move (Fase 5): copia los campos conocidos. */
function parseEffect(v: unknown): LandingEffect | null {
  if (!isObj(v) || !isStr(v.type)) return null;
  const t = v.type;
  if (t !== 'tax' && t !== 'parking' && t !== 'go_to_jail' && t !== 'card' && t !== 'none') return null;
  const e: LandingEffect = { type: t };
  if (isStr(v.name)) e.name = v.name;
  if (isNumOrNull(v.amount)) e.amount = v.amount;
  if (isBool(v.paid)) e.paid = v.paid;
  if (isBool(v.pending)) e.pending = v.pending;
  if (isNum(v.payout)) e.payout = v.payout;
  if (isBool(v.jailed)) e.jailed = v.jailed;
  if (isStr(v.board)) e.board = v.board;
  if (isStr(v.deck)) e.deck = v.deck;
  if (isStr(v.card_ref)) e.card_ref = v.card_ref;
  if (isStr(v.title)) e.title = v.title;
  if (isStr(v.effect_type)) e.effect_type = v.effect_type;
  if (isBool(v.manual)) e.manual = v.manual;
  if (isBool(v.keepable)) e.keepable = v.keepable;
  if (isBool(v.empty)) e.empty = v.empty;
  return e;
}

function parseSpaceLike(s: Record<string, unknown>): BoardSpace | null {
  if (!isStr(s.space_ref) || !isBoard(s.board_key) || !isNum(s.space_index) || !isStr(s.name) ||
      !isStr(s.space_type) || !SPACE_TYPES.has(s.space_type) || !isStrOrNull(s.property_ref) || !isBool(s.is_start)) {
    return null;
  }
  return {
    space_ref: s.space_ref, board_key: s.board_key, space_index: s.space_index, name: s.name,
    space_type: s.space_type as SpaceType, property_ref: s.property_ref, is_start: s.is_start,
    provisional: isBool(s.provisional) ? s.provisional : false,
    guardian: isBool(s.guardian) ? s.guardian : false,
    links_to_board: isBoard(s.links_to_board) ? s.links_to_board : null,
    links_to_index: isNum(s.links_to_index) ? s.links_to_index : null,
    guardian_toll: isNum(s.guardian_toll) ? s.guardian_toll : null,
  };
}

export type ParseActiveResult = { ok: true; data: ActiveSnapshot } | { ok: false; reason: string };
const bad = (reason: string): { ok: false; reason: string } => ({ ok: false, reason });

/** Valida y tipa el snapshot activo. Rechaza estructura inválida o claves internas. */
export function parseActiveSnapshot(raw: unknown): ParseActiveResult {
  if (hasForbiddenKey(raw)) return bad('clave interna prohibida');
  if (!isObj(raw)) return bad('no es objeto');

  const g = raw.game;
  if (!isObj(g) || !isObj(g.config)) return bad('game/config ausente');
  if (!isStr(g.code) || g.status !== 'active') return bad('game inválido');
  const cfg = g.config;
  if (!isNum(cfg.initial_money) || !isNum(cfg.min_players) || !isNum(cfg.max_players) || !isBool(cfg.allow_late_join)) return bad('config inválida');

  const m = raw.me;
  if (!isObj(m) || !isStr(m.public_ref) || !isBool(m.is_host) || !isNum(m.balance) || !isBool(m.is_current) || !isBool(m.is_spectator)) return bad('me inválido');

  const t = raw.turn;
  if (!isObj(t) || !isNum(t.turn_number) || !isStr(t.current_player_ref) || !Array.isArray(t.order) || !t.order.every(isStr)) {
    return bad('turn inválido');
  }

  if (!Array.isArray(raw.players)) return bad('players ausente');
  const players: ActivePlayer[] = [];
  for (const p of raw.players) {
    if (!isObj(p) || !isStr(p.public_ref) || !isStr(p.display_name) || !isStrOrNull(p.token_id) || !isNumOrNull(p.balance) || !isBool(p.is_current) ||
        (p.status !== 'active' && p.status !== 'bankrupt')) {
      return bad('player inválido');
    }
    players.push({ public_ref: p.public_ref, display_name: p.display_name, token_id: p.token_id, balance: p.balance, is_current: p.is_current, status: p.status });
  }

  if (!Array.isArray(raw.ledger_recent)) return bad('ledger_recent ausente');
  const ledger: LedgerEntry[] = [];
  for (const l of raw.ledger_recent) {
    if (
      !isObj(l) || !isStr(l.ledger_ref) || !isNum(l.seq) || !isStr(l.kind) || !KINDS.has(l.kind) ||
      !isStrOrNull(l.from_ref) || !isStrOrNull(l.to_ref) || !isNum(l.amount) ||
      !isNumOrNull(l.before_balance) || !isNumOrNull(l.after_balance) || !isStrOrNull(l.reason) ||
      !isStrOrNull(l.actor_ref) || !isStrOrNull(l.reverts_ref) || !isStr(l.created_at)
    ) {
      return bad('ledger inválido');
    }
    ledger.push({
      ledger_ref: l.ledger_ref, seq: l.seq, kind: l.kind as LedgerKind, from_ref: l.from_ref, to_ref: l.to_ref,
      amount: l.amount, before_balance: l.before_balance, after_balance: l.after_balance, reason: l.reason,
      actor_ref: l.actor_ref, reverts_ref: l.reverts_ref, created_at: l.created_at,
    });
  }

  if (!Array.isArray(raw.properties)) return bad('properties ausente');
  const properties: ActiveProperty[] = [];
  for (const p of raw.properties) {
    if (
      !isObj(p) || !isStr(p.property_ref) || !isStr(p.board_key) || !BOARDS.has(p.board_key) ||
      !isStr(p.group_key) || !isStr(p.name) || !isStr(p.kind) || !PKINDS.has(p.kind) ||
      !isNum(p.price) || !isNum(p.base_rent) || !isBool(p.is_buyable) || !isNum(p.sort_order) || !isStrOrNull(p.owner_ref) || !isBool(p.in_auction)
    ) {
      return bad('property inválida');
    }
    // Campos de la tarjeta: opcionales y nullables (no rompen el snapshot si faltan o no aplican).
    const card = (v: unknown): number | null => (isNum(v) ? v : null);
    properties.push({
      property_ref: p.property_ref, board_key: p.board_key as BoardKey, group_key: p.group_key, name: p.name,
      kind: p.kind as PropertyKind, price: p.price, base_rent: p.base_rent, is_buyable: p.is_buyable,
      sort_order: p.sort_order, owner_ref: p.owner_ref, in_auction: p.in_auction,
      rent_1: card(p.rent_1), rent_2: card(p.rent_2), rent_3: card(p.rent_3), rent_4: card(p.rent_4),
      rent_hotel: card(p.rent_hotel), house_cost: card(p.house_cost), hotel_cost: card(p.hotel_cost),
      mortgage_value: card(p.mortgage_value), unmortgage_cost: card(p.unmortgage_cost),
      houses: isNum(p.houses) ? p.houses : null, has_hotel: isBool(p.has_hotel) ? p.has_hotel : null,
      mortgaged: isBool(p.mortgaged) ? p.mortgaged : null, monopoly: isBool(p.monopoly) ? p.monopoly : null,
      rent_due: card(p.rent_due),
    });
  }

  if (!Array.isArray(raw.auctions)) return bad('auctions ausente');
  const auctions: PropertyAuction[] = [];
  for (const a of raw.auctions) {
    if (!isObj(a) || !isStr(a.auction_ref) || !isStr(a.property_ref) || !isStr(a.property_name) ||
        !isNumOrNull(a.high_bid) || !isStrOrNull(a.high_bidder_ref) || !isStr(a.started_by_ref)) {
      return bad('auction inválida');
    }
    auctions.push({ auction_ref: a.auction_ref, property_ref: a.property_ref, property_name: a.property_name, high_bid: a.high_bid, high_bidder_ref: a.high_bidder_ref, started_by_ref: a.started_by_ref });
  }

  if (!Array.isArray(raw.purchase_requests)) return bad('purchase_requests ausente');
  const purchase: PurchaseRequest[] = [];
  for (const r of raw.purchase_requests) {
    if (!isObj(r) || !isStr(r.request_ref) || !isStr(r.property_ref) || !isStr(r.property_name) || !isStr(r.requester_ref) || !isStr(r.requester_name)) return bad('purchase_request inválida');
    purchase.push({ request_ref: r.request_ref, property_ref: r.property_ref, property_name: r.property_name, requester_ref: r.requester_ref, requester_name: r.requester_name });
  }

  if (!Array.isArray(raw.leave_requests)) return bad('leave_requests ausente');
  const leaves: LeaveRequest[] = [];
  for (const r of raw.leave_requests) {
    if (!isObj(r) || !isStr(r.request_ref) || !isStr(r.requester_ref) || !isStr(r.requester_name)) return bad('leave_request inválida');
    leaves.push({ request_ref: r.request_ref, requester_ref: r.requester_ref, requester_name: r.requester_name });
  }

  if (!Array.isArray(raw.bankruptcy_requests)) return bad('bankruptcy_requests ausente');
  const bankruptcies: BankruptcyRequest[] = [];
  for (const r of raw.bankruptcy_requests) {
    if (!isObj(r) || !isStr(r.request_ref) || !isStr(r.requester_ref) || !isStr(r.requester_name) ||
        (r.kind !== 'to_bank' && r.kind !== 'to_player') || !isStrOrNull(r.creditor_ref) || !isStrOrNull(r.creditor_name) || !isStrOrNull(r.reason)) {
      return bad('bankruptcy_request inválida');
    }
    bankruptcies.push({ request_ref: r.request_ref, requester_ref: r.requester_ref, requester_name: r.requester_name, kind: r.kind, creditor_ref: r.creditor_ref, creditor_name: r.creditor_name, reason: r.reason });
  }

  if (!Array.isArray(raw.late_join_requests)) return bad('late_join_requests ausente');
  const late: LateJoinRequest[] = [];
  for (const l of raw.late_join_requests) {
    if (!isObj(l) || !isStr(l.request_ref) || !isStr(l.name) || !isStr(l.token) || !isStrOrNull(l.device_label)) {
      return bad('late_join inválido');
    }
    late.push({ request_ref: l.request_ref, name: l.name, token: l.token, device_label: l.device_label });
  }

  // ── Fase 4: tablero / casillas / posiciones (tolerante: ausencia => vacío/null) ──
  const boards: BoardInfo[] = [];
  if (Array.isArray(raw.boards)) {
    for (const b of raw.boards) {
      if (!isObj(b) || !isBoard(b.board_key) || !isNum(b.ring_size) || !isNum(b.start_bonus)) return bad('board inválido');
      boards.push({ board_key: b.board_key, ring_size: b.ring_size, start_bonus: b.start_bonus, provisional: isBool(b.provisional) ? b.provisional : false });
    }
  }
  const spaces: BoardSpace[] = [];
  if (Array.isArray(raw.spaces)) {
    for (const s of raw.spaces) {
      if (!isObj(s)) return bad('space inválido');
      const sp = parseSpaceLike(s);
      if (!sp) return bad('space inválido');
      spaces.push(sp);
    }
  }
  const boardLinks: BoardLink[] = [];
  if (Array.isArray(raw.board_links)) {
    for (const l of raw.board_links) {
      if (!isObj(l) || !isBoard(l.board_key) || !isNum(l.space_index) || !isStr(l.space_type) || !SPACE_TYPES.has(l.space_type) ||
          !(l.links_to_board === null || isBoard(l.links_to_board)) || !isNumOrNull(l.links_to_index)) {
        return bad('board_link inválido');
      }
      boardLinks.push({
        board_key: l.board_key, space_index: l.space_index, space_type: l.space_type as SpaceType,
        links_to_board: (l.links_to_board ?? null) as BoardKey | null, links_to_index: l.links_to_index,
        guardian: isBool(l.guardian) ? l.guardian : false,
      });
    }
  }
  const guardians: GuardianState[] = [];
  if (Array.isArray(raw.guardians)) {
    for (const gd of raw.guardians) {
      if (!isObj(gd) || !isBoard(gd.board_key) || (gd.guards !== 'own' && gd.guards !== 'cross')) return bad('guardian inválido');
      guardians.push({ board_key: gd.board_key, guards: gd.guards });
    }
  }
  let pendingJunction: PendingJunction | null = null;
  if (isObj(raw.pending_junction)) {
    const pjj = raw.pending_junction;
    if (!isStr(pjj.player_ref) || !isBoard(pjj.board_key) || !isNum(pjj.junction_index) || !isNum(pjj.remaining)) return bad('pending_junction inválido');
    pendingJunction = {
      player_ref: pjj.player_ref, board_key: pjj.board_key, junction_index: pjj.junction_index,
      remaining: pjj.remaining,
      ...(isBool(pjj.passed_start) ? { passed_start: pjj.passed_start } : {}),
    };
  }
  const positions: PlayerPosition[] = [];
  if (Array.isArray(raw.positions)) {
    for (const p of raw.positions) {
      if (!isObj(p) || !isStr(p.player_ref) || !isBoard(p.board_key) || !isNum(p.space_index)) return bad('position inválida');
      positions.push({ player_ref: p.player_ref, board_key: p.board_key, space_index: p.space_index });
    }
  }
  let myPosition: MyPosition | null = null;
  if (isObj(raw.my_position)) {
    const mp = raw.my_position;
    if (!isBoard(mp.board_key) || !isNum(mp.space_index)) return bad('my_position inválida');
    myPosition = { board_key: mp.board_key, space_index: mp.space_index };
  }
  let currentSpace: CurrentSpace | null = null;
  if (isObj(raw.current_space)) {
    const cs = parseSpaceLike(raw.current_space);
    if (!cs) return bad('current_space inválido');
    currentSpace = cs;
  }
  let lastRoll: LastRoll | null = null;
  if (isObj(raw.last_roll)) {
    const lr = raw.last_roll;
    if (!isNum(lr.d1) || !isNum(lr.d2) || !isNum(lr.total) || !isStr(lr.player_ref)) return bad('last_roll inválido');
    const jr = lr.jail;
    const jail = (jr === 'doubles' || jr === 'failed' || jr === 'forced_paid' || jr === 'forced_pending') ? jr : null;
    lastRoll = { d1: lr.d1, d2: lr.d2, total: lr.total, player_ref: lr.player_ref, jail };
  }
  let lastMove: LastMove | null = null;
  if (isObj(raw.last_move)) {
    const lm = raw.last_move;
    if (!isStr(lm.player_ref) || !isBoard(lm.board) || !isNum(lm.from) || !isNum(lm.to) || !isNum(lm.steps) ||
        !isStr(lm.method) || !isBool(lm.passed_start) || !isNum(lm.bonus) || !isStr(lm.space_ref) ||
        !isStr(lm.space_name) || !isStr(lm.space_type) || !SPACE_TYPES.has(lm.space_type) || !isStrOrNull(lm.property_ref)) {
      return bad('last_move inválido');
    }
    lastMove = {
      player_ref: lm.player_ref, board: lm.board, from: lm.from, to: lm.to, steps: lm.steps, method: lm.method,
      passed_start: lm.passed_start, bonus: lm.bonus, space_ref: lm.space_ref, space_name: lm.space_name,
      space_type: lm.space_type as SpaceType, property_ref: lm.property_ref,
      effect: parseEffect(lm.effect),
    };
  }

  // ── Fase 5: casillas especiales (parseo tolerante; campos opcionales no rompen el snapshot) ──
  const parkingPot = isNum(raw.parking_pot) ? raw.parking_pot : 0;
  const jail: JailEntry[] = [];
  if (Array.isArray(raw.jail)) for (const j of raw.jail) {
    if (isObj(j) && isStr(j.player_ref) && isBoard(j.board_key)) {
      jail.push({ player_ref: j.player_ref, board_key: j.board_key, jail_turns: isNum(j.jail_turns) ? j.jail_turns : 0 });
    }
  }
  let myJail: MyJail | null = null;
  if (isObj(raw.my_jail)) {
    const mj = raw.my_jail;
    if (isBoard(mj.board_key)) {
      myJail = { board_key: mj.board_key, jail_turns: isNum(mj.jail_turns) ? mj.jail_turns : 0, fine: isNum(mj.fine) ? mj.fine : 50,
        action_taken_this_turn: mj.action_taken_this_turn === true };
    }
  }
  const cardDecks: CardDeckSummary[] = [];
  if (Array.isArray(raw.card_decks)) for (const d of raw.card_decks) {
    if (isObj(d) && isDeck(d.deck_key) && isBoard(d.board_key)) {
      cardDecks.push({ deck_key: d.deck_key, board_key: d.board_key, draw_count: isNum(d.draw_count) ? d.draw_count : 0, discard_count: isNum(d.discard_count) ? d.discard_count : 0 });
    }
  }
  let lastCardDraw: LastCardDraw | null = null;
  if (isObj(raw.last_card_draw)) {
    const cd = raw.last_card_draw;
    if (isStr(cd.card_ref) && isDeck(cd.deck_key)) {
      lastCardDraw = {
        draw_id: isStr(cd.draw_id) ? cd.draw_id : cd.card_ref, player_ref: isStr(cd.player_ref) ? cd.player_ref : '',
        deck_key: cd.deck_key, board_key: isBoard(cd.board_key) ? cd.board_key : 'classic', card_ref: cd.card_ref,
        title: isStr(cd.title) ? cd.title : '', description: isStr(cd.description) ? cd.description : '',
        effect_type: isCardEffect(cd.effect_type) ? cd.effect_type : 'manual', amount: isNumOrNull(cd.amount) ? cd.amount : null,
        keepable: isBool(cd.keepable) ? cd.keepable : false, temporary: isBool(cd.temporary) ? cd.temporary : false,
        manual: isBool(cd.manual) ? cd.manual : false, manual_instruction: isStr(cd.manual_instruction) ? cd.manual_instruction : null,
      };
    }
  }
  const heldCards: HeldCardCount[] = [];
  if (Array.isArray(raw.held_cards)) for (const h of raw.held_cards) {
    if (isObj(h) && isStr(h.player_ref)) heldCards.push({ player_ref: h.player_ref, count: isNum(h.count) ? h.count : 0 });
  }
  const myHeldCards: MyHeldCard[] = [];
  if (Array.isArray(raw.my_held_cards)) for (const h of raw.my_held_cards) {
    if (isObj(h) && isStr(h.card_ref) && isDeck(h.deck_key)) {
      myHeldCards.push({ card_ref: h.card_ref, title: isStr(h.title) ? h.title : '', description: isStr(h.description) ? h.description : '',
        deck_key: h.deck_key, effect_type: isCardEffect(h.effect_type) ? h.effect_type : 'jail_free' });
    }
  }
  let pendingCard: PendingCard | null = null;
  if (isObj(raw.pending_card)) {
    const pc = raw.pending_card;
    if (isStr(pc.card_ref) && isDeck(pc.deck_key) && isStr(pc.player_ref)) {
      pendingCard = { player_ref: pc.player_ref, card_ref: pc.card_ref, deck_key: pc.deck_key,
        title: isStr(pc.title) ? pc.title : '', description: isStr(pc.description) ? pc.description : '',
        kind: pc.kind === 'choice' ? 'choice' : 'manual',
        manual_instruction: isStr(pc.manual_instruction) ? pc.manual_instruction : null,
        amount: isNumOrNull(pc.amount) ? pc.amount : null };
    }
  }
  let pendingPayment: PendingPayment | null = null;
  if (isObj(raw.pending_payment)) {
    const pp = raw.pending_payment;
    if (isStr(pp.player_ref) && isNum(pp.amount) && isBoard(pp.board)) {
      pendingPayment = { kind: isStr(pp.kind) ? pp.kind : 'tax', player_ref: pp.player_ref, amount: pp.amount,
        board: pp.board, space_index: isNum(pp.space_index) ? pp.space_index : 0, space_name: isStr(pp.space_name) ? pp.space_name : '' };
    }
  }
  let lastGlobalEvent: GlobalEvent | null = null;
  if (isObj(raw.last_global_event)) {
    const ge = raw.last_global_event;
    if (isStr(ge.kind) && isStr(ge.player_ref) && isStr(ge.event_id)) {
      lastGlobalEvent = { kind: ge.kind, player_ref: ge.player_ref, amount: isNum(ge.amount) ? ge.amount : 0, event_id: ge.event_id,
        outcome: isStr(ge.outcome) ? ge.outcome : undefined, property_ref: isStr(ge.property_ref) ? ge.property_ref : null };
    }
  }

  if (!isNum(raw.runtime_version)) return bad('runtime_version inválido');
  const rs = raw.runtime_status;
  if (rs !== 'running' && rs !== 'paused' && rs !== 'finished') return bad('runtime_status inválido');
  const ctl = raw.control;
  if (!isObj(ctl) || !isStrOrNull(ctl.paused_by_ref) || !isStrOrNull(ctl.finished_by_ref) || !isStrOrNull(ctl.reason)) {
    return bad('control inválido');
  }

  return {
    ok: true,
    data: {
      game: { code: g.code, status: 'active', config: { initial_money: cfg.initial_money, min_players: cfg.min_players, max_players: cfg.max_players, allow_late_join: cfg.allow_late_join, start_bonus: isNum(cfg.start_bonus) ? cfg.start_bonus : 200, dice_mode: parseDiceMode(cfg.dice_mode), initial_houses_available: isNum(cfg.initial_houses_available) ? cfg.initial_houses_available : 32, initial_hotels_available: isNum(cfg.initial_hotels_available) ? cfg.initial_hotels_available : 12, allow_build_without_monopoly: cfg.allow_build_without_monopoly === true, allow_trade_built_properties: cfg.allow_trade_built_properties === true, parking_mode: cfg.parking_mode === 'roulette' ? 'roulette' : 'pot', start_invest_pct: isNum(cfg.start_invest_pct) ? cfg.start_invest_pct : 0 } },
      me: { public_ref: m.public_ref, is_host: m.is_host, balance: m.balance, is_current: m.is_current, is_spectator: m.is_spectator },
      turn: { turn_number: t.turn_number, current_player_ref: t.current_player_ref, order: t.order as string[] },
      players,
      ledger_recent: ledger,
      properties,
      auctions,
      purchase_requests: purchase,
      leave_requests: leaves,
      bankruptcy_requests: bankruptcies,
      late_join_requests: late,
      boards,
      spaces,
      board_links: boardLinks,
      guardians,
      pending_junction: pendingJunction,
      positions,
      my_position: myPosition,
      current_space: currentSpace,
      last_roll: lastRoll,
      last_move: lastMove,
      parking_pot: parkingPot,
      jail,
      my_jail: myJail,
      card_decks: cardDecks,
      last_card_draw: lastCardDraw,
      held_cards: heldCards,
      my_held_cards: myHeldCards,
      pending_card: pendingCard,
      pending_payment: pendingPayment,
      last_global_event: lastGlobalEvent,
      runtime_status: rs,
      current_landing_rent_resolved: raw.current_landing_rent_resolved === true,
      building_stock: isObj(raw.building_stock) && isNum(raw.building_stock.houses_available) && isNum(raw.building_stock.hotels_available)
        ? { houses_available: raw.building_stock.houses_available, hotels_available: raw.building_stock.hotels_available } : null,
      building_requests: Array.isArray(raw.building_requests)
        ? raw.building_requests.filter(isObj).filter((b) => isBuildingAction(b.action)).map((b) => ({
            request_ref: String(b.request_ref), property_ref: String(b.property_ref),
            property_name: isStr(b.property_name) ? b.property_name : String(b.property_ref),
            action: b.action as BuildingAction, requester_ref: String(b.requester_ref),
            requester_name: isStr(b.requester_name) ? b.requester_name : '' })) : [],
      my_building_requests: Array.isArray(raw.my_building_requests)
        ? raw.my_building_requests.filter(isObj).filter((m) => isBuildingAction(m.action)).map((m) => ({ property_ref: String(m.property_ref), action: m.action as BuildingAction })) : [],
      incoming_trades: parseTrades(raw.incoming_trades),
      outgoing_trades: parseTrades(raw.outgoing_trades),
      trade_reviews: parseTrades(raw.trade_reviews),
      recent_trades: parseTrades(raw.recent_trades),
      my_card_transfers: Array.isArray(raw.my_card_transfers)
        ? raw.my_card_transfers.filter(isObj).filter((c) => isStr(c.transfer_ref)).map((c) => ({
            transfer_ref: String(c.transfer_ref), amount: isNum(c.amount) ? c.amount : 0,
            payer_ref: isStr(c.payer_ref) ? c.payer_ref : '', payee_ref: isStr(c.payee_ref) ? c.payee_ref : '',
            payer_name: isStr(c.payer_name) ? c.payer_name : '', payee_name: isStr(c.payee_name) ? c.payee_name : '' })) : [],
      control: { paused_by_ref: ctl.paused_by_ref, finished_by_ref: ctl.finished_by_ref, reason: ctl.reason },
      runtime_version: raw.runtime_version,
    },
  };
}
