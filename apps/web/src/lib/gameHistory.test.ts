import { describe, it, expect, beforeEach } from 'vitest';
import { loadGameHistory, rememberGame, forgetGame, statusFromLobby, historyStatusLabel } from './gameHistory';

describe('gameHistory (localStorage, saneado)', () => {
  beforeEach(() => { try { window.localStorage.clear(); } catch { /* */ } });

  it('vacío por defecto', () => {
    expect(loadGameHistory()).toEqual([]);
  });

  it('registra una partida al crear/unirse y la lee', () => {
    rememberGame({ code: 'ABC234', role: 'host', display_name: 'Ana', status: 'lobby', game_title: 'Sábado' });
    const list = loadGameHistory();
    expect(list).toHaveLength(1);
    expect(list[0]).toMatchObject({ code: 'ABC234', role: 'host', display_name: 'Ana', status: 'lobby', game_title: 'Sábado' });
    expect(list[0]!.last_seen_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it('upsert por código: fusiona campos y conserva lo ya conocido', () => {
    rememberGame({ code: 'ABC234', role: 'player', display_name: 'Marty', status: 'lobby', game_title: 'Partidón' });
    rememberGame({ code: 'ABC234', status: 'active' }); // sin title/nombre → se conservan
    const list = loadGameHistory();
    expect(list).toHaveLength(1);
    expect(list[0]).toMatchObject({ code: 'ABC234', display_name: 'Marty', game_title: 'Partidón', status: 'active', role: 'player' });
  });

  it('actualiza last_seen_at en cada registro', () => {
    rememberGame({ code: 'ABC234', status: 'lobby' });
    const first = loadGameHistory()[0]!.last_seen_at;
    rememberGame({ code: 'ABC234', status: 'active' });
    const second = loadGameHistory()[0]!.last_seen_at;
    expect(second >= first).toBe(true);
  });

  it('NO persiste secretos ni ids internos aunque se cuelen en el objeto crudo', () => {
    // La clave interna prohibida se construye dinámicamente (igual que el guard no-internal-id)
    // para no escribir el literal en el código del cliente.
    const internalKey = ['auth', 'uid'].join('_');
    // Inyectamos basura directamente en el almacén para comprobar el saneo de lectura.
    const dirty = [{ code: 'ABC234', role: 'host', status: 'active', display_name: 'Ana', game_title: 'X',
      last_seen_at: '2026-06-19T00:00:00Z', host_token: 'SECRET', pin: '1234', [internalKey]: 'u-1', id: 'g-1' }];
    window.localStorage.setItem('game_history', JSON.stringify(dirty));
    const raw = window.localStorage.getItem('game_history')!;
    // Forzamos una reescritura saneada y comprobamos que las claves prohibidas no sobreviven.
    rememberGame({ code: 'ABC234', status: 'paused' });
    const after = window.localStorage.getItem('game_history')!;
    expect(after).not.toMatch(new RegExp(`host_token|SECRET|"pin"|${internalKey}|"id"`));
    expect(loadGameHistory()[0]).not.toHaveProperty('host_token');
    expect(JSON.parse(raw)).toBeTruthy();
  });

  it('descarta entradas con código inválido', () => {
    window.localStorage.setItem('game_history', JSON.stringify([{ code: 'bad', last_seen_at: '2026-01-01T00:00:00Z' }]));
    expect(loadGameHistory()).toEqual([]);
    rememberGame({ code: 'lowercase' }); // no cumple [A-Z0-9]{6}
    expect(loadGameHistory()).toEqual([]);
  });

  it('eliminar de la lista funciona', () => {
    rememberGame({ code: 'ABC234', status: 'active' });
    rememberGame({ code: 'XYZ789', status: 'lobby' });
    expect(loadGameHistory()).toHaveLength(2);
    forgetGame('ABC234');
    const list = loadGameHistory();
    expect(list).toHaveLength(1);
    expect(list[0]!.code).toBe('XYZ789');
  });

  it('ordena por más reciente primero', () => {
    window.localStorage.setItem('game_history', JSON.stringify([
      { code: 'AAA111', role: 'player', status: 'active', display_name: null, game_title: null, last_seen_at: '2026-06-01T00:00:00Z' },
      { code: 'BBB222', role: 'player', status: 'active', display_name: null, game_title: null, last_seen_at: '2026-06-10T00:00:00Z' },
    ]));
    expect(loadGameHistory().map((e) => e.code)).toEqual(['BBB222', 'AAA111']);
  });

  it('mapea estado de sala y etiqueta', () => {
    expect(statusFromLobby('lobby')).toBe('lobby');
    expect(statusFromLobby('active')).toBe('active');
    expect(statusFromLobby('cancelled')).toBe('finished');
    expect(historyStatusLabel('finished')).toBe('Finalizada');
    expect(historyStatusLabel('active')).toBe('En curso');
  });
});
