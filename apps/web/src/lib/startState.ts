// Precondición VISUAL de inicio derivada del snapshot. La autoridad final es start_game.
import type { GameStatus, SnapCounts, SnapPlayer, SnapRequest } from './snapshot';

export interface StartState {
  canStart: boolean;
  playerCount: number;
  minPlayers: number;
  readyCount: number;
  withoutToken: number;
  pendingRequests: number;
  enoughPlayers: boolean;
  allReady: boolean;
}

export function computeStartState(a: {
  isHost: boolean;
  status: GameStatus;
  players: readonly SnapPlayer[];
  counts: SnapCounts;
  requests: readonly SnapRequest[];
}): StartState {
  const withoutToken = a.players.filter((p) => p.token_id === null).length;
  const enoughPlayers = a.counts.player_count >= a.counts.min_players;
  const allReady = a.counts.player_count > 0 && a.counts.ready_count === a.counts.player_count;
  const pendingRequests = a.requests.length;
  const canStart =
    a.isHost && a.status === 'lobby' && enoughPlayers && allReady && withoutToken === 0 && pendingRequests === 0;
  return {
    canStart,
    playerCount: a.counts.player_count,
    minPlayers: a.counts.min_players,
    readyCount: a.counts.ready_count,
    withoutToken,
    pendingRequests,
    enoughPlayers,
    allReady,
  };
}
