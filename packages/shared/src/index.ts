/**
 * Tipos y contratos compartidos entre web y servidor.
 * En Fase 0 solo se define el contrato del healthcheck. Los tipos de la base de
 * datos se generarán con `supabase gen types typescript` cuando exista esquema.
 */
export interface HealthcheckResponse {
  readonly ok: true;
  readonly engine: { name: string; version: string; checksum: number };
  readonly serverTime: string;
}

/* ───────────────── Fase 1 — DTOs de lobby (contratos cliente↔servidor) ─────────────────
 * Ninguno expone auth_uid ni secretos. Los clientes referencian jugadores por public_ref.
 */
export type GameStatus = 'lobby' | 'active' | 'cancelled';
export type PlayerJoinStatus = 'joined' | 'ready';
export type RequestStatus = 'pending' | 'approved' | 'rejected' | 'cancelled' | 'expired';

export interface TokenOption { readonly id: string; readonly label: string; readonly icon: string; }

/** Vista pública de jugador (sin uuid interno ni auth_uid). */
export interface PlayerPublic {
  readonly public_ref: string;
  readonly name: string;
  readonly token_id: string | null;
  readonly status: PlayerJoinStatus;
  readonly kicked: boolean;
}

/** Respuesta de peek_game: información mínima previa a unirse. */
export interface PeekGame {
  readonly name: string;
  readonly status: GameStatus;
  readonly player_count: number;
  readonly max_players: number;
  readonly open_slots: number;
  readonly accepts_entries: boolean;
  readonly available_tokens: readonly TokenOption[];
  readonly players: readonly PlayerPublic[];
}

export interface CreateGameRequest {
  readonly name: string; readonly host_name: string; readonly host_token: string | null;
  readonly config?: Record<string, unknown>; readonly request_id: string; readonly pin: string;
}
export interface CreateGameResponse { readonly game_id: string; readonly code: string; readonly host_public_ref: string; readonly idempotent: boolean; }
export interface StartGameResponse { readonly status: GameStatus; readonly turn_order: string[]; readonly idempotent: boolean; }
export interface RequestRef { readonly request_ref: string; readonly status: RequestStatus; }
export interface RequestStatusResponse { readonly kind: 'recovery' | 'reentry'; readonly status: RequestStatus; }
export type MyStatus = 'active' | 'kicked' | 'not_member';

/** Códigos de error que devuelven las RPC (errcode/sqlerrm). */
export type LobbyErrorCode =
  | 'NOT_AUTHENTICATED' | 'GAME_NOT_FOUND' | 'GAME_NOT_JOINABLE' | 'GAME_CANCELLED' | 'GAME_FULL'
  | 'NAME_TAKEN' | 'INVALID_NAME' | 'TOKEN_TAKEN' | 'TOKEN_INVALID' | 'INCOMPLETE_PLAYER'
  | 'NOT_ACTIVE_MEMBER' | 'NOT_HOST' | 'NOT_IN_LOBBY' | 'CANNOT_KICK_HOST' | 'VERSION_CONFLICT'
  | 'INVALID_PLAYER_LIMITS' | 'MAX_EXCEEDS_TOKENS' | 'NOT_ENOUGH_PLAYERS' | 'PLAYERS_INCOMPLETE'
  | 'PENDING_RECOVERIES' | 'KICKED_NEEDS_REENTRY' | 'KICKED_USE_REENTRY' | 'NOT_KICKED'
  | 'SESSION_HAS_ACTIVE_PLAYER' | 'TARGET_NOT_FOUND' | 'REQUEST_NOT_FOUND' | 'WEAK_PIN'
  | 'INVALID_PIN' | 'LOCKED';
