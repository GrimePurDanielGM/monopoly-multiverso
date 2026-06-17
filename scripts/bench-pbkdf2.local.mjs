import crypto from 'node:crypto';
const ITER = 600_000, KEYLEN = 32, N = 50;
const pepper = 'bench-pepper', pin = '482915';
const pre = crypto.createHmac('sha256', pepper).update(pin).digest(); // pepper como en Edge
function once() {
  const salt = crypto.randomBytes(16); const t = process.hrtime.bigint();
  crypto.pbkdf2Sync(pre, salt, ITER, KEYLEN, 'sha256');
  return Number(process.hrtime.bigint() - t) / 1e6;
}
once(); // warmup
const xs = Array.from({ length: N }, once).sort((a, b) => a - b);
const pct = (p) => xs[Math.min(xs.length - 1, Math.floor(p / 100 * xs.length))];
const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
console.log(JSON.stringify({ runtime: 'node-openssl', iterations: ITER, n: N,
  p50: +pct(50).toFixed(1), p95: +pct(95).toFixed(1), p99: +pct(99).toFixed(1),
  mean: +mean.toFixed(1), min: +xs[0].toFixed(1), max: +xs[xs.length-1].toFixed(1) }, null, 2));
