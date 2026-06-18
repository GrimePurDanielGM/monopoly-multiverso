-- Fase 2 — Incorporaciones tardías durante una partida iniciada, con aprobación del
-- anfitrión. config.allow_late_join (default false, solo en lobby). Flujo separado de
-- recuperación de identidad y de reentrada de expulsados.

-- ── 1) Whitelist de configuración: allow_late_join (solo lobby) ───────────────────
create or replace function public.update_config(p_game uuid, p_patch jsonb, p_expected_version int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; v_cfg jsonb; v_active_tokens int; v_max int; v_min int;
begin
  g := public._require_host(p_game);
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  if g.version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  v_cfg := g.config;
  if p_patch ? 'name' then
    if char_length(btrim(p_patch->>'name')) not between 3 and 40 then raise exception 'INVALID_GAME_NAME'; end if;
    update public.games set name=btrim(p_patch->>'name') where id=g.id;
  end if;
  v_cfg := v_cfg
    || (case when p_patch ? 'initial_money'   then jsonb_build_object('initial_money',(p_patch->>'initial_money')::int) else '{}'::jsonb end)
    || (case when p_patch ? 'min_players'     then jsonb_build_object('min_players',(p_patch->>'min_players')::int)   else '{}'::jsonb end)
    || (case when p_patch ? 'max_players'     then jsonb_build_object('max_players',(p_patch->>'max_players')::int)   else '{}'::jsonb end)
    || (case when p_patch ? 'allow_late_join' then jsonb_build_object('allow_late_join',(p_patch->>'allow_late_join')::boolean) else '{}'::jsonb end);
  v_min := coalesce((v_cfg->>'min_players')::int,6);
  v_max := coalesce((v_cfg->>'max_players')::int,16);
  if v_min < 2 or v_min > v_max or v_max > 16 then raise exception 'INVALID_PLAYER_LIMITS'; end if;
  select count(*) into v_active_tokens from public.token_catalog
    where active and catalog_version=coalesce((v_cfg->>'token_catalog_version')::int,0);
  if v_max > v_active_tokens then raise exception 'MAX_EXCEEDS_TOKENS'; end if;
  update public.games set config=v_cfg, version=version+1 where id=g.id returning * into g;
  perform public._audit(g.id,'config_changed',auth.uid(),null,null,null,g.config,null,false);
  return jsonb_build_object('version',g.version,'config',g.config,'name',g.name);
end $$;

-- ── 2) Tabla de solicitudes de incorporación tardía (deny-all; uid en request_secrets) ──
create table public.late_join_requests (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null default public.gen_public_ref(),
  game_id uuid not null references public.games(id) on delete cascade,
  desired_name text not null,
  desired_token text not null,
  device_label text null,
  status request_status not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  new_player_id uuid null references public.players(id) on delete set null
);
create unique index late_join_pubref_key on public.late_join_requests (game_id, public_ref);
create index        late_join_pending_idx on public.late_join_requests (game_id) where status='pending';
alter table public.late_join_requests enable row level security;        -- sin políticas => deny-all
revoke all on public.late_join_requests from anon, authenticated;

-- ── 3) Ledger: nuevo tipo late_join_seed (banco -> jugador, con request_id) ───────
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check check (kind in
  ('seed','bank_to_player','player_to_bank','player_to_player','host_player_transfer','host_adjust','host_revert','late_join_seed'));
alter table public.ledger drop constraint ledger_shape;
alter table public.ledger add constraint ledger_shape check (
  case kind
    when 'seed' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is null and before_balance is null and after_balance is null
    when 'late_join_seed' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'bank_to_player' then
      from_ref is null and to_ref is not null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_bank' then
      from_ref is not null and to_ref is null and reverts_ledger_id is null
      and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_player' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'host_player_transfer' then
      from_ref is not null and to_ref is not null and from_ref <> to_ref
      and reason is not null and reverts_ledger_id is null and request_id is not null
      and before_balance is null and after_balance is null
    when 'host_adjust' then
      before_balance is not null and after_balance is not null
      and before_balance <> after_balance
      and amount = abs(after_balance - before_balance)
      and ((after_balance > before_balance and from_ref is null     and to_ref is not null)
        or (after_balance < before_balance and from_ref is not null and to_ref is null))
      and reason is not null and reverts_ledger_id is null and request_id is not null
    when 'host_revert' then
      reverts_ledger_id is not null and reason is not null and request_id is not null
      and before_balance is null and after_balance is null
      and ( ((from_ref is null) <> (to_ref is null))
         or (from_ref is not null and to_ref is not null and from_ref <> to_ref) )
    else false
  end
);

-- ── 4) request_late_join: sesión nueva pide entrar (active + opción + sin jugador) ──
create or replace function public.request_late_join(p_code text, p_name text, p_token text, p_device_label text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); g public.games; rt public.game_runtime; r public.late_join_requests;
        v_active int; v_max int; v_existing public.late_join_requests;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where code = upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  if g.status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  select * into rt from public.game_runtime where game_id=g.id for update;          -- serializa
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  if not coalesce((g.config->>'allow_late_join')::boolean, false) then raise exception 'LATE_JOIN_DISABLED'; end if;
  perform 1 from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is not null;
  if found then raise exception 'KICKED_USE_REENTRY'; end if;
  perform 1 from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is null;
  if found then raise exception 'SESSION_HAS_ACTIVE_PLAYER'; end if;
  -- Idempotencia: solicitud pendiente existente de ESTA sesión.
  select lr.* into v_existing from public.late_join_requests lr
    join public.request_secrets s on s.request_id = lr.id
    where lr.game_id=g.id and lr.status='pending' and s.requester_auth_uid=v_uid;
  if found then return jsonb_build_object('request_ref', v_existing.public_ref, 'status', v_existing.status); end if;
  -- Plaza / nombre / ficha (revalidados al aprobar).
  v_max := coalesce((g.config->>'max_players')::int,16);
  select count(*) into v_active from public.players where game_id=g.id and kicked_at is null;
  if v_active >= v_max then raise exception 'GAME_FULL'; end if;
  if char_length(btrim(p_name)) not between 2 and 24 then raise exception 'INVALID_NAME'; end if;
  perform 1 from public.players where game_id=g.id and kicked_at is null and display_name_norm = public.normalize_name(p_name);
  if found then raise exception 'NAME_TAKEN'; end if;
  perform 1 from public.token_catalog where id=p_token and active and catalog_version=coalesce((g.config->>'token_catalog_version')::int,0);
  if not found then raise exception 'TOKEN_INVALID'; end if;
  perform 1 from public.players where game_id=g.id and kicked_at is null and token_id=p_token;
  if found then raise exception 'TOKEN_TAKEN'; end if;
  insert into public.late_join_requests(game_id, desired_name, desired_token, device_label)
    values (g.id, btrim(p_name), p_token, p_device_label) returning * into r;
  insert into public.request_secrets(request_id, requester_auth_uid) values (r.id, v_uid);
  perform public._audit(g.id,'late_join_requested',v_uid,null,null,null,
    jsonb_build_object('request',r.public_ref,'name',r.desired_name,'token',r.desired_token),null,false);
  perform public._emit_active_signal(g.id);   -- notifica al anfitrión (re-fetch del snapshot)
  return jsonb_build_object('request_ref', r.public_ref, 'status', r.status);
end $$;

-- ── 5) resolve_late_join: el anfitrión aprueba/rechaza (revalida; crea jugador) ────
create or replace function public.resolve_late_join(p_request_ref text, p_accept boolean, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.late_join_requests; g public.games; rt public.game_runtime; v_uid uuid;
        v_active int; v_max int; v_init int; np public.players; v_ver bigint;
begin
  select * into r from public.late_join_requests where public_ref=p_request_ref for update;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(r.game_id);                       -- bloquea games + valida host
  if g.status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'idempotent', true); end if;
  select * into rt from public.game_runtime where game_id=g.id for update;
  if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
  if not p_accept then
    update public.late_join_requests set status='rejected', resolved_at=now() where id=r.id;
    perform public._audit(g.id,'late_join_rejected',auth.uid(),null,null,null,jsonb_build_object('request',r.public_ref),null,false);
    perform public._emit_active_signal(g.id);   -- el anfitrión (otros dispositivos) actualiza la bandeja
    return jsonb_build_object('status','rejected');
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  -- Revalidar opción / plaza / nombre / ficha / sesión (pudieron cambiar desde la solicitud).
  if not coalesce((g.config->>'allow_late_join')::boolean,false) then raise exception 'LATE_JOIN_DISABLED'; end if;
  v_max := coalesce((g.config->>'max_players')::int,16);
  select count(*) into v_active from public.players where game_id=g.id and kicked_at is null;
  if v_active >= v_max then raise exception 'GAME_FULL'; end if;
  perform 1 from public.players where game_id=g.id and kicked_at is null and display_name_norm=public.normalize_name(r.desired_name);
  if found then raise exception 'NAME_TAKEN'; end if;
  perform 1 from public.token_catalog where id=r.desired_token and active and catalog_version=coalesce((g.config->>'token_catalog_version')::int,0);
  if not found then raise exception 'TOKEN_INVALID'; end if;
  perform 1 from public.players where game_id=g.id and kicked_at is null and token_id=r.desired_token;
  if found then raise exception 'TOKEN_TAKEN'; end if;
  select requester_auth_uid into v_uid from public.request_secrets where request_id=r.id;
  perform 1 from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is null;
  if found then raise exception 'SESSION_HAS_ACTIVE_PLAYER'; end if;
  -- Crear jugador, saldo y ledger; añadir al FINAL del orden sin tocar el turno actual.
  begin
    insert into public.players(game_id, auth_uid, display_name, token_id, join_status)
      values (g.id, v_uid, r.desired_name, r.desired_token, 'ready') returning * into np;
  exception when unique_violation then raise exception 'NAME_TAKEN'; end;
  v_init := coalesce((g.config->>'initial_money')::int, 3000);
  insert into public.player_balances(game_id, player_ref, balance) values (g.id, np.public_ref, v_init);
  if v_init > 0 then
    perform public._p2_post(g.id, 'late_join_seed', null, np.public_ref, v_init, null, null, null, null, null, r.id);
  end if;
  update public.game_runtime set turn_order_refs = turn_order_refs || np.public_ref where game_id=g.id; -- al final; turn_index/turn_number/current intactos
  v_ver := public._p2_bump(g.id);
  perform public._audit(g.id,'late_join_approved',auth.uid(),np.id,array[np.id],null,
    jsonb_build_object('request',r.public_ref,'player',np.public_ref,'balance',v_init,'appended_at_end',true),null,false);
  perform public._emit_active_signal(g.id);
  update public.late_join_requests set status='approved', resolved_at=now(), new_player_id=np.id where id=r.id;
  return jsonb_build_object('status','approved','new_public_ref',np.public_ref,'runtime_version',v_ver);
end $$;

-- ── 6) get_request_status: añade late_join (compatibilidad, salida saneada) ───────
create or replace function public.get_request_status(p_request_ref text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v text;
begin
  select status::text into v from public.player_recovery_requests where public_ref=p_request_ref;
  if found then return jsonb_build_object('kind','recovery','status',v); end if;
  select status::text into v from public.player_reentry_requests where public_ref=p_request_ref;
  if found then return jsonb_build_object('kind','reentry','status',v); end if;
  select status::text into v from public.late_join_requests where public_ref=p_request_ref;
  if found then return jsonb_build_object('kind','late_join','status',v); end if;
  raise exception 'REQUEST_NOT_FOUND' using errcode='P0002';
end $$;

grant execute on function public.request_late_join(text, text, text, text)        to authenticated;
grant execute on function public.resolve_late_join(text, boolean, bigint)          to authenticated;

-- Snapshot de lobby: inyecta allow_late_join en config (sin recrear el helper grande)
-- para que el anfitrión vea y configure la opción antes de iniciar.
create or replace function public.get_lobby_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid; v_snap jsonb; v_allow boolean;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select id into v_id from public.games where code = upper(btrim(p_code));
  if v_id is null then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  v_snap := public._lobby_snapshot(v_id, auth.uid());
  select coalesce((config->>'allow_late_join')::boolean, false) into v_allow from public.games where id = v_id;
  return jsonb_set(v_snap, '{game,config,allow_late_join}', to_jsonb(v_allow));
end $$;
revoke execute on function public.get_lobby_snapshot_by_code(text) from public;
grant  execute on function public.get_lobby_snapshot_by_code(text) to authenticated;

-- ── 7) Snapshot activo: config.allow_late_join + solicitudes tardías (solo anfitrión) ──
create or replace function public.get_active_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; rt public.game_runtime; me public.players; v_cur text; v_players jsonb; v_ledger jsonb;
        v_is_host boolean; v_late jsonb;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where code = upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode = 'P0002'; end if;
  if g.status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  select * into me from public.players where game_id = g.id and auth_uid = auth.uid() and kicked_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  select * into rt from public.game_runtime where game_id = g.id;
  v_cur := rt.turn_order_refs[rt.turn_index];
  v_is_host := me.id = g.host_player_id;

  select jsonb_agg(jsonb_build_object(
           'public_ref', p.public_ref, 'display_name', p.display_name, 'token_id', p.token_id,
           'balance', b.balance, 'is_current', p.public_ref = v_cur)
           order by array_position(rt.turn_order_refs, p.public_ref))
    into v_players
    from public.players p
    join public.player_balances b on b.game_id = p.game_id and b.player_ref = p.public_ref
    where p.game_id = g.id and p.public_ref = any(rt.turn_order_refs);

  select jsonb_agg(jsonb_build_object(
           'ledger_ref', l.ledger_ref, 'seq', l.seq, 'kind', l.kind, 'from_ref', l.from_ref, 'to_ref', l.to_ref,
           'amount', l.amount, 'before_balance', l.before_balance, 'after_balance', l.after_balance,
           'reason', l.reason, 'actor_ref', l.actor_ref,
           'reverts_ref', (select r.ledger_ref from public.ledger r where r.id = l.reverts_ledger_id),
           'created_at', l.created_at) order by l.seq desc)
    into v_ledger
    from (select * from public.ledger where game_id = g.id order by seq desc limit 25) l;

  -- Solicitudes tardías pendientes: SOLO para el anfitrión, saneadas (sin uid ni ids internos).
  if v_is_host then
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', lr.public_ref, 'name', lr.desired_name, 'token', lr.desired_token,
             'device_label', lr.device_label) order by lr.created_at), '[]'::jsonb)
      into v_late from public.late_join_requests lr where lr.game_id=g.id and lr.status='pending';
  else
    v_late := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'game', jsonb_build_object('code', g.code, 'status', g.status,
      'config', jsonb_build_object(
        'initial_money', coalesce((g.config->>'initial_money')::int, 3000),
        'min_players',   coalesce((g.config->>'min_players')::int, 6),
        'max_players',   coalesce((g.config->>'max_players')::int, 16),
        'allow_late_join', coalesce((g.config->>'allow_late_join')::boolean, false))),
    'me', jsonb_build_object('public_ref', me.public_ref, 'is_host', v_is_host,
      'balance', (select balance from public.player_balances where game_id = g.id and player_ref = me.public_ref),
      'is_current', me.public_ref = v_cur),
    'turn', jsonb_build_object('turn_number', rt.turn_number, 'current_player_ref', v_cur,
      'order', to_jsonb(rt.turn_order_refs)),
    'players', coalesce(v_players, '[]'::jsonb),
    'ledger_recent', coalesce(v_ledger, '[]'::jsonb),
    'late_join_requests', v_late,
    'runtime_status', rt.runtime_status,
    'control', jsonb_build_object(
      'paused_by_ref', rt.paused_by_ref, 'finished_by_ref', rt.finished_by_ref, 'reason', rt.status_reason),
    'runtime_version', rt.runtime_version);
end $$;

-- ── 8) peek_game: expone allow_late_join (para que /j decida el flujo en activa) ──
create or replace function public.peek_game(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; v_active int; v_max int; v_taken text[];
begin
  select * into g from public.games where code = upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  select count(*) into v_active from public.players where game_id=g.id and kicked_at is null;
  v_max := coalesce((g.config->>'max_players')::int, 16);
  select array_agg(token_id) into v_taken from public.players where game_id=g.id and kicked_at is null and token_id is not null;
  return jsonb_build_object(
    'name', g.name, 'status', g.status,
    'player_count', v_active, 'max_players', v_max,
    'open_slots', greatest(v_max - v_active, 0),
    'accepts_entries', (g.status='lobby' and v_active < v_max),
    'allow_late_join', coalesce((g.config->>'allow_late_join')::boolean, false),
    'available_tokens', (
      select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',label,'icon',icon) order by sort_order),'[]')
      from public.token_catalog
      where active and catalog_version = coalesce((g.config->>'token_catalog_version')::int,0)
        and id <> all(coalesce(v_taken,'{}'))
    ),
    'players', (select coalesce(jsonb_agg(public._player_public(p) order by p.created_at),'[]')
                from public.players p where p.game_id=g.id and p.kicked_at is null)
  );
end $$;
