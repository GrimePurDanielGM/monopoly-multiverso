// Contrato saneado de get_active_snapshot_by_code + validación en runtime.
// Solo public_ref / ledger_ref: rechaza claves internas prohibidas (el id de sesión) y tipos inválidos.
import { hasForbiddenKey } from './snapshot';

export type LedgerKind =
  | 'seed' | 'late_join_seed' | 'bank_to_player' | 'player_to_bank' | 'player_to_player'
  | 'host_player_transfer' | 'host_adjust' | 'host_revert'
  | 'player_exit_to_bank' | 'player_exit_distribution' | 'player_exit_remainder_to_bank'
  | 'property_purchase' | 'rent_payment' | 'property_auction_purchase'
  | 'bankruptcy_cash_to_bank' | 'bankruptcy_cash_to_player'
  | 'pass_start_bonus';

export type BoardKey = 'classic' | 'back_to_the_future';
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

export interface ActiveConfig {
  initial_money: number;
  min_players: number;
  max_players: number;
  allow_late_join: boolean;
  start_bonus: number;
}

// ── Fase 4: tablero, casillas y posiciones ────────────────────────────────────────
export interface BoardInfo {
  board_key: BoardKey;
  ring_size: number;
  start_bonus: number;
}
export interface BoardSpace {
  space_ref: string;
  board_key: BoardKey;
  space_index: number;
  name: string;
  space_type: SpaceType;
  property_ref: string | null;
  is_start: boolean;
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
export interface LastRoll {
  d1: number;
  d2: number;
  total: number;
  player_ref: string;
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
}
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
  balance: number;
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
  positions: PlayerPosition[];
  my_position: MyPosition | null;
  current_space: CurrentSpace | null;
  last_roll: LastRoll | null;
  last_move: LastMove | null;
  runtime_status: RuntimeStatus;
  control: ActiveControl;
  runtime_version: number;
}

function isObj(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}
const isStr = (v: unknown): v is string => typeof v === 'string';
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isBool = (v: unknown): v is boolean => typeof v === 'boolean';
const isStrOrNull = (v: unknown): v is string | null => v === null || typeof v === 'string';
const isNumOrNull = (v: unknown): v is number | null => v === null || isNum(v);

const KINDS: ReadonlySet<string> = new Set([
  'seed', 'late_join_seed', 'bank_to_player', 'player_to_bank', 'player_to_player', 'host_player_transfer', 'host_adjust', 'host_revert',
  'player_exit_to_bank', 'player_exit_distribution', 'player_exit_remainder_to_bank',
  'property_purchase', 'rent_payment', 'property_auction_purchase', 'bankruptcy_cash_to_bank', 'bankruptcy_cash_to_player',
  'pass_start_bonus',
]);
const BOARDS: ReadonlySet<string> = new Set(['classic', 'back_to_the_future']);
const PKINDS: ReadonlySet<string> = new Set(['street', 'station', 'transport', 'utility', 'special']);
const SPACE_TYPES: ReadonlySet<string> = new Set(['start', 'property', 'tax', 'card', 'jail', 'go_to_jail', 'parking', 'special']);
const isBoard = (v: unknown): v is BoardKey => v === 'classic' || v === 'back_to_the_future';

function parseSpaceLike(s: Record<string, unknown>): BoardSpace | null {
  if (!isStr(s.space_ref) || !isBoard(s.board_key) || !isNum(s.space_index) || !isStr(s.name) ||
      !isStr(s.space_type) || !SPACE_TYPES.has(s.space_type) || !isStrOrNull(s.property_ref) || !isBool(s.is_start)) {
    return null;
  }
  return {
    space_ref: s.space_ref, board_key: s.board_key, space_index: s.space_index, name: s.name,
    space_type: s.space_type as SpaceType, property_ref: s.property_ref, is_start: s.is_start,
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
    if (!isObj(p) || !isStr(p.public_ref) || !isStr(p.display_name) || !isStrOrNull(p.token_id) || !isNum(p.balance) || !isBool(p.is_current) ||
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
    properties.push({
      property_ref: p.property_ref, board_key: p.board_key as BoardKey, group_key: p.group_key, name: p.name,
      kind: p.kind as PropertyKind, price: p.price, base_rent: p.base_rent, is_buyable: p.is_buyable,
      sort_order: p.sort_order, owner_ref: p.owner_ref, in_auction: p.in_auction,
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
      boards.push({ board_key: b.board_key, ring_size: b.ring_size, start_bonus: b.start_bonus });
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
    lastRoll = { d1: lr.d1, d2: lr.d2, total: lr.total, player_ref: lr.player_ref };
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
    };
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
      game: { code: g.code, status: 'active', config: { initial_money: cfg.initial_money, min_players: cfg.min_players, max_players: cfg.max_players, allow_late_join: cfg.allow_late_join, start_bonus: isNum(cfg.start_bonus) ? cfg.start_bonus : 200 } },
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
      positions,
      my_position: myPosition,
      current_space: currentSpace,
      last_roll: lastRoll,
      last_move: lastMove,
      runtime_status: rs,
      control: { paused_by_ref: ctl.paused_by_ref, finished_by_ref: ctl.finished_by_ref, reason: ctl.reason },
      runtime_version: raw.runtime_version,
    },
  };
}
