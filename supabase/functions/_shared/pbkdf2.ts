// PBKDF2-HMAC-SHA256 con PEPPER (secreto de Edge). El PIN/pepper nunca se almacenan.
const ITERATIONS = 600_000;
const KEYLEN_BITS = 256;
const enc = new TextEncoder();

// Copia los bytes en un ArrayBuffer propio: BufferSource inequívocamente válido
// para Web Crypto bajo el tipado estricto de TS 6 / Deno 2.8 (Uint8Array es genérico
// sobre ArrayBufferLike y no encaja directamente en BufferSource).
function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function b64(bytes: Uint8Array): string { return btoa(String.fromCharCode(...bytes)); }
function unb64(s: string): Uint8Array { return Uint8Array.from(atob(s), (c) => c.charCodeAt(0)); }

async function pepperedPassword(pin: string, pepper: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw', toArrayBuffer(enc.encode(pepper)), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, toArrayBuffer(enc.encode(pin))));
}
async function derive(password: Uint8Array, salt: Uint8Array, iterations: number): Promise<Uint8Array> {
  const base = await crypto.subtle.importKey('raw', toArrayBuffer(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: toArrayBuffer(salt), iterations, hash: 'SHA-256' }, base, KEYLEN_BITS,
  );
  return new Uint8Array(bits);
}
function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

export interface StoredHash { hash: string; salt: string; algo: string; iterations: number; }

export function isWeakPin(pin: string): boolean {
  if (!/^\d{6}$/.test(pin)) return true;
  if (/^(\d)\1{5}$/.test(pin)) return true;
  if (pin === '123456') return true;
  return false;
}

export async function hashPin(pin: string, pepper: string): Promise<StoredHash> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const pw = await pepperedPassword(pin, pepper);
  const hash = await derive(pw, salt, ITERATIONS);
  return { hash: b64(hash), salt: b64(salt), algo: 'PBKDF2-HMAC-SHA256', iterations: ITERATIONS };
}

export async function verifyPin(pin: string, pepper: string, stored: StoredHash): Promise<boolean> {
  const pw = await pepperedPassword(pin, pepper);
  const candidate = await derive(pw, unb64(stored.salt), stored.iterations);
  return constantTimeEqual(candidate, unb64(stored.hash));
}
