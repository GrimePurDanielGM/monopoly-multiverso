// @vitest-environment node
// Integración local REAL — recuperaciones (Bloque 5). Solo si SB_URL/SB_ANON.
// Requiere las Edge Functions create_game/recover_host servidas en local.
import { describe, it, expect } from 'vitest';
import { createClient, FunctionsHttpError, type SupabaseClient } from '@supabase/supabase-js';

const URL = process.env.SB_URL;
const ANON = process.env.SB_ANON;
const enabled = Boolean(URL && ANON);

async function authed(): Promise<SupabaseClient> {
  const c = createClient(URL as string, ANON as string, { auth: { persistSession: false, autoRefreshToken: false } });
  await c.auth.signInAnonymously();
  const { data } = await c.auth.getSession();
  await c.realtime.setAuth(data.session?.access_token ?? '');
  return c;
}
async function makeHost(pin = '482915') {
  const c = await authed();
  const cg = await c.functions.invoke('create_game', {
    body: { name: 'IT Rec', host_name: 'Host', host_token: 'delorean', config: {}, request_id: crypto.randomUUID(), pin },
  });
  return { c, code: cg.data.code as string, gid: cg.data.game_id as string, ref: cg.data.host_public_ref as string };
}
async function recover(c: SupabaseClient, code: string, pin: string): Promise<{ ok: boolean; code?: string; lockedUntil?: string }> {
  const { data, error } = await c.functions.invoke('recover_host', { body: { code, pin } });
  if (!error && data?.ok) return { ok: true };
  if (error instanceof FunctionsHttpError) {
    const b = (await error.context.json()) as { error?: string; locked_until?: string };
    const out: { ok: boolean; code?: string; lockedUntil?: string } = { ok: false };
    if (b.error !== undefined) out.code = b.error;
    if (b.locked_until !== undefined) out.lockedUntil = b.locked_until;
    return out;
  }
  return { ok: false, code: 'NETWORK' };
}

describe.skipIf(!enabled)('Recuperaciones — integración local real', () => {
  it('recuperación de jugador activo: host ve, aprueba, nuevo dispositivo activo, antiguo deja de actuar', async () => {
    const H = await makeHost();
    const J = await authed();
    await J.rpc('join_game', { p_code: H.code, p_name: 'Marty', p_request_id: crypto.randomUUID() });
    const js = await J.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    const martyRef = js.data.me.public_ref as string;

    const D = await authed(); // nuevo dispositivo
    const rr = await D.rpc('request_recovery', { p_code: H.code, p_player_ref: martyRef, p_device: 'iPad' });
    expect(rr.error).toBeNull();
    const reqRef = rr.data.request_ref as string;

    const hostSnap = await H.c.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    expect(hostSnap.data.requests.some((x: { request_ref: string }) => x.request_ref === reqRef)).toBe(true); // (2)

    const res = await H.c.rpc('resolve_recovery', { p_request_ref: reqRef, p_accept: true }); // (3)
    expect(res.error).toBeNull();

    const dSnap = await D.rpc('get_lobby_snapshot_by_code', { p_code: H.code }); // (4)
    expect(dSnap.data.me.public_ref).toBe(martyRef);

    const jAfter = await J.rpc('get_lobby_snapshot_by_code', { p_code: H.code }); // (5) antiguo dispositivo
    expect(jAfter.error?.message).toBe('NOT_ACTIVE_MEMBER');
  }, 30000);

  it('recuperación rechazada -> get_request_status rejected', async () => {
    const H = await makeHost();
    const J = await authed();
    await J.rpc('join_game', { p_code: H.code, p_name: 'Doc', p_request_id: crypto.randomUUID() });
    const ref = (await J.rpc('get_lobby_snapshot_by_code', { p_code: H.code })).data.me.public_ref as string;
    const D = await authed();
    const rr = await D.rpc('request_recovery', { p_code: H.code, p_player_ref: ref, p_device: 'x' });
    await H.c.rpc('resolve_recovery', { p_request_ref: rr.data.request_ref, p_accept: false });
    const st = await D.rpc('get_request_status', { p_request_ref: rr.data.request_ref });
    expect(st.data.status).toBe('rejected');
  }, 30000);

  it('reentrada del expulsado: aprobada crea fila nueva; la histórica sigue expulsada', async () => {
    const H = await makeHost();
    const J = await authed();
    await J.rpc('join_game', { p_code: H.code, p_name: 'Biff', p_request_id: crypto.randomUUID() });
    const ref = (await J.rpc('get_lobby_snapshot_by_code', { p_code: H.code })).data.me.public_ref as string;
    await H.c.rpc('kick_player', { p_game: H.gid, p_target_ref: ref });

    const rr = await J.rpc('request_reentry', { p_code: H.code, p_name: 'Biff2', p_device: 'Android' });
    expect(rr.error).toBeNull();
    const rs = await H.c.rpc('resolve_reentry', { p_request_ref: rr.data.request_ref, p_accept: true });
    expect(rs.error).toBeNull();
    const newRef = rs.data.new_public_ref as string;
    expect(newRef).not.toBe(ref); // (8) fila NUEVA, no reutiliza la histórica

    const after = await J.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    expect(after.data.me.public_ref).toBe(newRef);
    // (9) la fila histórica sigue expulsada: ya no aparece como activa
    expect(after.data.players.some((p: { public_ref: string }) => p.public_ref === ref)).toBe(false);
  }, 30000);

  it('sala llena bloquea la reentrada (GAME_FULL)', async () => {
    const H = await makeHost();
    // 5 joiners -> 6/16; bajamos max a 6 (lleno)
    const joiners: SupabaseClient[] = [];
    for (let i = 0; i < 5; i++) {
      const c = await authed();
      await c.rpc('join_game', { p_code: H.code, p_name: 'P' + i, p_request_id: crypto.randomUUID() });
      joiners.push(c);
    }
    await H.c.rpc('update_config', { p_game: H.gid, p_patch: { max_players: 6 }, p_expected_version: 0 });
    // expulsamos a P0 (5/6) y rellenamos con un nuevo jugador (6/6 lleno)
    const kicked = joiners[0]!;
    const kref = (await kicked.rpc('get_lobby_snapshot_by_code', { p_code: H.code })).data.me.public_ref as string;
    await H.c.rpc('kick_player', { p_game: H.gid, p_target_ref: kref });
    const filler = await authed();
    await filler.rpc('join_game', { p_code: H.code, p_name: 'Filler', p_request_id: crypto.randomUUID() });
    // el expulsado pide reentrada; host intenta aprobar -> GAME_FULL
    const rr = await kicked.rpc('request_reentry', { p_code: H.code, p_name: 'P0bis', p_device: 'x' });
    const rs = await H.c.rpc('resolve_reentry', { p_request_ref: rr.data.request_ref, p_accept: true });
    expect(rs.error?.message).toBe('GAME_FULL');
  }, 45000);

  it('recuperación de host con PIN correcto', async () => {
    const H = await makeHost('482915');
    const D = await authed();
    const r = await recover(D, H.code, '482915');
    expect(r.ok).toBe(true);
    const snap = await D.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    expect(snap.data.me.is_host).toBe(true);
  }, 30000);

  it('recuperación de host en partida ACTIVE: nuevo dispositivo es host, el antiguo lo pierde', async () => {
    const H = await makeHost('482915'); // host con ficha delorean
    const tokens = ['penguin', 'cat', 'boot', 'thimble', 'top_hat'];
    for (let i = 0; i < 5; i++) {
      const c = await authed();
      await c.rpc('join_game', { p_code: H.code, p_name: 'P' + i, p_request_id: crypto.randomUUID() });
      await c.rpc('choose_token', { p_game: H.gid, p_token: tokens[i] });
      await c.rpc('set_ready', { p_game: H.gid, p_ready: true });
    }
    await H.c.rpc('set_ready', { p_game: H.gid, p_ready: true });

    const pre = await H.c.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    const start = await H.c.rpc('start_game', { p_game: H.gid, p_expected_version: pre.data.game.version });
    expect(start.error).toBeNull();
    const act = await H.c.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    expect(act.data.game.status).toBe('active'); // el backend permite recuperar sobre 'active'

    const D = await authed(); // nuevo dispositivo del anfitrión
    const r = await recover(D, H.code, '482915');
    expect(r.ok).toBe(true);
    const dSnap = await D.rpc('get_lobby_snapshot_by_code', { p_code: H.code });
    expect(dSnap.data.me.is_host).toBe(true); // (5) nuevo dispositivo es anfitrión

    const hAfter = await H.c.rpc('get_lobby_snapshot_by_code', { p_code: H.code }); // (6) el antiguo pierde el rol
    expect(hAfter.error?.message === 'NOT_ACTIVE_MEMBER' || hAfter.data?.me?.is_host === false).toBe(true);
  }, 60000);

  it('PIN incorrecto y bloqueo tras 5 intentos', async () => {
    const H = await makeHost('482915');
    const D = await authed();
    let last: { ok: boolean; code?: string; lockedUntil?: string } = { ok: false };
    for (let i = 0; i < 5; i++) last = await recover(D, H.code, '000001');
    expect(last.code).toBe('INVALID_PIN');
    expect(last.lockedUntil).toBeTruthy(); // 5º intento fija el bloqueo
    const sixth = await recover(D, H.code, '000001');
    expect(sixth.code).toBe('LOCKED');
  }, 30000);
});
