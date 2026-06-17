import { describe, it, expect } from 'vitest';
import { takenTokenIds, isMe, canSetReady } from './lobbySelectors';
import type { SnapMe, SnapPlayer } from './snapshot';

function player(ref: string, token: string | null): SnapPlayer {
  return { public_ref: ref, name: ref, token_id: token, status: 'joined', last_seen_at: '2026-06-17T00:00:00Z' };
}
function me(ref: string, token: string | null): SnapMe {
  return { public_ref: ref, is_host: false, join_status: 'joined', token_id: token, membership: 'active' };
}

describe('lobbySelectors', () => {
  it('takenTokenIds reúne solo los token_id no nulos', () => {
    const set = takenTokenIds([player('P-1', 'a'), player('P-2', null), player('P-3', 'b')]);
    expect([...set].sort()).toEqual(['a', 'b']);
  });
  it('isMe compara por public_ref', () => {
    expect(isMe(player('P-1', null), me('P-1', null))).toBe(true);
    expect(isMe(player('P-2', null), me('P-1', null))).toBe(false);
  });
  it('canSetReady: true para preparado solo con ficha; quitar siempre permitido', () => {
    expect(canSetReady(me('P-1', 'a'), true)).toBe(true);
    expect(canSetReady(me('P-1', null), true)).toBe(false);
    expect(canSetReady(me('P-1', null), false)).toBe(true);
  });
});
