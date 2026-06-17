import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createDebouncer } from './debounce';

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe('createDebouncer', () => {
  it('agrupa llamadas consecutivas en una sola ejecución', () => {
    const fn = vi.fn();
    const d = createDebouncer(fn, 200);
    d.call();
    d.call();
    d.call();
    expect(fn).not.toHaveBeenCalled();
    vi.advanceTimersByTime(200);
    expect(fn).toHaveBeenCalledTimes(1);
  });
  it('no pierde la última señal: una llamada posterior vuelve a ejecutar', () => {
    const fn = vi.fn();
    const d = createDebouncer(fn, 100);
    d.call();
    vi.advanceTimersByTime(100);
    d.call();
    vi.advanceTimersByTime(100);
    expect(fn).toHaveBeenCalledTimes(2);
  });
  it('cancel evita el disparo pendiente', () => {
    const fn = vi.fn();
    const d = createDebouncer(fn, 100);
    d.call();
    d.cancel();
    vi.advanceTimersByTime(300);
    expect(fn).not.toHaveBeenCalled();
  });
});
