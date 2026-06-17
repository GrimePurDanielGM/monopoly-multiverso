// Sesión anónima de Supabase. El uid (auth.uid) vive SOLO dentro del SDK para firmar
// peticiones; nunca se expone a la UI, al estado, a logs ni a payloads.
import { supabase } from './supabase';

export type SessionStatus = 'unconfigured' | 'loading' | 'ready' | 'error';

/** Garantiza una sesión anónima persistente. Idempotente: reutiliza la existente. */
export async function ensureAnonSession(): Promise<SessionStatus> {
  if (!supabase) return 'unconfigured';
  const { data } = await supabase.auth.getSession();
  if (data.session) return 'ready';
  const { error } = await supabase.auth.signInAnonymously();
  return error ? 'error' : 'ready';
}
