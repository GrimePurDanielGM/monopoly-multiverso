// Genera dos efectos de sonido locales para la cárcel (Fase 5 corrección):
//   public/sounds/police-siren.wav   — sirena bitono corta (~1.5 s)
//   public/sounds/jail-door-open.wav — puerta/barrotes metálicos (~1.0 s)
// PCM 16-bit mono 44.1 kHz, volumen moderado, sin dependencias. Determinista (PRNG sembrado).
// Uso: node apps/web/scripts/gen-jail-sounds.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const SR = 44100;
const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'public', 'sounds');

// PRNG determinista (LCG) para el ruido, para que el WAV sea reproducible byte a byte.
let seed = 0x12345678;
const rand = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 0x100000000 * 2 - 1; };

function toWav(samples) {
  const n = samples.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    const s = Math.max(-1, Math.min(1, samples[i]));
    buf.writeInt16LE(Math.round(s * 32767), 44 + i * 2);
  }
  return buf;
}

// ── Sirena de policía: dos tonos alternos (hi/lo) con leve vibrato y bordes suaves. ──
function siren() {
  const dur = 1.5, n = Math.floor(SR * dur), out = new Float32Array(n);
  const lo = 620, hi = 900, swap = 0.22; // alterna cada 0.22 s
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const f = (Math.floor(t / swap) % 2 === 0 ? lo : hi) * (1 + 0.01 * Math.sin(2 * Math.PI * 6 * t));
    phase += (2 * Math.PI * f) / SR;
    // mezcla seno + un poco de su tercer armónico para darle "filo" sin estridencia.
    let s = 0.8 * Math.sin(phase) + 0.2 * Math.sin(3 * phase);
    // envolvente global (fade in/out) + microenvolvente en cada cambio de tono.
    const env = Math.min(1, t / 0.05) * Math.min(1, (dur - t) / 0.12);
    const seg = (t % swap) / swap;
    const segEnv = Math.min(1, seg / 0.04) * Math.min(1, (1 - seg) / 0.04);
    out[i] = s * env * (0.55 + 0.45 * segEnv) * 0.34;
  }
  return out;
}

// ── Liberación celebratoria: arpegio mayor ascendente tipo campanita + un clic breve de "reja abierta"
//    discreto al inicio. Sensación de logro/salida, no de puerta. ~1 s, volumen moderado. ──
function jailRelease() {
  const dur = 1.0, n = Math.floor(SR * dur), out = new Float32Array(n);
  // Do mayor ascendente C5–E5–G5–C6 (alegre), cada nota con timbre de campana (fundamental + 2 parciales).
  const notes = [523.25, 659.25, 783.99, 1046.5];
  const noteDur = 0.16;       // separación entre notas
  for (let k = 0; k < notes.length; k++) {
    const f = notes[k];
    const start = Math.floor(k * noteDur * SR);
    const len = Math.floor((dur - k * noteDur) * SR); // resuena hasta el final
    for (let i = 0; i < len && start + i < n; i++) {
      const t = i / SR;
      const env = Math.exp(-4.5 * t);                 // decaimiento de campana
      const s = (Math.sin(2 * Math.PI * f * t)
               + 0.5 * Math.sin(2 * Math.PI * 2 * f * t)
               + 0.25 * Math.sin(2 * Math.PI * 3 * f * t)) / 1.75;
      out[start + i] += s * env * 0.3;
    }
  }
  // Clic breve inicial (reja que se abre), MUY discreto: pequeño transitorio de ruido filtrado.
  let prev = 0;
  for (let i = 0; i < SR * 0.06 && i < n; i++) {
    const t = i / SR;
    const env = Math.exp(-40 * t);
    prev = prev + 0.3 * (rand() - prev);
    out[i] += prev * env * 0.18;
  }
  // Fade out final suave.
  for (let i = 0; i < n; i++) { const t = i / SR; out[i] *= Math.min(1, (dur - t) / 0.05); }
  return out;
}

mkdirSync(OUT, { recursive: true });
writeFileSync(join(OUT, 'police-siren.wav'), toWav(siren()));
seed = 0x12345678; // reinicia el PRNG para que la liberación sea determinista
writeFileSync(join(OUT, 'jail-release.wav'), toWav(jailRelease()));
console.log('Generados: police-siren.wav, jail-release.wav en', OUT);
