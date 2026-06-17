// @vitest-environment node
// Integración local REAL de Realtime (0009). Se ejecuta solo si SB_URL/SB_ANON están
// definidos (apunta a Supabase local). Verifica con varios clientes anónimos reales.
import { describe, it, expect } from 'vitest';
import { createClient, type RealtimeChannel } from '@supabase/supabase-js';

const URL = process.env.SB_URL;
const ANON = process.env.SB_ANON;
const enabled = Boolean(URL && ANON);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function authed() {
  const c = createClient(URL as string, ANON as string, { auth: { persistSession: false, autoRefreshToken: false } });
  await c.auth.signInAnonymously();
  const { data } = await c.auth.getSession();
  await c.realtime.setAuth(data.session?.access_token ?? '');
  return c;
}
function waitSub(ch: RealtimeChannel, ms = 8000): Promise<string> {
  return new Promise((resolve) => {
    let done = false;
    const t = setTimeout(() => { if (!done) { done = true; resolve('TIMEOUT'); } }, ms);
    ch.subscribe((s) => {
      if (!done && (s === 'SUBSCRIBED' || s === 'CHANNEL_ERROR' || s === 'TIMED_OUT')) { done = true; clearTimeout(t); resolve(s); }
    });
  });
}

describe.skipIf(!enabled)('Realtime lobby — integración local real', () => {
  it('miembro recibe; no-miembro no; presence de dos; sin spoof; heartbeat actualiza last_seen_at', async () => {
    const M = await authed();
    const cg = await M.functions.invoke('create_game', {
      body: { name: 'RT IT', host_name: 'Host', host_token: 'delorean', config: {}, request_id: crypto.randomUUID(), pin: '482915' },
    });
    const code = cg.data.code as string, gid = cg.data.game_id as string, hostRef = cg.data.host_public_ref as string;

    const M2 = await authed();
    await M2.rpc('join_game', { p_code: code, p_name: 'Marty', p_request_id: crypto.randomUUID() });
    await M2.rpc('choose_token', { p_game: gid, p_token: 'hoverboard' }); // necesita ficha antes de ready
    const snap0 = await M2.rpc('get_lobby_snapshot_by_code', { p_code: code });
    const m2Ref = snap0.data.me.public_ref as string;

    const N = await authed(); // no-miembro

    const mEvents: unknown[] = [];
    let mPresence: Record<string, unknown> = {};
    const chM = M.channel('room:' + code, { config: { private: true, presence: { key: hostRef } } });
    chM.on('broadcast', { event: 'lobby_changed' }, (p) => mEvents.push(p.payload));
    chM.on('presence', { event: 'sync' }, () => { mPresence = chM.presenceState(); });
    const mSub = await waitSub(chM);
    await chM.track({ public_ref: hostRef });

    const m2Events: unknown[] = [];
    const chM2 = M2.channel('room:' + code, { config: { private: true, presence: { key: m2Ref } } });
    chM2.on('broadcast', { event: 'lobby_changed' }, (p) => m2Events.push(p.payload));
    await waitSub(chM2);
    await chM2.track({ public_ref: m2Ref });

    const nEvents: unknown[] = [];
    const chN = N.channel('room:' + code, { config: { private: true } });
    chN.on('broadcast', { event: 'lobby_changed' }, (p) => nEvents.push(p.payload));
    const nSub = await waitSub(chN);

    await sleep(700);

    // (3/4) mutación autoritativa -> lobby_changed -> receptor recarga y ve nuevo estado
    await M2.rpc('set_ready', { p_game: gid, p_ready: true });
    await sleep(2000);
    const snap1 = await M.rpc('get_lobby_snapshot_by_code', { p_code: code });

    // (5) el cliente NO puede emitir broadcast oficial: M intenta spoof, M2 no debe recibirlo
    const beforeM2 = m2Events.length;
    await chM.send({ type: 'broadcast', event: 'lobby_changed', payload: { game_id: gid } });
    await sleep(900);
    const afterM2 = m2Events.length;

    // (8) heartbeat actualiza last_seen_at
    const lsBefore = snap1.data.players.find((p: { public_ref: string }) => p.public_ref === hostRef)?.last_seen_at;
    await sleep(1100);
    await M.rpc('heartbeat', { p_game: gid });
    await sleep(500);
    const snap2 = await M.rpc('get_lobby_snapshot_by_code', { p_code: code });
    const lsAfter = snap2.data.players.find((p: { public_ref: string }) => p.public_ref === hostRef)?.last_seen_at;

    const presenceKeys = Object.keys(mPresence).sort();

    // (7) presence desaparece al cerrar un cliente
    await M2.removeAllChannels();
    await sleep(1500);
    const presenceAfterClose = Object.keys(chM.presenceState());

    await M.removeAllChannels();
    await N.removeAllChannels();

    expect(mSub).toBe('SUBSCRIBED'); // (1)
    expect(nSub).toBe('CHANNEL_ERROR'); // (2)
    expect(mEvents.length).toBeGreaterThanOrEqual(1); // (3)
    expect(nEvents.length).toBe(0);
    expect(snap1.data.counts.ready_count).toBe(1); // (4)
    expect(afterM2).toBe(beforeM2); // (5) spoof no entregado
    expect(presenceKeys).toEqual([hostRef, m2Ref].sort()); // (6)
    expect(presenceAfterClose).not.toContain(m2Ref); // (7)
    expect(lsAfter).not.toBe(lsBefore); // (8)
  }, 40000);
});
