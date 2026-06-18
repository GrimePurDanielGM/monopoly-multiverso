// Efecto de sonido "caja registradora" (ticling) sintetizado con Web Audio (sin asset binario,
// libre de derechos). Preferencia local por dispositivo en localStorage. Falla en silencio si el
// navegador bloquea el autoplay o no hay Web Audio.
const PREF_KEY = 'cash_sound_enabled';

/** ¿Está activado el sonido al recibir dinero? (por defecto: sí). */
export function isCashSoundEnabled(): boolean {
  try {
    return window.localStorage.getItem(PREF_KEY) !== 'off';
  } catch {
    return true;
  }
}

/** Activa/desactiva el sonido localmente (no se sincroniza con el backend). */
export function setCashSoundEnabled(on: boolean): void {
  try {
    window.localStorage.setItem(PREF_KEY, on ? 'on' : 'off');
  } catch {
    /* sin localStorage: no persiste, sin error */
  }
}

type AC = typeof AudioContext;
let ctx: AudioContext | null = null;
function getCtx(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  try {
    const Ctor: AC | undefined = window.AudioContext ?? (window as unknown as { webkitAudioContext?: AC }).webkitAudioContext;
    if (!Ctor) return null;
    if (!ctx) ctx = new Ctor();
    return ctx;
  } catch {
    return null;
  }
}

/** Desbloquea el audio tras la primera interacción del usuario (muchos navegadores lo exigen). */
export function primeCashSound(): void {
  const c = getCtx();
  if (c && c.state === 'suspended') c.resume().catch(() => {});
}

/** Reproduce un "ticling" corto (dos campanitas) de caja registradora. Falla en silencio. */
export function playCashSound(): void {
  try {
    const c = getCtx();
    if (!c) return;
    if (c.state === 'suspended') c.resume().catch(() => {});
    const now = c.currentTime;
    for (const [t, freq] of [[0, 1318.5], [0.075, 1760]] as const) {
      const osc = c.createOscillator();
      const gain = c.createGain();
      osc.type = 'triangle';
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.0001, now + t);
      gain.gain.exponentialRampToValueAtTime(0.16, now + t + 0.008);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + t + 0.16);
      osc.connect(gain);
      gain.connect(c.destination);
      osc.start(now + t);
      osc.stop(now + t + 0.18);
    }
  } catch {
    /* autoplay bloqueado u otro problema: silencio, sin romper la UI */
  }
}
