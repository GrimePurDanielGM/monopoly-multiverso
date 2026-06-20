// Efectos de sonido de la cárcel (Fase 5 corrección): sirena al entrar, puerta/barrotes al salir.
// Mismo patrón robusto que cashSound (HTMLAudioElement + asset WAV local, desbloqueo dentro de un gesto,
// falla SIEMPRE en silencio). Comparte la preferencia de sonido con cashSound (un único interruptor).
import { isCashSoundEnabled } from './cashSound';

export type SfxName = 'siren' | 'door';

const BASE = import.meta.env.BASE_URL ?? '/';
const ASSETS: Record<SfxName, string> = {
  siren: `${BASE}sounds/police-siren.wav`,
  door: `${BASE}sounds/jail-door-open.wav`,
};

const els: Partial<Record<SfxName, HTMLAudioElement>> = {};
let unlocked = false;

function get(name: SfxName): HTMLAudioElement | null {
  if (typeof window === 'undefined' || typeof Audio === 'undefined') return null;
  let a = els[name];
  if (!a) {
    try {
      a = new Audio(ASSETS[name]);
      a.preload = 'auto';
      a.setAttribute('playsinline', '');
      a.load();
      els[name] = a;
    } catch {
      return null;
    }
  }
  return a;
}

/** Desbloquea TODOS los SFX en el primer gesto real (igual que primeCashSound): play muted + pause. */
export function primeSfx(): void {
  if (unlocked) return;
  let any = false;
  (Object.keys(ASSETS) as SfxName[]).forEach((name) => {
    const a = get(name);
    if (!a) return;
    any = true;
    try {
      const prev = a.muted;
      a.muted = true;
      const p = a.play();
      if (p && typeof p.then === 'function') {
        p.then(() => { try { a.pause(); a.currentTime = 0; } catch { /* */ } a.muted = prev; }).catch(() => { a.muted = prev; });
      } else {
        try { a.pause(); a.currentTime = 0; } catch { /* */ }
        a.muted = prev;
      }
    } catch {
      /* sin audio: silencio */
    }
  });
  if (any) unlocked = true;
}

/** Reproduce un SFX por nombre. Respeta la preferencia de sonido. Falla en silencio. */
export function playSfx(name: SfxName): void {
  if (!isCashSoundEnabled()) return;
  const a = get(name);
  if (!a) return;
  try {
    a.muted = false;
    a.currentTime = 0;
    const p = a.play();
    if (p && typeof p.then === 'function') p.catch(() => {});
  } catch {
    /* autoplay bloqueado: silencio */
  }
}

/** Solo para tests: restablece el estado interno. */
export function __resetSfxForTests(): void {
  (Object.keys(els) as SfxName[]).forEach((k) => delete els[k]);
  unlocked = false;
}
