// Capa de acceso a datos del lobby. El navegador NUNCA hace SELECT directo sobre
// players/games/host_recovery/audit_events/solicitudes: solo RPC saneadas y Edge Functions.
// Ningún tipo aquí contiene el uid de sesión ni columnas internas.
import { FunctionsHttpError } from '@supabase/supabase-js';
import { supabase } from './supabase';
import { messageForError } from './errors';

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

/** Catálogo provisional de fichas activas (lectura directa permitida; token_catalog es público). */
export async function listActiveTokens(): Promise<ApiResult<PublicToken[]>> {
  if (!supabase) return fail('UNCONFIGURED');
  const { data, error } = await supabase
    .from('token_catalog')
    .select('id,label,icon')
    .eq('active', true)
    .eq('catalog_version', 0)
    .order('sort_order', { ascending: true });
  if (error) return fail(error.message);
  return { ok: true, data: (data ?? []) as PublicToken[] };
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
