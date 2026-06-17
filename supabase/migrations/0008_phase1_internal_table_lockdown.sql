-- Fase 1 — Endurecimiento: el cliente NO accede directamente a tablas internas.
-- El navegador usará SOLO RPC saneadas (peek_game, my_status, get_lobby_snapshot, y las
-- RPC autoritativas). Quitamos todo SELECT directo de authenticated sobre players y games:
--   * auth_uid (y cualquier columna futura) deja de ser legible por PostgREST.
--   * select=* deja de funcionar.
--   * Las funciones SECURITY DEFINER y las políticas RLS siguen leyendo ambas tablas como owner.
-- NO se editan migraciones anteriores. RLS y políticas previas quedan intactas (inertes sin grant).

revoke select on public.players from authenticated;
revoke select on public.games   from authenticated;
-- (token_catalog sigue siendo lectura pública de referencia; host_recovery/audit/request_secrets
--  ya eran deny-all; player_*_requests no contienen auth_uid — el uid vive en request_secrets.)

-- ---------- get_lobby_snapshot: ÚNICA fuente saneada del estado de sala para el cliente ----------
-- Devuelve solo datos públicos. NUNCA: auth_uid, hashes, salts, PIN, ids de sesión ni filas expulsadas.
create or replace function public.get_lobby_snapshot(p_game uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  g public.games;
  me public.players;
  v_is_host boolean;
  v_players jsonb;
  v_requests jsonb := '[]'::jsonb;
  v_pc int; v_rc int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where id = p_game;
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  -- Exige jugador ACTIVO de ESTA partida (auth_uid solo se usa internamente, jamás se devuelve).
  select * into me from public.players where game_id = p_game and auth_uid = v_uid and kicked_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  v_is_host := (me.id = g.host_player_id);

  -- Solo jugadores ACTIVOS, columnas públicas.
  select coalesce(jsonb_agg(jsonb_build_object(
            'public_ref', p.public_ref, 'name', p.display_name, 'token_id', p.token_id,
            'status', p.join_status, 'last_seen_at', p.last_seen_at) order by p.created_at), '[]')
    into v_players
  from public.players p where p.game_id = p_game and p.kicked_at is null;

  select count(*), count(*) filter (where join_status = 'ready')
    into v_pc, v_rc from public.players where game_id = p_game and kicked_at is null;

  -- requests: SOLO para el anfitrión. Para el resto, array vacío (documentado y consistente).
  if v_is_host then
    select coalesce(jsonb_agg(req order by ord), '[]') into v_requests from (
      select jsonb_build_object('request_ref', r.public_ref, 'kind', 'recovery', 'status', r.status,
               'target_public_ref', tp.public_ref, 'device_label', r.device_label) as req, r.created_at as ord
      from public.player_recovery_requests r
      join public.players tp on tp.id = r.player_id
      where r.game_id = p_game and r.status = 'pending'
      union all
      select jsonb_build_object('request_ref', rr.public_ref, 'kind', 'reentry', 'status', rr.status,
               'target_public_ref', pp.public_ref, 'device_label', rr.device_label), rr.created_at
      from public.player_reentry_requests rr
      join public.players pp on pp.id = rr.prior_player_id
      where rr.game_id = p_game and rr.status = 'pending'
    ) s;
  end if;

  return jsonb_build_object(
    'game', jsonb_build_object(
      'id', g.id, 'code', g.code, 'name', g.name, 'status', g.status,
      'version', g.version, 'started_at', g.started_at, 'cancelled_at', g.cancelled_at,
      'host_public_ref', (select public_ref from public.players where id = g.host_player_id),
      'config', jsonb_build_object(
        'min_players',   coalesce((g.config->>'min_players')::int, 6),
        'max_players',   coalesce((g.config->>'max_players')::int, 16),
        'initial_money', coalesce((g.config->>'initial_money')::int, 3000),
        'token_catalog_version', coalesce((g.config->>'token_catalog_version')::int, 0))),
    'players', v_players,
    'me', jsonb_build_object(
      'public_ref', me.public_ref, 'is_host', v_is_host,
      'join_status', me.join_status, 'token_id', me.token_id, 'membership', 'active'),
    'requests', v_requests,
    'counts', jsonb_build_object(
      'player_count', v_pc, 'ready_count', v_rc,
      'min_players', coalesce((g.config->>'min_players')::int, 6),
      'max_players', coalesce((g.config->>'max_players')::int, 16))
  );
end $$;

revoke execute on function public.get_lobby_snapshot(uuid) from public;
grant  execute on function public.get_lobby_snapshot(uuid) to authenticated;
