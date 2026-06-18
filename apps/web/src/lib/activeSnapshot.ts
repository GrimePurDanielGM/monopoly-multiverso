// Contrato saneado de get_active_snapshot_by_code + validación en runtime.
// Solo public_ref / ledger_ref: rechaza claves internas prohibidas (el id de sesión) y tipos inválidos.
import { hasForbiddenKey } from './snapshot';

export type LedgerKind =
  | 'seed' | 'late_join_seed' | 'bank_to_player' | 'player_to_bank' | 'player_to_player'
  | 'host_player_transfer' | 'host_adjust' | 'host_revert';

export interface ActiveConfig {
  initial_money: number;
  min_players: number;
  max_players: number;
  allow_late_join: boolean;
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
}
export interface ActiveTurn {
  turn_number: number;
  current_player_ref: string;
  order: string[];
}
export interface ActivePlayer {
  public_ref: string;
  display_name: string;
  token_id: string | null;
  balance: number;
  is_current: boolean;
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
  late_join_requests: LateJoinRequest[];
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
]);

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
  if (!isObj(m) || !isStr(m.public_ref) || !isBool(m.is_host) || !isNum(m.balance) || !isBool(m.is_current)) return bad('me inválido');

  const t = raw.turn;
  if (!isObj(t) || !isNum(t.turn_number) || !isStr(t.current_player_ref) || !Array.isArray(t.order) || !t.order.every(isStr)) {
    return bad('turn inválido');
  }

  if (!Array.isArray(raw.players)) return bad('players ausente');
  const players: ActivePlayer[] = [];
  for (const p of raw.players) {
    if (!isObj(p) || !isStr(p.public_ref) || !isStr(p.display_name) || !isStrOrNull(p.token_id) || !isNum(p.balance) || !isBool(p.is_current)) {
      return bad('player inválido');
    }
    players.push({ public_ref: p.public_ref, display_name: p.display_name, token_id: p.token_id, balance: p.balance, is_current: p.is_current });
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

  if (!Array.isArray(raw.late_join_requests)) return bad('late_join_requests ausente');
  const late: LateJoinRequest[] = [];
  for (const l of raw.late_join_requests) {
    if (!isObj(l) || !isStr(l.request_ref) || !isStr(l.name) || !isStr(l.token) || !isStrOrNull(l.device_label)) {
      return bad('late_join inválido');
    }
    late.push({ request_ref: l.request_ref, name: l.name, token: l.token, device_label: l.device_label });
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
      game: { code: g.code, status: 'active', config: { initial_money: cfg.initial_money, min_players: cfg.min_players, max_players: cfg.max_players, allow_late_join: cfg.allow_late_join } },
      me: { public_ref: m.public_ref, is_host: m.is_host, balance: m.balance, is_current: m.is_current },
      turn: { turn_number: t.turn_number, current_player_ref: t.current_player_ref, order: t.order as string[] },
      players,
      ledger_recent: ledger,
      late_join_requests: late,
      runtime_status: rs,
      control: { paused_by_ref: ctl.paused_by_ref, finished_by_ref: ctl.finished_by_ref, reason: ctl.reason },
      runtime_version: raw.runtime_version,
    },
  };
}
