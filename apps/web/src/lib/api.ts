// Capa de acceso a datos del lobby. El navegador NUNCA hace SELECT directo sobre
// players/games/host_recovery/audit_events/solicitudes: solo RPC saneadas y Edge Functions.
// Ningún tipo aquí contiene el uid de sesión ni columnas internas.
import { FunctionsHttpError } from '@supabase/supabase-js';
import { supabase } from './supabase';
import { messageForError } from './errors';
import { parseSnapshot, type LobbySnapshot } from './snapshot';
import { parseActiveSnapshot, type ActiveSnapshot } from './activeSnapshot';
import type { RequestKind, RequestStatus } from './requestState';

export type ApiOk<T> = { ok: true; data: T };
export type ApiErr = { ok: false; code: string; message: string };
export type ApiResult<T> = ApiOk<T> | ApiErr;

function fail(code: string): ApiErr {
  return { ok: false, code, message: messageForError(code) };
}

// ---- Tipos de retorno (saneados: solo datos públicos) ----
export interface CreateGameResult {
  game_id: string;
  code: string;
  host_public_ref: string;
  idempotent: boolean;
}

export interface PublicToken {
  id: string;
  label: string;
  icon: string;
}

export interface PublicPlayer {
  public_ref: string;
  name: string;
  token_id: string | null;
  status: string;
  kicked: boolean;
}

export interface PeekGameResult {
  name: string;
  status: 'lobby' | 'active' | 'cancelled';
  player_count: number;
  max_players: number;
  open_slots: number;
  accepts_entries: boolean;
  allow_late_join: boolean;
  available_tokens: PublicToken[];
  players: PublicPlayer[];
}

export interface JoinGameResult {
  public_ref: string;
  name: string;
  token_id: string | null;
  status: string;
  kicked: boolean;
}

export interface CreateGameInput {
  name: string;
  host_name: string;
  pin: string;
  /** Ficha del anfitrión: id real de token_catalog (activo). Reservada en la creación atómica. */
  host_token: string;
  request_id: string;
}

/** Catálogo de fichas activas de la versión indicada (lectura directa permitida; token_catalog es público). */
export async function listActiveTokens(catalogVersion = 0): Promise<ApiResult<PublicToken[]>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase
    .from('token_catalog')
    .select('id,label,icon')
    .eq('active', true)
    .eq('catalog_version', catalogVersion)
    .order('sort_order', { ascending: true });
  if (error) return fail(error.message);
  return { ok: true, data: (data ?? []) as PublicToken[] };
}

/** Carga la sala por código (resuelve game_id de forma segura y devuelve el snapshot saneado). */
export async function getLobbySnapshotByCode(code: string): Promise<ApiResult<LobbySnapshot>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase.rpc('get_lobby_snapshot_by_code', { p_code: code });
  if (error) return fail(error.message);
  const parsed = parseSnapshot(data);
  if (!parsed.ok) return fail('INVALID_SNAPSHOT');
  return { ok: true, data: parsed.data };
}

/** Elige/cambia ficha (solo en lobby). El servidor valida; el cliente recarga el snapshot tras éxito. */
export async function chooseToken(gameId: string, tokenId: string): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('choose_token', { p_game: gameId, p_token: tokenId });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Marca preparado/no preparado. El servidor valida (INCOMPLETE_PLAYER, etc.). */
export async function setReady(gameId: string, ready: boolean): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('set_ready', { p_game: gameId, p_ready: ready });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Latido de presencia/liveness en servidor (actualiza last_seen_at). Idempotente y barato. */
export async function heartbeat(gameId: string): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('heartbeat', { p_game: gameId });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

// ---- Acciones del anfitrión (el backend valida NOT_HOST; la UI solo decide visibilidad) ----

/** Cambia la configuración del lobby con control de versión (concurrencia optimista). */
export async function updateConfig(
  gameId: string,
  patch: Record<string, unknown>,
  expectedVersion: number,
): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('update_config', {
    p_game: gameId,
    p_patch: patch,
    p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Expulsa a un jugador por su public_ref (nunca por id interno). */
export async function kickPlayer(gameId: string, targetRef: string): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('kick_player', { p_game: gameId, p_target_ref: targetRef });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Cancela la sala (idempotente). No es borrado físico. */
export async function cancelGame(gameId: string): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('cancel_game', { p_game: gameId });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Inicia la partida con control de versión. turn_order (ids internos) se DESCARTA. */
export async function startGame(gameId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('start_game', { p_game: gameId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Estado del llamante en la partida: 'active' | 'kicked' | 'not_member'. */
export async function getMyStatus(gameId: string): Promise<ApiResult<'active' | 'kicked' | 'not_member'>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase.rpc('my_status', { p_game: gameId });
  if (error) return fail(error.message);
  return { ok: true, data: data as 'active' | 'kicked' | 'not_member' };
}

// ---- Recuperaciones (Bloque 5) ----
export interface RequestRefResult {
  request_ref: string;
  status: RequestStatus;
}

/** Solicita recuperar una identidad ACTIVA (por public_ref) desde otro dispositivo. */
export async function requestRecovery(code: string, playerRef: string, device: string | null): Promise<ApiResult<RequestRefResult>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase.rpc('request_recovery', { p_code: code, p_player_ref: playerRef, p_device: device });
  if (error) return fail(error.message);
  return { ok: true, data: data as RequestRefResult };
}

/** Solicita reentrada (sesión expulsada) con un nombre nuevo. */
export async function requestReentry(code: string, name: string, device: string | null): Promise<ApiResult<RequestRefResult>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase.rpc('request_reentry', { p_code: code, p_name: name, p_device: device });
  if (error) return fail(error.message);
  return { ok: true, data: data as RequestRefResult };
}

/** Anfitrión: aprueba/rechaza una solicitud de recuperación. */
export async function resolveRecovery(requestRef: string, accept: boolean): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('resolve_recovery', { p_request_ref: requestRef, p_accept: accept });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Anfitrión: aprueba/rechaza una solicitud de reentrada. */
export async function resolveReentry(requestRef: string, accept: boolean): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('resolve_reentry', { p_request_ref: requestRef, p_accept: accept });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Sondeo del estado de una solicitud (sin uid). */
export async function getRequestStatus(requestRef: string): Promise<ApiResult<{ kind: RequestKind; status: RequestStatus }>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase.rpc('get_request_status', { p_request_ref: requestRef });
  if (error) return fail(error.message);
  return { ok: true, data: data as { kind: RequestKind; status: RequestStatus } };
}

export type RecoverHostResult =
  | { ok: true }
  | { ok: false; code: string; message: string; lockedUntil?: string; failedAttempts?: number };

/** Recuperación del rol de anfitrión por código + PIN (Edge; el PIN nunca toca la BD). */
export async function recoverHost(code: string, pin: string): Promise<RecoverHostResult> {
  if (!supabase) return { ok: false, code: 'UNCONFIGURED', message: messageForError('UNCONFIGURED') };
  const { data, error } = await supabase.functions.invoke<{ ok?: boolean }>('recover_host', { body: { code, pin } });
  if (!error && data?.ok) return { ok: true };
  let body: { error?: string; locked_until?: string; failed_attempts?: number } = {};
  if (error instanceof FunctionsHttpError) {
    try {
      body = (await error.context.json()) as typeof body;
    } catch {
      return { ok: false, code: 'NETWORK', message: messageForError('NETWORK') };
    }
  } else if (error) {
    return { ok: false, code: 'NETWORK', message: messageForError('NETWORK') };
  }
  const code2 = body.error ?? 'UNKNOWN';
  const res: RecoverHostResult = { ok: false, code: code2, message: messageForError(code2) };
  if (body.locked_until) res.lockedUntil = body.locked_until;
  if (typeof body.failed_attempts === 'number') res.failedAttempts = body.failed_attempts;
  return res;
}

/** Crea una partida vía Edge Function `create_game` (hashea el PIN con el pepper en el Edge). */
export async function createGame(input: CreateGameInput): Promise<ApiResult<CreateGameResult>> {
  if (!supabase) return fail('UNCONFIGURED');
  // La ficha del anfitrión se reserva DENTRO de la creación atómica (host_token), no después.
  const body = {
    name: input.name,
    host_name: input.host_name,
    host_token: input.host_token,
    config: {},
    request_id: input.request_id,
    pin: input.pin,
  };
  const { data, error } = await supabase.functions.invoke<CreateGameResult>('create_game', { body });
  if (error) {
    let code = 'UNKNOWN';
    if (error instanceof FunctionsHttpError) {
      try {
        const payload = (await error.context.json()) as { error?: string };
        code = payload.error ?? code;
      } catch {
        code = 'NETWORK';
      }
    } else {
      code = 'NETWORK';
    }
    return fail(code);
  }
  if (!data) return fail('UNKNOWN');
  return { ok: true, data };
}

/** Vista previa de una partida por código (pre-unión, sin pertenencia). */
export async function peekGame(code: string): Promise<ApiResult<PeekGameResult>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase.rpc('peek_game', { p_code: code });
  if (error) return fail(error.message);
  return { ok: true, data: data as PeekGameResult };
}

/** Une al jugador a la partida. La ficha se elige aparte (choose_token), no aquí. */
export async function joinGame(
  code: string,
  name: string,
  requestId: string,
): Promise<ApiResult<JoinGameResult>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase.rpc('join_game', {
    p_code: code,
    p_name: name,
    p_request_id: requestId,
  });
  if (error) return fail(error.message);
  return { ok: true, data: data as JoinGameResult };
}

// ============================================================================
// Fase 2 — Partida activa (banco, turnos, correcciones). Concurrencia por
// runtime_version; idempotencia por requestId. El snapshot es la única fuente.
// ============================================================================

/** Snapshot autoritativo de la partida activa (saneado: solo public_ref / ledger_ref). */
export async function getActiveSnapshotByCode(code: string): Promise<ApiResult<ActiveSnapshot>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase.rpc('get_active_snapshot_by_code', { p_code: code });
  if (error) return fail(error.message);
  const parsed = parseActiveSnapshot(data);
  if (!parsed.ok) return fail('SNAPSHOT_INVALID');
  return { ok: true, data: parsed.data };
}

/** Finaliza el turno (solo el jugador actual). */
export async function endTurn(gameId: string, expectedVersion: number, requestId: string): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('end_turn', { p_game: gameId, p_expected_version: expectedVersion, p_request_id: requestId });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Banca (solo anfitrión): banco↔jugador. dir = 'to_player' | 'from_player'. */
export async function bankTransfer(
  gameId: string, playerRef: string, direction: 'to_player' | 'from_player',
  amount: number, requestId: string, expectedVersion: number,
): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('bank_transfer', {
    p_game: gameId, p_player_ref: playerRef, p_direction: direction, p_amount: amount,
    p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Transferencia entre jugadores (paga el llamante; permitido en cualquier momento). */
export async function playerTransfer(
  gameId: string, toRef: string, amount: number, requestId: string, expectedVersion: number,
): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('player_transfer', {
    p_game: gameId, p_to_ref: toRef, p_amount: amount, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Corrección del anfitrión: transferencia en nombre de otro (motivo obligatorio). */
export async function hostPlayerTransfer(
  gameId: string, fromRef: string, toRef: string, amount: number, reason: string, requestId: string, expectedVersion: number,
): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('host_player_transfer', {
    p_game: gameId, p_from_ref: fromRef, p_to_ref: toRef, p_amount: amount, p_reason: reason,
    p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Corrección del anfitrión: fija el saldo de un jugador (motivo obligatorio). */
export async function hostAdjustBalance(
  gameId: string, targetRef: string, newBalance: number, reason: string, requestId: string, expectedVersion: number,
): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('host_adjust_balance', {
    p_game: gameId, p_target_ref: targetRef, p_new_balance: newBalance, p_reason: reason,
    p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Corrección del anfitrión: fija el turno a un jugador del orden (motivo obligatorio). */
export async function hostSetTurn(
  gameId: string, targetRef: string, reason: string, requestId: string, expectedVersion: number,
): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('host_set_turn', {
    p_game: gameId, p_target_ref: targetRef, p_reason: reason, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Corrección del anfitrión: revierte un movimiento por su ledger_ref (motivo obligatorio). */
export async function hostRevertMovement(
  gameId: string, ledgerRef: string, reason: string, requestId: string, expectedVersion: number,
): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('host_revert_movement', {
    p_game: gameId, p_ledger_ref: ledgerRef, p_reason: reason, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Control de la partida (solo anfitrión): pausar. */
export async function pauseGame(gameId: string, reason: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('pause_game_runtime', { p_game: gameId, p_reason: reason, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Control de la partida (solo anfitrión): reanudar. */
export async function resumeGame(gameId: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('resume_game_runtime', { p_game: gameId, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Control de la partida (solo anfitrión): finalizar (terminal). */
export async function finishGame(gameId: string, reason: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('finish_game_runtime', { p_game: gameId, p_reason: reason, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Incorporación tardía: una sesión nueva solicita entrar en una partida activa. */
export async function requestLateJoin(
  code: string, name: string, token: string, deviceLabel: string | null,
): Promise<ApiResult<{ request_ref: string; status: RequestStatus }>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase.rpc('request_late_join', { p_code: code, p_name: name, p_token: token, p_device_label: deviceLabel });
  if (error) return fail(error.message);
  return { ok: true, data: data as { request_ref: string; status: RequestStatus } };
}

/** Incorporación tardía: el anfitrión aprueba/rechaza una solicitud (con runtime_version). */
export async function resolveLateJoin(requestRef: string, accept: boolean, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('resolve_late_join', { p_request_ref: requestRef, p_accept: accept, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

export type ExitResolution = 'to_bank' | 'distribute';

/** Solicitud de abandono: el jugador la pide (salida directa solo si no tiene saldo ni propiedades). */
export async function requestLeaveActive(gameId: string, requestId: string): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('request_leave_active', { p_game: gameId, p_request_id: requestId });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Resuelve una solicitud de abandono (solo anfitrión): aprobar con destino del dinero, o rechazar. */
export async function resolveLeaveActive(requestRef: string, accept: boolean, resolution: ExitResolution, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('resolve_leave_active', { p_request_ref: requestRef, p_accept: accept, p_resolution_mode: resolution, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Expulsión (solo anfitrión): saca a un jugador y resuelve su saldo (banca o reparto). */
export async function removeActivePlayer(
  gameId: string, targetRef: string, resolution: ExitResolution, reason: string, requestId: string, expectedVersion: number,
): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('remove_active_player', {
    p_game: gameId, p_target_ref: targetRef, p_resolution_mode: resolution, p_reason: reason,
    p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Solicitud de compra: el jugador la pide; no cambia economía hasta que el anfitrión aprueba. */
export async function requestPropertyPurchase(gameId: string, propertyRef: string, requestId: string): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('request_property_purchase', { p_game: gameId, p_property_ref: propertyRef, p_request_id: requestId });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Resuelve una solicitud de compra (solo anfitrión): aprobar (cobra y asigna) o rechazar. */
export async function resolvePropertyPurchase(requestRef: string, accept: boolean, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('resolve_property_purchase', { p_request_ref: requestRef, p_accept: accept, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Subasta (solo anfitrión): inicia una subasta sobre una propiedad disponible. */
export async function startPropertyAuction(gameId: string, propertyRef: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('start_property_auction', { p_game: gameId, p_property_ref: propertyRef, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Puja en una subasta activa (jugador activo; importe > puja actual y ≤ saldo). */
export async function placePropertyBid(gameId: string, auctionRef: string, amount: number, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('place_property_bid', { p_game: gameId, p_auction_ref: auctionRef, p_amount: amount, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Cierra una subasta (solo anfitrión): adjudica al mayor postor o la deja sin adjudicar. */
export async function closePropertyAuction(gameId: string, auctionRef: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('close_property_auction', { p_game: gameId, p_auction_ref: auctionRef, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Cancela una subasta (solo anfitrión): la propiedad sigue disponible. */
export async function cancelPropertyAuction(gameId: string, auctionRef: string, reason: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('cancel_property_auction', { p_game: gameId, p_auction_ref: auctionRef, p_reason: reason, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

export type BankruptcyKind = 'to_bank' | 'to_player';

/** Solicitud de bancarrota: el propio jugador la pide (a banca o a un acreedor). */
export async function requestBankruptcy(gameId: string, kind: BankruptcyKind, creditorRef: string | null, reason: string, requestId: string): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('request_bankruptcy', { p_game: gameId, p_kind: kind, p_creditor_ref: creditorRef, p_reason: reason, p_request_id: requestId });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Resuelve una solicitud de bancarrota (solo anfitrión): aprobar o rechazar. */
export async function resolveBankruptcy(requestRef: string, accept: boolean, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('resolve_bankruptcy', { p_request_ref: requestRef, p_accept: accept, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Paga el alquiler base de una propiedad a su propietario activo. */
export async function payRent(gameId: string, propertyRef: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('pay_rent', {
    p_game: gameId, p_property_ref: propertyRef, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

// ── Movimiento (Fase 4) ────────────────────────────────────────────────────────────
/** Mueve manualmente al jugador actual N casillas (1..12). El resultado autoritativo llega por snapshot. */
export async function movePlayer(gameId: string, steps: number, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('move_player', {
    p_game: gameId, p_steps: steps, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Tira dos dados (1-6) y mueve la suma. La tirada y el movimiento llegan por snapshot (last_roll/last_move). */
export async function rollAndMove(gameId: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('roll_and_move', {
    p_game: gameId, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Mueve usando dados FÍSICOS (resultado introducido a mano). Sirve también como intento de cárcel.
 *  Requiere que el modo de dados permita físicos; el backend valida d1/d2 ∈ 1..6. */
export async function moveWithPhysicalRoll(gameId: string, die1: number, die2: number, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('move_with_physical_roll', {
    p_game: gameId, p_die1: die1, p_die2: die2, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Cambia el modo de dados de la partida (anfitrión; lobby o activa). */
export async function setDiceMode(gameId: string, mode: 'virtual_only' | 'physical_allowed' | 'physical_only', requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('set_dice_mode', {
    p_game: gameId, p_mode: mode, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Paga el alquiler de un SERVICIO (combinable entre tableros): tirada × multiplicador según servicios
 *  del propietario. Si die1/die2 son null usa la última tirada válida (o genera virtual si el modo lo permite). */
export async function payUtilityRent(gameId: string, propertyRef: string, die1: number | null, die2: number | null, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('pay_utility_rent', {
    p_game: gameId, p_property_ref: propertyRef, p_die1: die1, p_die2: die2, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Resuelve la bifurcación de la cárcel-guardián: 'own' (seguir en tu tablero) o 'cross' (cruzar al otro). */
export async function resolveJunction(gameId: string, direction: 'own' | 'cross', requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('resolve_junction', {
    p_game: gameId, p_direction: direction, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

// ── Fase 5 — casillas especiales (cárcel, cartas, pago pendiente) ──

/** Salir de la cárcel pagando la multa (50). */
export async function payJailRelease(gameId: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('pay_jail_release', { p_game: gameId, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Salir de la cárcel usando una carta "Sal de la cárcel gratis". */
export async function redeemJailCard(gameId: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('use_jail_card', { p_game: gameId, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Marcar como resuelta una carta de resolución manual. */
export async function resolveCard(gameId: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('resolve_card', { p_game: gameId, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** Pagar un impuesto que quedó pendiente por falta de saldo. */
export async function payPending(gameId: string, requestId: string, expectedVersion: number): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('pay_pending', { p_game: gameId, p_request_id: requestId, p_expected_version: expectedVersion });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}

/** El anfitrión corrige la posición de un jugador (motivo obligatorio; no cobra salida ni dispara acciones). */
export async function hostSetPlayerPosition(
  gameId: string, playerRef: string, boardKey: string, spaceIndex: number,
  reason: string, requestId: string, expectedVersion: number,
): Promise<ApiResult<true>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { error } = await supabase.rpc('host_set_player_position', {
    p_game: gameId, p_player_ref: playerRef, p_board_key: boardKey, p_space_index: spaceIndex,
    p_reason: reason, p_request_id: requestId, p_expected_version: expectedVersion,
  });
  if (error) return fail(error.message);
  return { ok: true, data: true };
}
