import { createClient } from 'npm:@supabase/supabase-js@2';
import { hashPin, isWeakPin } from '../_shared/pbkdf2.ts';
import { jsonCors, preflight } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  // Preflight CORS: responder ANTES de cualquier otra lógica.
  if (req.method === 'OPTIONS') return preflight(origin);

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) return jsonCors({ error: 'NOT_AUTHENTICATED' }, 401, origin);

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY');
    const pepper = Deno.env.get('HOST_PIN_PEPPER');
    if (!SUPABASE_URL || !ANON_KEY || !pepper) return jsonCors({ error: 'SERVER_MISCONFIGURED' }, 500, origin);

    // Cliente con el JWT del usuario => auth.uid() poblado dentro del RPC.
    const supabase = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authHeader } },
    });

    // verify_jwt=false en la plataforma => la validación del JWT es OBLIGATORIA aquí.
    // Nunca se confía en un uid del cuerpo; el uid sale del token validado por Supabase Auth.
    const { data: u, error: userErr } = await supabase.auth.getUser();
    if (userErr || !u?.user?.id) return jsonCors({ error: 'NOT_AUTHENTICATED' }, 401, origin);

    const body = await req.json();
    const { name, host_name, host_token, config, request_id, pin } = body ?? {};
    if (typeof pin !== 'string' || isWeakPin(pin)) return jsonCors({ error: 'WEAK_PIN' }, 400, origin);

    const t0 = performance.now();
    const stored = await hashPin(pin, pepper);
    console.log(`pbkdf2_hash_ms=${(performance.now() - t0).toFixed(1)}`); // para el benchmark remoto

    const { data, error } = await supabase.rpc('create_game_tx', {
      p_name: name, p_host_name: host_name, p_host_token: host_token ?? null,
      p_config: config ?? {}, p_request_id: request_id,
      p_pin_hash: stored.hash, p_pin_salt: stored.salt, p_algo: stored.algo, p_iterations: stored.iterations,
    });
    if (error) return jsonCors({ error: error.message }, 400, origin);
    return jsonCors(data, 200, origin);
  } catch (e) {
    return jsonCors({ error: e instanceof Error ? e.message : String(e) }, 500, origin);
  }
});
