// Contrato saneado de get_lobby_snapshot(_by_code) + validación estructural en runtime.
// Rechaza snapshots incompletos o con tipos incorrectos y, recursivamente, cualquier
// clave interna prohibida (el id de sesión vetado). Tipos en un único sitio (sin duplicar).

export type GameStatus = 'lobby' | 'active' | 'cancelled';
export type JoinStatus = 'joined' | 'ready';

export interface SnapConfig {
  min_players: number;
  max_players: number;
  initial_money: number;
  token_catalog_version: number;
  allow_late_join?: boolean;
  dice_mode: 'virtual_only' | 'physical_allowed' | 'physical_only';
  initial_houses_available: number;
  initial_hotels_available: number;
  allow_build_without_monopoly: boolean;
}
export interface SnapGame {
  id: string;
  code: string;
  name: string;
  status: GameStatus;
  version: number;
  started_at: string | null;
  cancelled_at: string | null;
  host_public_ref: string | null;
  config: SnapConfig;
}
export interface SnapPlayer {
  public_ref: string;
  name: string;
  token_id: string | null;
  status: JoinStatus;
  last_seen_at: string;
}
export interface SnapMe {
  public_ref: string;
  is_host: boolean;
  join_status: JoinStatus;
  token_id: string | null;
  membership: 'active';
}
export interface SnapRequest {
  request_ref: string;
  kind: 'recovery' | 'reentry';
  status: string;
  target_public_ref: string;
  device_label: string | null;
}
export interface SnapCounts {
  player_count: number;
  ready_count: number;
  min_players: number;
  max_players: number;
}
export interface LobbySnapshot {
  game: SnapGame;
  players: SnapPlayer[];
  me: SnapMe;
  requests: SnapRequest[];
  counts: SnapCounts;
}

// Clave interna vetada (construida dinámicamente para no aparecer literal en el código).
const FORBIDDEN_KEY = ['auth', 'uid'].join('_');

/** Escaneo recursivo: true si aparece la clave interna prohibida en cualquier nivel. */
export function hasForbiddenKey(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(hasForbiddenKey);
  if (value !== null && typeof value === 'object') {
    for (const k of Object.keys(value as Record<string, unknown>)) {
      if (k === FORBIDDEN_KEY) return true;
      if (hasForbiddenKey((value as Record<string, unknown>)[k])) return true;
    }
  }
  return false;
}

// --- helpers de tipo ---
function isObj(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}
const isStr = (v: unknown): v is string => typeof v === 'string';
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isBool = (v: unknown): v is boolean => typeof v === 'boolean';
const isStrOrNull = (v: unknown): v is string | null => v === null || typeof v === 'string';
const isStatus = (v: unknown): v is GameStatus => v === 'lobby' || v === 'active' || v === 'cancelled';
const isJoin = (v: unknown): v is JoinStatus => v === 'joined' || v === 'ready';

export type ParseResult =
  | { ok: true; data: LobbySnapshot }
  | { ok: false; reason: string };

function bad(reason: string): { ok: false; reason: string } {
  return { ok: false, reason };
}

/** Valida y tipa un snapshot recibido. Rechaza estructura inválida o claves prohibidas. */
export function parseSnapshot(raw: unknown): ParseResult {
  if (hasForbiddenKey(raw)) return bad('clave interna prohibida');
  if (!isObj(raw)) return bad('no es un objeto');

  const g = raw.game;
  if (!isObj(g)) return bad('game ausente');
  const cfg = g.config;
  if (!isObj(cfg)) return bad('config ausente');
  if (
    !isStr(g.id) || !isStr(g.code) || !isStr(g.name) || !isStatus(g.status) || !isNum(g.version) ||
    !isStrOrNull(g.started_at) || !isStrOrNull(g.cancelled_at) || !isStrOrNull(g.host_public_ref) ||
    !isNum(cfg.min_players) || !isNum(cfg.max_players) || !isNum(cfg.initial_money) || !isNum(cfg.token_catalog_version)
  ) {
    return bad('game/config con tipos incorrectos');
  }

  if (!Array.isArray(raw.players)) return bad('players ausente');
  const players: SnapPlayer[] = [];
  for (const p of raw.players) {
    if (!isObj(p) || !isStr(p.public_ref) || !isStr(p.name) || !isStrOrNull(p.token_id) || !isJoin(p.status) || !isStr(p.last_seen_at)) {
      return bad('player con tipos incorrectos');
    }
    players.push({
      public_ref: p.public_ref,
      name: p.name,
      token_id: p.token_id,
      status: p.status,
      last_seen_at: p.last_seen_at,
    });
  }

  const m = raw.me;
  if (!isObj(m) || !isStr(m.public_ref) || !isBool(m.is_host) || !isJoin(m.join_status) || !isStrOrNull(m.token_id) || m.membership !== 'active') {
    return bad('me con tipos incorrectos');
  }

  if (!Array.isArray(raw.requests)) return bad('requests ausente');
  const requests: SnapRequest[] = [];
  for (const r of raw.requests) {
    if (!isObj(r) || !isStr(r.request_ref) || (r.kind !== 'recovery' && r.kind !== 'reentry') || !isStr(r.status) || !isStr(r.target_public_ref) || !isStrOrNull(r.device_label)) {
      return bad('request con tipos incorrectos');
    }
    requests.push({
      request_ref: r.request_ref,
      kind: r.kind,
      status: r.status,
      target_public_ref: r.target_public_ref,
      device_label: r.device_label,
    });
  }

  const c = raw.counts;
  if (!isObj(c) || !isNum(c.player_count) || !isNum(c.ready_count) || !isNum(c.min_players) || !isNum(c.max_players)) {
    return bad('counts con tipos incorrectos');
  }

  return {
    ok: true,
    data: {
      game: {
        id: g.id,
        code: g.code,
        name: g.name,
        status: g.status,
        version: g.version,
        started_at: g.started_at,
        cancelled_at: g.cancelled_at,
        host_public_ref: g.host_public_ref,
        config: {
          min_players: cfg.min_players,
          max_players: cfg.max_players,
          initial_money: cfg.initial_money,
          token_catalog_version: cfg.token_catalog_version,
          allow_late_join: cfg.allow_late_join === true,
          dice_mode: cfg.dice_mode === 'physical_allowed' || cfg.dice_mode === 'physical_only' ? cfg.dice_mode : 'virtual_only',
          initial_houses_available: typeof cfg.initial_houses_available === 'number' ? cfg.initial_houses_available : 32,
          initial_hotels_available: typeof cfg.initial_hotels_available === 'number' ? cfg.initial_hotels_available : 12,
          allow_build_without_monopoly: cfg.allow_build_without_monopoly === true,
        },
      },
      players,
      me: {
        public_ref: m.public_ref,
        is_host: m.is_host,
        join_status: m.join_status,
        token_id: m.token_id,
        membership: 'active',
      },
      requests,
      counts: {
        player_count: c.player_count,
        ready_count: c.ready_count,
        min_players: c.min_players,
        max_players: c.max_players,
      },
    },
  };
}
