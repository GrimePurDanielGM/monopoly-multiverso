// Efecto de sonido "caja registradora" al recibir dinero.
//
// Implementación con HTMLAudioElement + asset WAV local (apps/web/public/sounds/cash-register.wav,
// sintetizado y libre de derechos). Esta vía es la más fiable en iOS Safari/PWA: el elemento <audio>
// reproduce media (no Web Audio), por lo que no depende del estado del AudioContext y, una vez
// "desbloqueado" dentro de un gesto real del usuario, vuelve a sonar de forma programática.
//
// Diagnóstico previo (por qué fallaba en iPhone con Web Audio):
//  - iOS solo permite crear/resumir el AudioContext DENTRO de un gesto; el contexto se creaba al
//    reproducir (en un update de snapshot, fuera de gesto) y quedaba `suspended` → silencio.
//  - El timbre triangular agudo era poco audible en el altavoz del iPhone.
//  - Web Audio respeta el interruptor de silencio del hardware; <audio> es más permisivo.
//
// Reglas: preferencia local por dispositivo en localStorage; falla SIEMPRE en silencio (nunca lanza
// ni muestra error técnico). El modo silencioso físico del iPhone puede silenciarlo: no se intenta
// sortear, solo se documenta.

const PREF_KEY = 'cash_sound_enabled';
const ASSET_URL = `${import.meta.env.BASE_URL ?? '/'}sounds/cash-register.wav`;

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

let audio: HTMLAudioElement | null = null;
let unlocked = false;

function getAudio(): HTMLAudioElement | null {
  if (typeof window === 'undefined' || typeof Audio === 'undefined') return null;
  if (!audio) {
    try {
      audio = new Audio(ASSET_URL);
      audio.preload = 'auto';
      // iOS necesita reproducción inline (no a pantalla completa) y un único canal de SFX.
      audio.setAttribute('playsinline', '');
      audio.load();
    } catch {
      audio = null;
    }
  }
  return audio;
}

/**
 * Desbloquea el audio en la PRIMERA interacción real del usuario (pointerdown/touchend/click).
 * Debe llamarse SÍNCRONAMENTE dentro del manejador del gesto: reproduce el asset en silencio
 * (muted) y lo pausa de inmediato, dejando el elemento listo para sonar luego sin gesto.
 * Marca `unlocked = true` solo si la promesa de play no es rechazada. Falla en silencio.
 */
export function primeCashSound(): void {
  if (unlocked) return;
  const a = getAudio();
  if (!a) return;
  try {
    const prevMuted = a.muted;
    a.muted = true;
    const p = a.play();
    if (p && typeof p.then === 'function') {
      p.then(() => {
        try {
          a.pause();
          a.currentTime = 0;
        } catch {
          /* noop */
        }
        a.muted = prevMuted;
        unlocked = true;
      }).catch(() => {
        a.muted = prevMuted;
        /* el navegador rechazó el desbloqueo: no marcamos unlocked, sin error */
      });
    } else {
      // Navegadores sin promesa en play(): asumimos desbloqueo optimista.
      try {
        a.pause();
        a.currentTime = 0;
      } catch {
        /* noop */
      }
      a.muted = prevMuted;
      unlocked = true;
    }
  } catch {
    /* sin audio disponible: silencio */
  }
}

/** Reproduce el sonido de caja registradora. Falla en silencio si el navegador lo bloquea. */
export function playCashSound(): void {
  const a = getAudio();
  if (!a) return;
  try {
    a.muted = false;
    a.currentTime = 0;
    const p = a.play();
    if (p && typeof p.then === 'function') p.catch(() => {});
  } catch {
    /* autoplay bloqueado u otro problema: silencio, sin romper la UI */
  }
}

/** Solo para tests: restablece el estado interno del módulo. */
export function __resetCashSoundForTests(): void {
  audio = null;
  unlocked = false;
}
