/**
 * Monopoly: El Multiverso — Motor de reglas (núcleo).
 *
 * REGLA ARQUITECTÓNICA: este paquete es la ÚNICA fuente de verdad de la lógica.
 * Debe ser puro e isomórfico: sin dependencias, sin APIs específicas de Node ni
 * de Deno, para poder importarse idénticamente desde la web (Vite/Node) y desde
 * las Edge Functions (Deno). En Fase 0 NO contiene reglas de Monopoly: solo una
 * función trivial que sirve para demostrar el reparto cliente/servidor.
 */

export const ENGINE_NAME = 'monopoly-multiverso-engine';
export const ENGINE_VERSION = '0.0.0';

export interface EngineFingerprint {
  readonly name: string;
  readonly version: string;
  readonly checksum: number;
}

/** Checksum determinista (FNV-like) — mismo input => mismo output en cualquier runtime. */
export function engineFingerprint(): EngineFingerprint {
  const seed = `${ENGINE_NAME}@${ENGINE_VERSION}`;
  let hash = 0;
  for (let i = 0; i < seed.length; i += 1) {
    hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
  }
  return { name: ENGINE_NAME, version: ENGINE_VERSION, checksum: hash };
}

/* ───────────────────────── Fase 1 — Helpers PUROS de lobby ─────────────────────────
 * NO son autoridad: el servidor (RPC/Edge) revalida todo. Sirven para previsualización
 * en cliente y para compartir constantes/validaciones idénticas en web y Edge.
 */

/** Alfabeto sin caracteres ambiguos (sin 0/O/1/I/L). Debe coincidir con el generador SQL. */
export const GAME_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const GAME_CODE_LENGTH = 6;

export function isValidGameCode(code: string): boolean {
  if (typeof code !== 'string') return false;
  const c = code.trim().toUpperCase();
  if (c.length !== GAME_CODE_LENGTH) return false;
  for (const ch of c) if (!GAME_CODE_ALPHABET.includes(ch)) return false;
  return true;
}

/** Espejo de normalize_name() en SQL: trim + colapsar espacios internos + minúsculas. */
export function normalizeName(input: string): string {
  return input.trim().replace(/\s+/g, ' ').toLowerCase();
}

export function isValidPlayerName(name: string): boolean {
  const n = name.trim();
  return n.length >= 2 && n.length <= 24;
}

/** PIN de host: exactamente 6 dígitos y no trivial. Debe coincidir con isWeakPin del Edge. */
export function isWeakPin(pin: string): boolean {
  if (!/^\d{6}$/.test(pin)) return true;
  if (/^(\d)\1{5}$/.test(pin)) return true; // seis dígitos iguales
  if (pin === '123456') return true;
  return false;
}

export interface LobbyPlayer {
  readonly tokenId: string | null;
  readonly ready: boolean;
  readonly name: string;
  readonly kicked: boolean;
}
export interface StartEligibility {
  readonly canStart: boolean;
  readonly reasons: readonly string[];
}

/** Previsualización de elegibilidad de inicio (la decisión final es de start_game en servidor). */
export function evaluateStart(players: readonly LobbyPlayer[], minPlayers: number): StartEligibility {
  const active = players.filter((p) => !p.kicked);
  const reasons: string[] = [];
  if (active.length < minPlayers) reasons.push('NOT_ENOUGH_PLAYERS');
  if (active.some((p) => !p.tokenId)) reasons.push('PLAYER_WITHOUT_TOKEN');
  if (active.some((p) => !p.ready)) reasons.push('PLAYER_NOT_READY');
  if (active.some((p) => !isValidPlayerName(p.name))) reasons.push('PLAYER_INVALID_NAME');
  return { canStart: reasons.length === 0, reasons };
}
