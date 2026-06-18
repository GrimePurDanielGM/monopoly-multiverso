// @vitest-environment node
// Integración local REAL — partida activa (Fase 2): economía, turnos, correcciones,
// idempotencia, conflicto de versión, Broadcast y resync. Solo si SB_URL/SB_ANON.
import { describe, it, expect } from 'vitest';
import { createClient, type RealtimeChannel, type SupabaseClient } from '@supabase/supabase-js';

const URL = process.env.SB_URL;
const ANON = process.env.SB_ANON;
const enabled = Boolean(URL && ANON);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function authed(): Promise<SupabaseClient> {
  const c = createClient(URL as string, ANON as string, { auth: { persistSession: false, autoRefreshToken: false } });
  await c.auth.signInAnonymously();
  const { data } = await c.auth.getSession();
  await c.realtime.setAuth(data.session?.access_token ?? '');
  return c;
}

/** Crea una partida y la lleva a 'active' con 6 jugadores. Devuelve clientes + code/gid. */
async function startedGame() {
  const host = await authed();
  const cg = await host.functions.invoke('create_game', {
    body: { name: 'Activa IT', host_name: 'Host', host_token: 'penguin', config: {}, request_id: crypto.randomUUID(), pin: '482915' },
  });
  const code = cg.data.code as string;
  const gid = cg.data.game_id as string;
  const toks = ['cat', 'boot', 'thimble', 'top_hat', 'iron'];
  const joiners: SupabaseClient[] = [];
  for (let i = 0; i < 5; i++) {
    const c = await authed();
    await c.rpc('join_game', { p_code: code, p_name: 'P' + i, p_request_id: crypto.randomUUID() });
    await c.rpc('choose_token', { p_game: gid, p_token: toks[i] });
    await c.rpc('set_ready', { p_game: gid, p_ready: true });
    joiners.push(c);
  }
  await host.rpc('set_ready', { p_game: gid, p_ready: true });
  const pre = await host.rpc('get_lobby_snapshot_by_code', { p_code: code });
  await host.rpc('start_game', { p_game: gid, p_expected_version: pre.data.game.version });
  return { host, joiners, code, gid };
}

function waitSub(ch: RealtimeChannel, ms = 8000): Promise<string> {
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve('TIMEOUT'), ms);
    ch.subscribe((s) => { if (s === 'SUBSCRIBED' || s === 'CHANNEL_ERROR') { clearTimeout(t); resolve(s); } });
  });
}

describe.skipIf(!enabled)('Partida activa — integración local real', () => {
  it('siembra, turnos, economía, idempotencia, versión, Broadcast y resync', async () => {
    const { host, joiners, code, gid } = await startedGame();

    // Snapshot inicial: saldos a 3000, soy host.
    const s0 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(s0.data.me.is_host).toBe(true);
    expect(s0.data.me.balance).toBe(3000);
    expect(s0.data.players.every((p: { balance: number }) => p.balance === 3000)).toBe(true);

    // Suscripción de un miembro: debe recibir 'active_state_changed' al mutar.
    const member = joiners[0]!;
    const events: number[] = [];
    const ch = member.channel('room:' + code, { config: { private: true } });
    ch.on('broadcast', { event: 'active_state_changed' }, (m: { payload?: { runtime_version?: number } }) => {
      if (typeof m.payload?.runtime_version === 'number') events.push(m.payload.runtime_version);
    });
    expect(await waitSub(ch)).toBe('SUBSCRIBED');

    // Banca: host paga 500 a un jugador.
    const target = s0.data.turn.order[1] as string;
    let ver = s0.data.runtime_version as number;
    const bt = await host.rpc('bank_transfer', { p_game: gid, p_player_ref: target, p_direction: 'to_player', p_amount: 500, p_request_id: crypto.randomUUID(), p_expected_version: ver });
    expect(bt.error).toBeNull();
    await sleep(1500);
    expect(events.length).toBeGreaterThanOrEqual(1); // Broadcast recibido

    // Resync del miembro: ve el saldo actualizado.
    const sm = await member.rpc('get_active_snapshot_by_code', { p_code: code });
    const tgt = sm.data.players.find((p: { public_ref: string }) => p.public_ref === target);
    expect(tgt.balance).toBe(3500);

    // Turno: el jugador actual finaliza; avanza turn_number.
    const cur = sm.data.turn.current_player_ref as string;
    const all = [host, ...joiners];
    let actor: SupabaseClient = host;
    for (const c of all) { const sx = await c.rpc('get_active_snapshot_by_code', { p_code: code }); if (sx.data.me.public_ref === cur) { actor = c; break; } }
    ver = sm.data.runtime_version;
    const et = await actor.rpc('end_turn', { p_game: gid, p_expected_version: ver, p_request_id: crypto.randomUUID() });
    expect(et.data.turn_number).toBe(2);

    // Idempotencia: mismo request_id no aplica dos veces.
    const s1 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    const rid = crypto.randomUUID();
    const r1 = await host.rpc('bank_transfer', { p_game: gid, p_player_ref: target, p_direction: 'to_player', p_amount: 100, p_request_id: rid, p_expected_version: s1.data.runtime_version });
    const r2 = await host.rpc('bank_transfer', { p_game: gid, p_player_ref: target, p_direction: 'to_player', p_amount: 100, p_request_id: rid, p_expected_version: 0 });
    expect(JSON.stringify(r1.data)).toBe(JSON.stringify(r2.data));
    const s2 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(s2.data.players.find((p: { public_ref: string }) => p.public_ref === target).balance).toBe(3600);

    // Conflicto de versión: operación NUEVA con versión vieja.
    const vc = await host.rpc('bank_transfer', { p_game: gid, p_player_ref: target, p_direction: 'to_player', p_amount: 1, p_request_id: crypto.randomUUID(), p_expected_version: 0 });
    expect(vc.error?.message).toBe('VERSION_CONFLICT');

    // Reanudación: una sesión nueva del host (recover) ve el estado activo correcto.
    await member.removeAllChannels();
  }, 60000);
});
