import { describe, it, expect, beforeEach } from 'vitest';
import { useLobbyStore } from './lobby';
import { hasForbiddenKey, type LobbySnapshot, type SnapPlayer } from '../lib/snapshot';

function player(ref: string, token: string | null = null): SnapPlayer {
  return { public_ref: ref, name: ref, token_id: token, status: 'joined', last_seen_at: '2026-06-17T00:00:00Z' };
}
function snap(code: string, refs: string[]): LobbySnapshot {
  const players = refs.map((r) => player(r));
  return {
    game: {
      id: `id-${code}`, code, name: `Sala ${code}`, status: 'lobby', version: 0,
      started_at: null, cancelled_at: null, host_public_ref: refs[0] ?? null,
      config: { min_players: 6, max_players: 16, initial_money: 3000, token_catalog_version: 0, dice_mode: 'virtual_only', initial_houses_available: 32, initial_hotels_available: 12, allow_build_without_monopoly: false },
    },
    players,
    me: { public_ref: refs[0] ?? 'P-1', is_host: true, join_status: 'joined', token_id: null, membership: 'active' },
    requests: [],
    counts: { player_count: players.length, ready_count: 0, min_players: 6, max_players: 16 },
  };
}

beforeEach(() => useLobbyStore.getState().reset());

describe('useLobbyStore', () => {
  it('replaceSnapshot guarda el snapshot y marca ready', () => {
    useLobbyStore.getState().replaceSnapshot(snap('AAA111', ['P-1', 'P-2']), 1234);
    const s = useLobbyStore.getState();
    expect(s.snapshotStatus).toBe('ready');
    expect(s.lastLoadedAt).toBe(1234);
    expect(s.error).toBeNull();
    expect(s.game?.code).toBe('AAA111');
    expect(s.players).toHaveLength(2);
    expect(s.me?.public_ref).toBe('P-1');
  });

  it('el snapshot SUSTITUYE por completo el estado anterior (sin restos)', () => {
    useLobbyStore.getState().replaceSnapshot(snap('AAA111', ['P-1', 'P-2', 'P-3']), 1);
    useLobbyStore.getState().replaceSnapshot(snap('BBB222', ['P-9']), 2);
    const s = useLobbyStore.getState();
    expect(s.game?.code).toBe('BBB222');
    expect(s.players).toHaveLength(1);
    expect(s.players[0]?.public_ref).toBe('P-9');
    expect(s.lastLoadedAt).toBe(2);
  });

  it('reset deja el estado vacío e idle', () => {
    useLobbyStore.getState().replaceSnapshot(snap('AAA111', ['P-1']), 1);
    useLobbyStore.getState().reset();
    const s = useLobbyStore.getState();
    expect(s.snapshotStatus).toBe('idle');
    expect(s.game).toBeNull();
    expect(s.players).toHaveLength(0);
  });

  it('el store nunca contiene la clave interna prohibida', () => {
    useLobbyStore.getState().replaceSnapshot(snap('AAA111', ['P-1', 'P-2']), 1);
    const s = useLobbyStore.getState();
    expect(hasForbiddenKey({ game: s.game, players: s.players, me: s.me, requests: s.requests, counts: s.counts })).toBe(false);
  });
});
