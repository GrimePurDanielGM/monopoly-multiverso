// Ejecutar localmente: deno run --allow-hrtime supabase/functions/_shared/pbkdf2_bench.ts
import { hashPin } from './pbkdf2.ts';
const N = 30, pepper = 'bench-pepper';
await hashPin('482915', pepper); // warmup
const xs: number[] = [];
for (let i = 0; i < N; i++) { const t = performance.now(); await hashPin('482915', pepper); xs.push(performance.now() - t); }
xs.sort((a, b) => a - b);
const pct = (p: number) => xs[Math.min(xs.length - 1, Math.floor((p / 100) * xs.length))];
console.log(JSON.stringify({ runtime: 'deno-webcrypto', iterations: 600000, n: N,
  p50: +pct(50).toFixed(1), p95: +pct(95).toFixed(1), p99: +pct(99).toFixed(1) }, null, 2));
