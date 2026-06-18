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

/** Crea una partida y la lleva a 'active' con 6 jugadores. Devuelve clientes + code/gid.
 *  `cfg` aplica un update_config en lobby (p. ej. { allow_late_join: true, max_players: 7 }). */
async function startedGame(cfg?: Record<string, unknown>) {
  const host = await authed();
  const cg = await host.functions.invoke('create_game', {
    body: { name: 'Activa IT', host_name: 'Host', host_token: 'penguin', config: {}, request_id: crypto.randomUUID(), pin: '482915' },
  });
  const code = cg.data.code as string;
  const gid = cg.data.game_id as string;
  if (cfg) {
    const v = await host.rpc('get_lobby_snapshot_by_code', { p_code: code });
    await host.rpc('update_config', { p_game: gid, p_patch: cfg, p_expected_version: v.data.game.version });
  }
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

  it('reanudación de jugador normal en partida activa: misma sesión y recuperación', async () => {
    const { host, joiners, code } = await startedGame();
    const J = joiners[0]!; // jugador normal
    const s0 = await J.rpc('get_active_snapshot_by_code', { p_code: code });
    const ref0 = s0.data.me.public_ref as string;
    const bal0 = s0.data.me.balance as number;
    const order0 = JSON.stringify(s0.data.turn.order);
    const ver0 = s0.data.runtime_version as number;

    // (4) Misma sesión: vuelve a pedir el snapshot -> sigue dentro, mismo ref y saldo.
    const same = await J.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(same.data.me.public_ref).toBe(ref0);
    expect(same.data.me.balance).toBe(bal0);

    // (5-7) Sesión nueva (otro dispositivo) solicita recuperar la identidad activa; host aprueba.
    const D = await authed();
    const rr = await D.rpc('request_recovery', { p_code: code, p_player_ref: ref0, p_device: 'iPad' });
    expect(rr.error).toBeNull();
    const res = await host.rpc('resolve_recovery', { p_request_ref: rr.data.request_ref, p_accept: true });
    expect(res.error).toBeNull();

    // (8) La sesión nueva carga el snapshot activo y es el MISMO jugador (no uno nuevo).
    const dSnap = await D.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(dSnap.data.me.public_ref).toBe(ref0);
    expect(dSnap.data.me.is_host).toBe(false);
    // (10-11) Sin fila nueva, mismo saldo, mismo orden.
    expect(dSnap.data.players.length).toBe(6);
    expect(dSnap.data.players.find((p: { public_ref: string }) => p.public_ref === ref0).balance).toBe(bal0);
    expect(JSON.stringify(dSnap.data.turn.order)).toBe(order0);
    // (13) runtime_version no cambia por la recuperación (no es una operación económica/turno).
    expect(dSnap.data.runtime_version).toBe(ver0);

    // (9) La sesión antigua pierde el control.
    const old = await J.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(old.error?.message).toBe('NOT_ACTIVE_MEMBER');
  }, 60000);

  it('control: pausa bloquea, reanudar restaura, finalizar es terminal', async () => {
    const { host, joiners, code, gid } = await startedGame();
    const s0 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    let ver = s0.data.runtime_version as number;
    const cur = s0.data.turn.current_player_ref as string;
    const all = [host, ...joiners];
    let actor = host;
    for (const c of all) { const sx = await c.rpc('get_active_snapshot_by_code', { p_code: code }); if (sx.data.me.public_ref === cur) { actor = c; break; } }

    // Pausar -> snapshot paused y mutaciones bloqueadas.
    const pz = await host.rpc('pause_game_runtime', { p_game: gid, p_reason: 'descanso', p_request_id: crypto.randomUUID(), p_expected_version: ver });
    expect(pz.error).toBeNull();
    const sp = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(sp.data.runtime_status).toBe('paused');
    const blocked = await actor.rpc('end_turn', { p_game: gid, p_expected_version: sp.data.runtime_version, p_request_id: crypto.randomUUID() });
    expect(blocked.error?.message).toBe('GAME_PAUSED');

    // Reanudar -> running y end_turn vuelve a funcionar.
    ver = sp.data.runtime_version;
    await host.rpc('resume_game_runtime', { p_game: gid, p_request_id: crypto.randomUUID(), p_expected_version: ver });
    const sr = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(sr.data.runtime_status).toBe('running');
    const et = await actor.rpc('end_turn', { p_game: gid, p_expected_version: sr.data.runtime_version, p_request_id: crypto.randomUUID() });
    expect(et.error).toBeNull();

    // Finalizar -> terminal; mutaciones -> GAME_FINISHED; snapshot legible.
    const sf0 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    await host.rpc('finish_game_runtime', { p_game: gid, p_reason: 'fin', p_request_id: crypto.randomUUID(), p_expected_version: sf0.data.runtime_version });
    const sf = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(sf.data.runtime_status).toBe('finished');
    const after = await host.rpc('bank_transfer', { p_game: gid, p_player_ref: sf.data.turn.order[1], p_direction: 'to_player', p_amount: 10, p_request_id: crypto.randomUUID(), p_expected_version: sf.data.runtime_version });
    expect(after.error?.message).toBe('GAME_FINISHED');
  }, 60000);

  it('incorporación tardía: solicitar, aprobar (al final del orden), rechazar y finished bloquea', async () => {
    const { host, code, gid } = await startedGame({ allow_late_join: true, max_players: 8 });
    const s0 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    const cur0 = s0.data.turn.current_player_ref as string;
    const order0 = (s0.data.turn.order as string[]).slice();

    // Solicitud de una sesión nueva.
    const D = await authed();
    const rr = await D.rpc('request_late_join', { p_code: code, p_name: 'Tardío', p_token: 'clock_tower', p_device_label: 'iPad' });
    expect(rr.error).toBeNull();
    expect(rr.data.status).toBe('pending');

    // El anfitrión la ve en el snapshot.
    const sh = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(sh.data.late_join_requests.some((x: { request_ref: string }) => x.request_ref === rr.data.request_ref)).toBe(true);

    // Aprobar: el nuevo jugador entra con saldo inicial, al final del orden; turno actual intacto.
    const res = await host.rpc('resolve_late_join', { p_request_ref: rr.data.request_ref, p_accept: true, p_expected_version: sh.data.runtime_version });
    expect(res.error).toBeNull();
    const np = res.data.new_public_ref as string;
    const dS = await D.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(dS.data.me.public_ref).toBe(np);
    expect(dS.data.me.balance).toBe(3000);
    expect(dS.data.turn.order[dS.data.turn.order.length - 1]).toBe(np);     // al final
    expect(dS.data.turn.order.slice(0, order0.length)).toEqual(order0);     // sin reordenar
    expect(dS.data.turn.current_player_ref).toBe(cur0);                      // turno actual intacto

    // Rechazo: una segunda solicitud rechazada no crea nada.
    const E = await authed();
    const rr2 = await E.rpc('request_late_join', { p_code: code, p_name: 'Octavo', p_token: 'einstein_dog', p_device_label: 'x' });
    const s2 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    await host.rpc('resolve_late_join', { p_request_ref: rr2.data.request_ref, p_accept: false, p_expected_version: s2.data.runtime_version });
    const st = await E.rpc('get_request_status', { p_request_ref: rr2.data.request_ref });
    expect(st.data.status).toBe('rejected');
    const eS = await E.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(eS.error?.message).toBe('NOT_ACTIVE_MEMBER'); // no se creó jugador

    // Finalizar: nuevas solicitudes -> GAME_FINISHED.
    const s3 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    await host.rpc('finish_game_runtime', { p_game: gid, p_reason: 'fin', p_request_id: crypto.randomUUID(), p_expected_version: s3.data.runtime_version });
    const F = await authed();
    const blocked = await F.rpc('request_late_join', { p_code: code, p_name: 'Tarde', p_token: 'rider', p_device_label: 'x' });
    expect(blocked.error?.message).toBe('GAME_FINISHED');
  }, 90000);

  it('salida: el jugador abandona (saldo a la banca), sale del orden, turno intacto y no puede actuar', async () => {
    const { host, joiners, code, gid } = await startedGame();
    const s0 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    const cur = s0.data.turn.current_player_ref as string;
    const refs = await Promise.all(joiners.map(async (c) =>
      (await c.rpc('get_active_snapshot_by_code', { p_code: code })).data.me.public_ref as string));
    const idx = refs.findIndex((r) => r !== cur);     // un jugador NO actual (ni host)
    const leaver = joiners[idx]!; const leaverRef = refs[idx]!;

    const lr = await leaver.rpc('leave_active_game', { p_game: gid, p_resolution_mode: 'to_bank', p_request_id: crypto.randomUUID(), p_expected_version: s0.data.runtime_version });
    expect(lr.error).toBeNull();

    const sh = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    expect((sh.data.turn.order as string[]).includes(leaverRef)).toBe(false);   // fuera del orden
    expect(sh.data.turn.current_player_ref).toBe(cur);                          // turno intacto
    expect((sh.data.players as { public_ref: string }[]).some((p) => p.public_ref === leaverRef)).toBe(false);
    const led = (sh.data.ledger_recent as { kind: string; from_ref: string | null; amount: number }[])
      .find((l) => l.kind === 'player_exit_to_bank' && l.from_ref === leaverRef);
    expect(led?.amount).toBe(3000);                                            // saldo devuelto a la banca

    // El saliente deja de ser miembro: ni snapshot activo ni de lobby, y no puede actuar.
    const self = await leaver.rpc('get_active_snapshot_by_code', { p_code: code });
    expect(self.error?.message).toBe('NOT_ACTIVE_MEMBER');
    const selfLobby = await leaver.rpc('get_lobby_snapshot_by_code', { p_code: code });
    expect(selfLobby.error?.message).toBe('NOT_ACTIVE_MEMBER');
    const act = await leaver.rpc('end_turn', { p_game: gid, p_expected_version: sh.data.runtime_version, p_request_id: crypto.randomUUID() });
    expect(act.error?.message).toBe('NOT_ACTIVE_MEMBER');
  }, 90000);

  it('expulsión con reparto: el host reparte el saldo entre restantes (resto a la banca) y reconcilia', async () => {
    const { host, joiners, code, gid } = await startedGame();
    const s0 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    const victimRef = (await joiners[0]!.rpc('get_active_snapshot_by_code', { p_code: code })).data.me.public_ref as string;

    // Fijar 1001: restantes = 5 (host + 4) -> 200 c/u, resto 1 a la banca (ejemplo del enunciado, escalado).
    await host.rpc('host_adjust_balance', { p_game: gid, p_target_ref: victimRef, p_new_balance: 1001, p_reason: 'preparar reparto', p_request_id: crypto.randomUUID(), p_expected_version: s0.data.runtime_version });
    const s1 = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    const rm = await host.rpc('remove_active_player', { p_game: gid, p_target_ref: victimRef, p_resolution_mode: 'distribute', p_reason: 'expulsión', p_request_id: crypto.randomUUID(), p_expected_version: s1.data.runtime_version });
    expect(rm.error).toBeNull();

    const sh = await host.rpc('get_active_snapshot_by_code', { p_code: code });
    expect((sh.data.players as { public_ref: string }[]).some((p) => p.public_ref === victimRef)).toBe(false);
    const ledger = sh.data.ledger_recent as { kind: string; from_ref: string | null; amount: number }[];
    const dist = ledger.filter((l) => l.kind === 'player_exit_distribution' && l.from_ref === victimRef);
    expect(dist.length).toBe(5);
    expect(dist.every((l) => l.amount === 200)).toBe(true);
    const rem = ledger.find((l) => l.kind === 'player_exit_remainder_to_bank' && l.from_ref === victimRef);
    expect(rem?.amount).toBe(1);

    // Reconciliación: cada restante recibió +200 (3000 -> 3200); la víctima queda fuera (no listada).
    expect((sh.data.players as { balance: number }[]).every((p) => p.balance === 3200)).toBe(true);

    // Permisos: un jugador normal NO puede expulsar.
    const otherRef = (await joiners[2]!.rpc('get_active_snapshot_by_code', { p_code: code })).data.me.public_ref as string;
    const bad = await joiners[1]!.rpc('remove_active_player', { p_game: gid, p_target_ref: otherRef, p_resolution_mode: 'to_bank', p_reason: 'x', p_request_id: crypto.randomUUID(), p_expected_version: sh.data.runtime_version });
    expect(bad.error?.message).toBe('NOT_HOST');
  }, 90000);
});
