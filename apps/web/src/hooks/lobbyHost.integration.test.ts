// @vitest-environment node
// Integración local REAL — controles del anfitrión (Bloque 4). Solo si SB_URL/SB_ANON.
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
async function makeHost() {
  const c = await authed();
  const cg = await c.functions.invoke('create_game', {
    body: { name: 'IT Host', host_name: 'Host', host_token: 'delorean', config: {}, request_id: crypto.randomUUID(), pin: '482915' },
  });
  return { c, code: cg.data.code as string, gid: cg.data.game_id as string, ref: cg.data.host_public_ref as string };
}
function waitSub(ch: RealtimeChannel, ms = 8000): Promise<string> {
  return new Promise((resolve) => {
    let done = false;
    const t = setTimeout(() => { if (!done) { done = true; resolve('TIMEOUT'); } }, ms);
    ch.subscribe((s) => { if (!done && (s === 'SUBSCRIBED' || s === 'CHANNEL_ERROR' || s === 'TIMED_OUT')) { done = true; clearTimeout(t); resolve(s); } });
  });
}

describe.skipIf(!enabled)('Controles del anfitrión — integración local real', () => {
  it('config: host actualiza; no-host -> NOT_HOST; conflicto de versión; otro miembro ve el cambio', async () => {
    const H = await makeHost();
    const J = await authed();
    await J.rpc('join_game', { p_code: H.code, p_name: 'Marty', p_request_id: crypto.randomUUID() });

    const u1 = await H.c.rpc('update_config', { p_game: H.gid, p_patch: { name: 'Renombrada' }, p_expected_version: 0 });
    expect(u1.error).toBeNull();

    const nh = await J.rpc('update_config', { p_game: H.gid, p_patch: { name: 'X' }, p_expected_version: 1 });
    expect(nh.error?.message).toBe('NOT_HOST');

    const vc = await H.c.rpc('update_config', { p_game: H.gid, p_patch: { name: 'Otra' }, p_expected_version: 0 });
    expect(vc.error?.message).toBe('VERSION_CONFLICT');

    const snap = await J.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    expect(snap.data.game.name).toBe('Renombrada');
  }, 30000);

  it('kick: host expulsa; el expulsado deja de obtener snapshot como miembro', async () => {
    const H = await makeHost();
    const J = await authed();
    await J.rpc('join_game', { p_code: H.code, p_name: 'Pedro', p_request_id: crypto.randomUUID() });
    const before = await J.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    const ref = before.data.me.public_ref as string;

    const k = await H.c.rpc('kick_player', { p_game: H.gid, p_target_ref: ref });
    expect(k.error).toBeNull();

    const after = await J.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    expect(after.error?.message).toBe('NOT_ACTIVE_MEMBER');
  }, 30000);

  it('cancel: un miembro recibe game_cancelled por Broadcast', async () => {
    const H = await makeHost();
    const events: unknown[] = [];
    const ch = H.c.channel('room:' + H.code, { config: { private: true, presence: { key: H.ref } } });
    ch.on('broadcast', { event: 'game_cancelled' }, (p) => events.push(p.payload));
    expect(await waitSub(ch)).toBe('SUBSCRIBED');
    await sleep(400);
    await H.c.rpc('cancel_game', { p_game: H.gid });
    await sleep(1800);
    expect(events.length).toBeGreaterThanOrEqual(1);
    await H.c.removeAllChannels();
  }, 30000);

  it('start: <6 no inicia; 6 completos inician; doble inicio idempotente con mismo orden', async () => {
    const H = await makeHost();
    await H.c.rpc('set_ready', { p_game: H.gid, p_ready: true });

    const s1 = await H.c.rpc('start_game', { p_game: H.gid, p_expected_version: 0 });
    expect(s1.error?.message).toBe('NOT_ENOUGH_PLAYERS');

    const toks = ['hoverboard', 'flux_capacitor', 'plutonium_case', 'clock_tower', 'sports_almanac'];
    for (let i = 0; i < 5; i++) {
      const J = await authed();
      await J.rpc('join_game', { p_code: H.code, p_name: 'J' + i, p_request_id: crypto.randomUUID() });
      await J.rpc('choose_token', { p_game: H.gid, p_token: toks[i] });
      await J.rpc('set_ready', { p_game: H.gid, p_ready: true });
    }

    const s2 = await H.c.rpc('start_game', { p_game: H.gid, p_expected_version: 0 });
    expect(s2.error).toBeNull();
    expect(s2.data.status).toBe('active');
    const order1 = JSON.stringify(s2.data.turn_order);

    const s3 = await H.c.rpc('start_game', { p_game: H.gid, p_expected_version: 999 });
    expect(s3.data.idempotent).toBe(true);
    expect(JSON.stringify(s3.data.turn_order)).toBe(order1);
  }, 45000);
});
