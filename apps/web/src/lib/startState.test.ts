import { describe, it, expect } from 'vitest';
import { computeStartState } from './startState';
import type { SnapCounts, SnapPlayer, SnapRequest } from './snapshot';

function player(ref: string, token: string | null, status: 'joined' | 'ready' = 'ready'): SnapPlayer {
  return { public_ref: ref, name: ref, token_id: token, status, last_seen_at: 'x' };
}
function counts(pc: number, rc: number, min = 6, max = 16): SnapCounts {
  return { player_count: pc, ready_count: rc, min_players: min, max_players: max };
}
const six = Array.from({ length: 6 }, (_, i) => player(`P-${i}`, 't'));

describe('computeStartState', () => {
  it('canStart con 6, todos con ficha y preparados, sin solicitudes (host)', () => {
    expect(computeStartState({ isHost: true, status: 'lobby', players: six, counts: counts(6, 6), requests: [] }).canStart).toBe(true);
  });
  it('no inicia con menos de 6', () => {
    const five = six.slice(0, 5);
    expect(computeStartState({ isHost: true, status: 'lobby', players: five, counts: counts(5, 5), requests: [] }).canStart).toBe(false);
  });
  it('no inicia si no todos están preparados', () => {
    expect(computeStartState({ isHost: true, status: 'lobby', players: six, counts: counts(6, 5), requests: [] }).canStart).toBe(false);
  });
  it('cuenta jugadores sin ficha y bloquea inicio', () => {
    const players = [...six.slice(0, 5), player('P-x', null)];
    const s = computeStartState({ isHost: true, status: 'lobby', players, counts: counts(6, 6), requests: [] });
    expect(s.withoutToken).toBe(1);
    expect(s.canStart).toBe(false);
  });
  it('no inicia con solicitudes pendientes', () => {
    const req: SnapRequest = { request_ref: 'r', kind: 'recovery', status: 'pending', target_public_ref: 'P-0', device_label: null };
    expect(computeStartState({ isHost: true, status: 'lobby', players: six, counts: counts(6, 6), requests: [req] }).canStart).toBe(false);
  });
  it('no inicia si no soy host', () => {
    expect(computeStartState({ isHost: false, status: 'lobby', players: six, counts: counts(6, 6), requests: [] }).canStart).toBe(false);
  });
});
