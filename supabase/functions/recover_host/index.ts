import { createClient } from 'npm:@supabase/supabase-js@2';
import { verifyPin } from '../_shared/pbkdf2.ts';
import { jsonCors, preflight } from '../_shared/cors.ts';

// Log seguro: nunca imprime JWT, PIN, pepper, hashes ni claves.
function logSafe(stage: string, detail: Record<string, unknown> = {}) {
  console.log(`[recover_host] ${stage} ${JSON.stringify(detail)}`);
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  // Preflight CORS: responder ANTES de cualquier otra lógica.
  if (req.method === 'OPTIONS') return preflight(origin);
  // Cierre sobre `origin`: todas las respuestas (incluidos errores) llevan CORS.
  const json = (body: unknown, status: number) => jsonCors(body, status, origin);
  try {
    // 1) Entorno disponible en el runtime (sin exponer valores).
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY');
    const pepper = Deno.env.get('HOST_PIN_PEPPER');
    const envOk = { url: !!SUPABASE_URL, service_role: !!SERVICE_KEY, anon: !!ANON_KEY, pepper: !!pepper };
    if (!SUPABASE_URL || !SERVICE_KEY || !ANON_KEY || !pepper) {
      logSafe('SERVER_MISCONFIGURED', { envOk });           // qué falta, sin valores
      return json({ error: 'SERVER_MISCONFIGURED', envOk }, 500);
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) return json({ error: 'NOT_AUTHENTICATED' }, 401);

    const body = await req.json().catch(() => null);
    const rawCode = body?.code;
    const pin = body?.pin;
    if (typeof rawCode !== 'string' || typeof pin !== 'string') return json({ error: 'BAD_REQUEST' }, 400);
    // 2) Normalización: trim + uppercase.
    const code = rawCode.trim().toUpperCase();
    if (code.length === 0) return json({ error: 'BAD_REQUEST' }, 400);

    // 3) uid del solicitante (sesión nueva) desde SU JWT (cliente autenticado SOLO para esto).
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authHeader } },
    });
    const { data: u, error: userErr } = await userClient.auth.getUser();
    if (userErr || !u?.user?.id) {
      logSafe('NOT_AUTHENTICATED', { hasUserErr: !!userErr });
      return json({ error: 'NOT_AUTHENTICATED' }, 401);
    }
    const newUid = u.user.id;

    // 4) Cliente de SERVICIO: service_role explícito en cabeceras => bypassa RLS.
    //    Nunca consulta con el cliente del usuario (RLS ocultaría la partida a la sesión nueva).
    const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${SERVICE_KEY}`, apikey: SERVICE_KEY } },
    });

    // 5) Buscar la partida por games.code. Distinguir error de "no existe".
    const gameQ = await admin.from('games').select('id, code').eq('code', code).maybeSingle();
    if (gameQ.error) {
      logSafe('LOOKUP_FAILED games', { code, pgcode: gameQ.error.code, msg: gameQ.error.message });
      return json({ error: 'LOOKUP_FAILED', where: 'games', pgcode: gameQ.error.code }, 500);
    }
    if (!gameQ.data) {
      logSafe('GAME_NOT_FOUND', { code });                  // consulta OK y 0 filas
      return json({ error: 'GAME_NOT_FOUND' }, 404);
    }
    const gameId = gameQ.data.id;

    const hrQ = await admin.from('host_recovery').select('*').eq('game_id', gameId).maybeSingle();
    if (hrQ.error) {
      logSafe('LOOKUP_FAILED host_recovery', { code, pgcode: hrQ.error.code, msg: hrQ.error.message });
      return json({ error: 'LOOKUP_FAILED', where: 'host_recovery', pgcode: hrQ.error.code }, 500);
    }
    if (!hrQ.data) { logSafe('NO_RECOVERY', { code }); return json({ error: 'NO_RECOVERY' }, 404); }
    const hr = hrQ.data;

    // 6) Bloqueo temporal.
    if (hr.locked_until && new Date(hr.locked_until) > new Date()) {
      logSafe('LOCKED', { code, locked_until: hr.locked_until });
      return json({ error: 'LOCKED', locked_until: hr.locked_until }, 423);
    }

    // 7) Verificación del PIN en tiempo constante (pepper solo en memoria).
    const ok = await verifyPin(pin, pepper, { hash: hr.pin_hash, salt: hr.pin_salt, algo: hr.algo, iterations: hr.iterations });
    if (!ok) {
      const fail = await admin.rpc('host_recovery_fail', { p_code: code });
      if (fail.error) {
        logSafe('LOOKUP_FAILED host_recovery_fail', { code, pgcode: fail.error.code, msg: fail.error.message });
        return json({ error: 'LOOKUP_FAILED', where: 'host_recovery_fail', pgcode: fail.error.code }, 500);
      }
      logSafe('INVALID_PIN', { code, failed_attempts: fail.data?.failed_attempts });
      return json({ error: 'INVALID_PIN', ...fail.data }, 401);
    }

    // 8) Reasignación atómica del host a la sesión nueva (RPC de service_role).
    const success = await admin.rpc('host_recovery_success', { p_code: code, p_new_uid: newUid });
    if (success.error) {
      logSafe('RPC_FAILED host_recovery_success', { code, pgcode: success.error.code, msg: success.error.message });
      // SESSION_HAS_ACTIVE_PLAYER u otros errores de la RPC: propagar, no ocultar.
      return json({ error: success.error.message || 'RPC_FAILED' }, 400);
    }
    logSafe('OK', { code });
    return json(success.data, 200);
  } catch (e) {
    logSafe('UNEXPECTED', { msg: e instanceof Error ? e.message : String(e) });
    return json({ error: 'UNEXPECTED' }, 500);
  }
});
