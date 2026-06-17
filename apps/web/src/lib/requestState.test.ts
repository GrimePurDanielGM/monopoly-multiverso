import { describe, it, expect } from 'vitest';
import { isTerminal, requestResultMessage, remainingLockMs, formatCountdown } from './requestState';

describe('requestState', () => {
  it('isTerminal: solo pending no es terminal', () => {
    expect(isTerminal('pending')).toBe(false);
    for (const s of ['approved', 'rejected', 'cancelled', 'expired'] as const) expect(isTerminal(s)).toBe(true);
  });
  it('clasifica el mensaje de cada estado terminal', () => {
    expect(requestResultMessage('approved')).toMatch(/aprobada/i);
    expect(requestResultMessage('rejected')).toMatch(/rechaz/i);
    expect(requestResultMessage('cancelled')).toMatch(/cancel/i);
    expect(requestResultMessage('expired')).toMatch(/caduc/i);
  });
  it('remainingLockMs', () => {
    const now = 1_000_000;
    expect(remainingLockMs(null, now)).toBe(0);
    expect(remainingLockMs(new Date(now + 5000).toISOString(), now)).toBe(5000);
    expect(remainingLockMs(new Date(now - 5000).toISOString(), now)).toBe(0);
    expect(remainingLockMs('basura', now)).toBe(0);
  });
  it('formatCountdown mm:ss', () => {
    expect(formatCountdown(0)).toBe('00:00');
    expect(formatCountdown(65000)).toBe('01:05');
    expect(formatCountdown(900000)).toBe('15:00');
  });
});
