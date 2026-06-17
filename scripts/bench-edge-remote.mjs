// Mide la latencia real del hash en el Edge desplegado, leyendo los logs de la función.
// Uso: SUPABASE_URL=... ANON_KEY=... JWT=<jwt anon> node scripts/bench-edge-remote.mjs 20
// (Crea N partidas desechables en un proyecto de staging y luego inspecciona los logs:
//   supabase functions logs create_game | grep pbkdf2_hash_ms)
const N = Number(process.argv[2] ?? 20);
const url = process.env.SUPABASE_URL, anon = process.env.ANON_KEY, jwt = process.env.JWT;
if (!url || !anon || !jwt) { console.error('Faltan SUPABASE_URL / ANON_KEY / JWT'); process.exit(1); }
const lat = [];
for (let i = 0; i < N; i++) {
  const t = performance.now();
  const r = await fetch(`${url}/functions/v1/create_game`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', apikey: anon, Authorization: `Bearer ${jwt}` },
    body: JSON.stringify({ name: `Bench ${i} ${Date.now()}`, host_name: 'Bench', host_token: null,
      config: {}, request_id: crypto.randomUUID(), pin: '482915' }),
  });
  await r.json(); lat.push(performance.now() - t);
}
lat.sort((a, b) => a - b);
const pct = (p) => lat[Math.min(lat.length - 1, Math.floor(p / 100 * lat.length))];
console.log('Round-trip ms (incluye red):', { p50: +pct(50).toFixed(0), p95: +pct(95).toFixed(0) });
console.log('Para el hash puro: supabase functions logs create_game | grep pbkdf2_hash_ms');
