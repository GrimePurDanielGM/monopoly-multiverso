import { describe, it, expect } from 'vitest';
import { reduceConn, playerPresenceStatus } from './connState';

describe('reduceConn', () => {
  it('subscribed -> connected', () => expect(reduceConn('connecting', 'subscribed', true)).toBe('connected'));
  it('lost desde connected -> reconnecting (no desconectado de inmediato)', () =>
    expect(reduceConn('connected', 'lost', true)).toBe('reconnecting'));
  it('timeout desde reconnecting -> disconnected (a los 12 s)', () =>
    expect(reduceConn('reconnecting', 'timeout', true)).toBe('disconnected'));
  it('subscribed cancela el reconnecting -> connected', () =>
    expect(reduceConn('reconnecting', 'subscribed', true)).toBe('connected'));
  it('timeout no afecta si ya está connected', () => expect(reduceConn('connected', 'timeout', true)).toBe('connected'));
  it('sin red tiene prioridad -> offline', () => expect(reduceConn('connected', 'lost', false)).toBe('offline'));
  it('online desde offline -> connecting', () => expect(reduceConn('offline', 'online', true)).toBe('connecting'));
});

describe('playerPresenceStatus', () => {
  it('reconnecting global -> reconnecting', () => expect(playerPresenceStatus('reconnecting', true)).toBe('reconnecting'));
  it('connected + presente -> connected', () => expect(playerPresenceStatus('connected', true)).toBe('connected'));
  it('connected + ausente -> disconnected', () => expect(playerPresenceStatus('connected', false)).toBe('disconnected'));
  it('offline -> disconnected', () => expect(playerPresenceStatus('offline', true)).toBe('disconnected'));
});
