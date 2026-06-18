import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
  primeCashSound, playCashSound, isCashSoundEnabled, setCashSoundEnabled, __resetCashSoundForTests,
} from './cashSound';

// Fake HTMLAudioElement que registra muted/currentTime/play/pause y permite simular el rechazo
// de play() (autoplay bloqueado por iOS/Safari).
class FakeAudio {
  static instances: FakeAudio[] = [];
  static playImpl: () => Promise<void> = () => Promise.resolve();
  src: string;
  muted = false;
  currentTime = 0;
  preload = '';
  paused = true;
  play = vi.fn(() => { this.paused = false; return FakeAudio.playImpl(); });
  pause = vi.fn(() => { this.paused = true; });
  load = vi.fn();
  setAttribute = vi.fn();
  constructor(src?: string) { this.src = src ?? ''; FakeAudio.instances.push(this); }
}

beforeEach(() => {
  __resetCashSoundForTests();
  FakeAudio.instances = [];
  FakeAudio.playImpl = () => Promise.resolve();
  vi.stubGlobal('Audio', FakeAudio as unknown as typeof Audio);
  try { window.localStorage.clear(); } catch { /* */ }
});
afterEach(() => { vi.unstubAllGlobals(); });

describe('cashSound — desbloqueo y reproducción (HTMLAudioElement)', () => {
  it('1) se desbloquea en una interacción real: crea el elemento y lo reproduce en silencio', async () => {
    primeCashSound();
    expect(FakeAudio.instances).toHaveLength(1);
    const a = FakeAudio.instances[0]!;
    expect(a.play).toHaveBeenCalledTimes(1);
    await Promise.resolve(); // resolver la promesa de play()
    expect(a.muted).toBe(false); // muted restaurado tras desbloquear
    // Un segundo prime no vuelve a reproducir (ya desbloqueado).
    primeCashSound();
    expect(a.play).toHaveBeenCalledTimes(1);
  });

  it('2) reproduce el sonido tras el desbloqueo (audible, no muted, desde el inicio)', () => {
    primeCashSound();
    const a = FakeAudio.instances[0]!;
    a.play.mockClear();
    playCashSound();
    expect(a.play).toHaveBeenCalledTimes(1);
    expect(a.muted).toBe(false);
    expect(a.currentTime).toBe(0);
  });

  it('3 y 7) falla en silencio si play() es rechazado por el navegador (iOS/Safari)', async () => {
    FakeAudio.playImpl = () => Promise.reject(new Error('NotAllowedError'));
    expect(() => primeCashSound()).not.toThrow();
    expect(() => playCashSound()).not.toThrow();
    await Promise.resolve();
    await Promise.resolve();
    // No hubo desbloqueo: un nuevo gesto reintenta (play vuelve a llamarse).
    FakeAudio.playImpl = () => Promise.resolve();
    primeCashSound();
    expect(FakeAudio.instances[0]!.play.mock.calls.length).toBeGreaterThanOrEqual(2);
  });

  it('6) no rompe si no existe HTMLAudioElement (Audio undefined)', () => {
    vi.stubGlobal('Audio', undefined);
    __resetCashSoundForTests();
    expect(() => primeCashSound()).not.toThrow();
    expect(() => playCashSound()).not.toThrow();
  });
});

describe('cashSound — preferencia local', () => {
  it('por defecto activado; se puede desactivar y reactivar (localStorage)', () => {
    expect(isCashSoundEnabled()).toBe(true);
    setCashSoundEnabled(false);
    expect(isCashSoundEnabled()).toBe(false);
    setCashSoundEnabled(true);
    expect(isCashSoundEnabled()).toBe(true);
  });
});
