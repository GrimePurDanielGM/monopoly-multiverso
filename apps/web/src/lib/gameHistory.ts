// Historial LOCAL de partidas por dispositivo (localStorage). Guarda solo una referencia SANEADA
// para que el usuario no tenga que recordar el código: code, rol aproximado, nombre usado, estado
// último conocido, título y última vez vista. NUNCA persiste secretos: ni PIN, ni host_token, ni
// el identificador interno de sesión, ni ids internos (la API pública solo acepta los campos
// saneados). Falla en silencio (mismo patrón que cashSound): cualquier error de almacenamiento se ignora.

export type HistoryRole = 'host' | 'player' | 'spectator' | 'unknown';
export type HistoryStatus = 'lobby' | 'active' | 'paused' | 'finished' | 'unknown';

export interface GameHistoryEntry {
  code: string;
  role: HistoryRole;
  display_name: string | null;
  status: HistoryStatus;
  game_title: string | null;
  last_seen_at: string; // ISO 8601
}

/** Campos que el llamador puede aportar al registrar/actualizar una partida (todos opcionales salvo code). */
export interface RememberGameInput {
  code: string;
  role?: HistoryRole;
  display_name?: string | null;
  status?: HistoryStatus;
  game_title?: string | null;
}

const KEY = 'game_history';
const MAX = 24;
const ROLES: ReadonlySet<string> = new Set(['host', 'player', 'spectator', 'unknown']);
const STATUSES: ReadonlySet<string> = new Set(['lobby', 'active', 'paused', 'finished', 'unknown']);
const CODE_RE = /^[A-Z0-9]{6}$/;

const isStr = (v: unknown): v is string => typeof v === 'string';
const strOrNull = (v: unknown): string | null => (isStr(v) ? v : null);

/** Valida y sanea una entrada cruda del almacenamiento (descarta lo que no encaje). */
function coerce(raw: unknown): GameHistoryEntry | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;
  if (!isStr(o.code) || !CODE_RE.test(o.code)) return null;
  if (!isStr(o.last_seen_at)) return null;
  return {
    code: o.code,
    role: isStr(o.role) && ROLES.has(o.role) ? (o.role as HistoryRole) : 'unknown',
    display_name: strOrNull(o.display_name),
    status: isStr(o.status) && STATUSES.has(o.status) ? (o.status as HistoryStatus) : 'unknown',
    game_title: strOrNull(o.game_title),
    last_seen_at: o.last_seen_at,
  };
}

/** Lee el historial local, ya saneado y ordenado por más reciente primero. Falla en silencio → []. */
export function loadGameHistory(): GameHistoryEntry[] {
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    const entries = parsed.map(coerce).filter((e): e is GameHistoryEntry => e !== null);
    // Dedup por código (por si hubiera duplicados) y orden por recencia.
    const byCode = new Map<string, GameHistoryEntry>();
    for (const e of entries) if (!byCode.has(e.code)) byCode.set(e.code, e);
    return [...byCode.values()].sort((a, b) => b.last_seen_at.localeCompare(a.last_seen_at));
  } catch {
    return [];
  }
}

function persist(entries: GameHistoryEntry[]): void {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(entries.slice(0, MAX)));
  } catch {
    /* sin almacenamiento: se ignora */
  }
}

/** Registra o actualiza (upsert) una partida en el historial. Fusiona con lo ya conocido: los campos
 *  no aportados se conservan. Actualiza siempre last_seen_at. Solo persiste campos saneados. */
export function rememberGame(input: RememberGameInput): void {
  if (!isStr(input.code) || !CODE_RE.test(input.code)) return;
  const now = new Date().toISOString();
  const list = loadGameHistory();
  const prev = list.find((e) => e.code === input.code) ?? null;
  const merged: GameHistoryEntry = {
    code: input.code,
    role: input.role ?? prev?.role ?? 'unknown',
    display_name: input.display_name !== undefined ? input.display_name : prev?.display_name ?? null,
    status: input.status ?? prev?.status ?? 'unknown',
    game_title: input.game_title !== undefined ? input.game_title : prev?.game_title ?? null,
    last_seen_at: now,
  };
  const rest = list.filter((e) => e.code !== input.code);
  persist([merged, ...rest]);
}

/** Elimina una partida del historial local. */
export function forgetGame(code: string): void {
  persist(loadGameHistory().filter((e) => e.code !== code));
}

/** Mapea el estado del snapshot de sala (lobby/active/cancelled) al estado de historial. */
export function statusFromLobby(s: 'lobby' | 'active' | 'cancelled'): HistoryStatus {
  return s === 'cancelled' ? 'finished' : s;
}

/** Etiqueta legible del estado para la UI del historial. */
export function historyStatusLabel(s: HistoryStatus): string {
  switch (s) {
    case 'lobby': return 'En sala';
    case 'active': return 'En curso';
    case 'paused': return 'En pausa';
    case 'finished': return 'Finalizada';
    default: return 'Desconocido';
  }
}
