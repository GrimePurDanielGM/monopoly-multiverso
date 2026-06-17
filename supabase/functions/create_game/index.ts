import { createClient } from 'npm:@supabase/supabase-js@2';
import { hashPin, isWeakPin } from '../_shared/pbkdf2.ts';

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) return json({ error: 'NOT_AUTHENTICATED' }, 401);
    const pepper = Deno.env.get('HOST_PIN_PEPPER');
    if (!pepper) return json({ error: 'SERVER_MISCONFIGURED' }, 500);

    const body = await req.json();
    const { name, host_name, host_token, config, request_id, pin } = body ?? {};
    if (typeof pin !== 'string' || isWeakPin(pin)) return json({ error: 'WEAK_PIN' }, 400);

    const t0 = performance.now();
    const stored = await hashPin(pin, pepper);
    console.log(`pbkdf2_hash_ms=${(performance.now() - t0).toFixed(1)}`); // para el benchmark remoto

    // Cliente con el JWT del usuario => auth.uid() poblado dentro del RPC.
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data, error } = await supabase.rpc('create_game_tx', {
      p_name: name, p_host_name: host_name, p_host_token: host_token ?? null,
      p_config: config ?? {}, p_request_id: request_id,
      p_pin_hash: stored.hash, p_pin_salt: stored.salt, p_algo: stored.algo, p_iterations: stored.iterations,
    });
    if (error) return json({ error: error.message }, 400);
    return json(data, 200);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}
