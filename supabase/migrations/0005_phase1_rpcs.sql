-- Fase 1 — RPCs autoritativas. Todas SECURITY DEFINER, search_path fijo,
-- validan auth.uid() + pertenencia + estado + permisos + no-expulsado.

-- Helper de auditoría: requiere games BLOQUEADA FOR UPDATE por el llamante.
create or replace function public._audit(
  p_game uuid, p_type text, p_actor_uid uuid, p_actor_player uuid,
  p_affected uuid[], p_before jsonb, p_after jsonb, p_reason text, p_automatic boolean
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_seq bigint;
begin
  update public.games set audit_seq = audit_seq + 1 where id = p_game returning audit_seq into v_seq;
  insert into public.audit_events(game_id, seq, type, actor_auth_uid, actor_player_id,
    affected_player_ids, before, after, reason, automatic)
  values (p_game, v_seq, p_type, p_actor_uid, p_actor_player,
          coalesce(p_affected,'{}'), p_before, p_after, p_reason, coalesce(p_automatic,false));
end $$;

-- Vista pública mínima de un jugador (sin uid).
create or replace function public._player_public(p public.players)
returns jsonb language sql immutable as $$
  select jsonb_build_object('public_ref', p.public_ref, 'name', p.display_name,
    'token_id', p.token_id, 'status', p.join_status, 'kicked', (p.kicked_at is not null))
$$;

-- ---------- peek_game ----------
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

-- ---------- create_game_tx (llamada por la Edge create_game con el JWT del usuario) ----------
create or replace function public.create_game_tx(
  p_name text, p_host_name text, p_host_token text, p_config jsonb,
  p_request_id uuid, p_pin_hash text, p_pin_salt text, p_algo text, p_iterations int
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); g public.games; hp public.players; v_code text; v_try int := 0; v_cfg jsonb;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Idempotencia por request_id.
  select * into g from public.games where create_request_id = p_request_id;
  if found then
    select * into hp from public.players where id = g.host_player_id;
    return jsonb_build_object('game_id',g.id,'code',g.code,'host_public_ref',hp.public_ref,'idempotent',true);
  end if;
  if char_length(btrim(p_name)) not between 3 and 40 then raise exception 'INVALID_GAME_NAME'; end if;
  if char_length(btrim(p_host_name)) not between 2 and 24 then raise exception 'INVALID_NAME'; end if;

  v_cfg := jsonb_build_object('initial_money',3000,'min_players',6,'max_players',16,'token_catalog_version',0)
           || coalesce(p_config,'{}'::jsonb);

  loop
    v_try := v_try + 1;
    v_code := (select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', (1+floor(random()*31))::int, 1), '')
               from generate_series(1,6));
    begin
      insert into public.games(code,name,config,create_request_id)
      values (v_code, btrim(p_name), v_cfg, p_request_id) returning * into g;
      exit;
    exception when unique_violation then
      if v_try > 12 then raise exception 'CODE_GENERATION_FAILED'; end if;
    end;
  end loop;

  perform 1 from public.games where id = g.id for update; -- bloqueo para auditoría
  insert into public.players(game_id, auth_uid, display_name, token_id, join_status)
  values (g.id, v_uid, btrim(p_host_name), p_host_token, 'joined') returning * into hp;
  update public.games set host_player_id = hp.id where id = g.id;
  insert into public.host_recovery(game_id, pin_hash, pin_salt, algo, iterations)
  values (g.id, p_pin_hash, p_pin_salt, p_algo, p_iterations);

  -- Validación final: el host pertenece a la partida y host_player_id no es null.
  if hp.game_id <> g.id then raise exception 'HOST_INTEGRITY'; end if;
  perform 1 from public.games where id=g.id and host_player_id is not null;
  if not found then raise exception 'HOST_NULL_AFTER_CREATE'; end if;

  perform public._audit(g.id,'game_created',v_uid,hp.id,array[hp.id],null,
    jsonb_build_object('name',g.name,'code',g.code),null,false);
  return jsonb_build_object('game_id',g.id,'code',g.code,'host_public_ref',hp.public_ref,'idempotent',false);
end $$;

-- ---------- join_game ----------
create or replace function public.join_game(p_code text, p_name text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); g public.games; p public.players; v_active int; v_max int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where code = upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  perform 1 from public.games where id=g.id for update;
  if g.status='cancelled' then raise exception 'GAME_CANCELLED'; end if;
  if g.status<>'lobby'   then raise exception 'GAME_NOT_JOINABLE'; end if;

  -- ¿Ya es jugador activo? -> idempotente.
  select * into p from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is null;
  if found then return public._player_public(p); end if;
  -- ¿Sesión expulsada? -> flujo independiente de reentrada.
  perform 1 from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is not null;
  if found then raise exception 'KICKED_NEEDS_REENTRY'; end if;

  v_max := coalesce((g.config->>'max_players')::int,16);
  select count(*) into v_active from public.players where game_id=g.id and kicked_at is null;
  if v_active >= v_max then raise exception 'GAME_FULL'; end if;
  if char_length(btrim(p_name)) not between 2 and 24 then raise exception 'INVALID_NAME'; end if;

  begin
    insert into public.players(game_id, auth_uid, display_name) values (g.id, v_uid, btrim(p_name)) returning * into p;
  exception when unique_violation then raise exception 'NAME_TAKEN'; end;
  perform public._audit(g.id,'player_joined',v_uid,p.id,array[p.id],null,jsonb_build_object('name',p.display_name),null,false);
  return public._player_public(p);
end $$;

-- ---------- helper: jugador activo del llamante (o error) ----------
create or replace function public._require_active_player(p_game uuid)
returns public.players language plpgsql security definer set search_path = public, pg_temp as $$
declare p public.players;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into p from public.players where game_id=p_game and auth_uid=auth.uid() and kicked_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  return p;
end $$;

-- ---------- helper: exigir host ----------
create or replace function public._require_host(p_game uuid)
returns public.games language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where id=p_game for update;
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  perform 1 from public.players where id=g.host_player_id and auth_uid=auth.uid() and kicked_at is null;
  if not found then raise exception 'NOT_HOST'; end if;
  return g;
end $$;

-- ---------- rename_player ----------
create or replace function public.rename_player(p_game uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; p public.players;
begin
  select * into g from public.games where id=p_game for update;
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  p := public._require_active_player(p_game);
  if char_length(btrim(p_name)) not between 2 and 24 then raise exception 'INVALID_NAME'; end if;
  begin
    update public.players set display_name=btrim(p_name), row_version=row_version+1 where id=p.id returning * into p;
  exception when unique_violation then raise exception 'NAME_TAKEN'; end;
  perform public._audit(g.id,'name_changed',auth.uid(),p.id,array[p.id],null,jsonb_build_object('name',p.display_name),null,false);
  return public._player_public(p);
end $$;

-- ---------- choose_token ----------
create or replace function public.choose_token(p_game uuid, p_token text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; p public.players;
begin
  select * into g from public.games where id=p_game for update;
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  p := public._require_active_player(p_game);
  if p.token_id is not distinct from p_token then return public._player_public(p); end if; -- idempotente
  perform 1 from public.token_catalog where id=p_token and active
    and catalog_version=coalesce((g.config->>'token_catalog_version')::int,0);
  if not found then raise exception 'TOKEN_INVALID'; end if;
  begin
    update public.players set token_id=p_token, row_version=row_version+1 where id=p.id returning * into p;
  exception when unique_violation then raise exception 'TOKEN_TAKEN'; end;
  perform public._audit(g.id,'token_chosen',auth.uid(),p.id,array[p.id],null,jsonb_build_object('token',p_token),null,false);
  return public._player_public(p);
end $$;

-- ---------- set_ready ----------
create or replace function public.set_ready(p_game uuid, p_ready boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; p public.players;
begin
  select * into g from public.games where id=p_game for update;
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  p := public._require_active_player(p_game);
  if p_ready and (p.token_id is null or char_length(btrim(p.display_name))<2) then raise exception 'INCOMPLETE_PLAYER'; end if;
  update public.players set join_status=(case when p_ready then 'ready' else 'joined' end)::player_join_status,
    row_version=row_version+1 where id=p.id returning * into p;
  perform public._audit(g.id,'ready_changed',auth.uid(),p.id,array[p.id],null,jsonb_build_object('ready',p_ready),null,false);
  return public._player_public(p);
end $$;

-- ---------- kick_player ----------
create or replace function public.kick_player(p_game uuid, p_target_ref text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; t public.players;
begin
  g := public._require_host(p_game);
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  select * into t from public.players where game_id=p_game and public_ref=p_target_ref and kicked_at is null;
  if not found then raise exception 'TARGET_NOT_FOUND'; end if;
  if t.id = g.host_player_id then raise exception 'CANNOT_KICK_HOST'; end if;
  update public.players set kicked_at=now(), join_status='joined', row_version=row_version+1 where id=t.id; -- conserva auth_uid
  -- cancela solicitudes pendientes del expulsado
  update public.player_recovery_requests set status='cancelled', resolved_at=now() where player_id=t.id and status='pending';
  perform public._audit(g.id,'player_kicked',auth.uid(),t.id,array[t.id],
    jsonb_build_object('was_active',true),jsonb_build_object('kicked',true),null,false);
  return jsonb_build_object('kicked', t.public_ref);
end $$;

-- ---------- update_config ----------
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
    || (case when p_patch ? 'initial_money' then jsonb_build_object('initial_money',(p_patch->>'initial_money')::int) else '{}'::jsonb end)
    || (case when p_patch ? 'min_players'   then jsonb_build_object('min_players',(p_patch->>'min_players')::int)   else '{}'::jsonb end)
    || (case when p_patch ? 'max_players'   then jsonb_build_object('max_players',(p_patch->>'max_players')::int)   else '{}'::jsonb end);
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

-- ---------- cancel_game ----------
create or replace function public.cancel_game(p_game uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games;
begin
  g := public._require_host(p_game);
  if g.status='cancelled' then return jsonb_build_object('status','cancelled'); end if; -- idempotente
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  update public.games set status='cancelled', cancelled_at=now() where id=g.id;
  perform public._audit(g.id,'game_cancelled',auth.uid(),null,null,null,null,null,false);
  return jsonb_build_object('status','cancelled');
end $$;

-- ---------- start_game (RNG seguro, una sola vez, idempotente) ----------
create or replace function public.start_game(p_game uuid, p_expected_version int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; v_active int; v_min int; v_incomplete int; v_pending int; v_order uuid[];
begin
  g := public._require_host(p_game);
  if g.status='active' then return jsonb_build_object('status','active','turn_order',to_jsonb(g.turn_order),'idempotent',true); end if;
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  if g.version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;

  v_min := coalesce((g.config->>'min_players')::int,6);
  select count(*) into v_active from public.players where game_id=g.id and kicked_at is null;
  if v_active < v_min then raise exception 'NOT_ENOUGH_PLAYERS'; end if;
  select count(*) into v_incomplete from public.players
    where game_id=g.id and kicked_at is null and (token_id is null or join_status<>'ready' or char_length(btrim(display_name))<2);
  if v_incomplete > 0 then raise exception 'PLAYERS_INCOMPLETE'; end if;
  select count(*) into v_pending from public.player_recovery_requests r
    join public.players p on p.id=r.player_id and p.kicked_at is null
    where r.game_id=g.id and r.status='pending';
  if v_pending > 0 then raise exception 'PENDING_RECOVERIES'; end if;

  -- Orden criptográfico (gen_random_uuid) UNA sola vez; se almacena.
  select array_agg(id order by gen_random_uuid()) into v_order
  from public.players where game_id=g.id and kicked_at is null;

  update public.games set status='active', started_at=now(), turn_order=v_order, version=version+1 where id=g.id returning * into g;
  perform public._audit(g.id,'game_started',auth.uid(),null,v_order,null,jsonb_build_object('turn_order',to_jsonb(v_order)),null,false);
  return jsonb_build_object('status','active','turn_order',to_jsonb(g.turn_order),'idempotent',false);
end $$;

-- ---------- request_recovery ----------
create or replace function public.request_recovery(p_code text, p_player_ref text, p_device text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); g public.games; t public.players; r public.player_recovery_requests;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where code=upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  perform 1 from public.games where id=g.id for update;
  select * into t from public.players where game_id=g.id and public_ref=p_player_ref and kicked_at is null;
  if not found then raise exception 'TARGET_NOT_FOUND'; end if;
  -- Si esta sesión está expulsada en la partida -> usar reentrada, no recuperación.
  perform 1 from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is not null;
  if found then raise exception 'KICKED_USE_REENTRY'; end if;
  -- Si esta sesión ya controla un jugador activo -> conflicto.
  perform 1 from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is null;
  if found then raise exception 'SESSION_HAS_ACTIVE_PLAYER'; end if;
  -- Solicitud pendiente existente -> idempotente.
  select * into r from public.player_recovery_requests where player_id=t.id and status='pending';
  if found then return jsonb_build_object('request_ref',r.public_ref,'status',r.status); end if;
  insert into public.player_recovery_requests(game_id,player_id,device_label) values (g.id,t.id,p_device) returning * into r;
  insert into public.request_secrets(request_id,requester_auth_uid) values (r.id,v_uid);
  perform public._audit(g.id,'recovery_requested',v_uid,t.id,array[t.id],null,jsonb_build_object('request',r.public_ref),null,false);
  return jsonb_build_object('request_ref',r.public_ref,'status',r.status);
end $$;

-- ---------- resolve_recovery (host) ----------
create or replace function public.resolve_recovery(p_request_ref text, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.player_recovery_requests; g public.games; t public.players; v_new uuid; v_old uuid;
begin
  select * into r from public.player_recovery_requests where public_ref=p_request_ref for update;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(r.game_id);
  if r.status<>'pending' then return jsonb_build_object('status',r.status,'idempotent',true); end if;
  select * into t from public.players where id=r.player_id for update;
  if not p_accept then
    update public.player_recovery_requests set status='rejected', resolved_at=now() where id=r.id;
    perform public._audit(g.id,'recovery_rejected',auth.uid(),t.id,array[t.id],null,jsonb_build_object('request',r.public_ref),null,false);
    return jsonb_build_object('status','rejected');
  end if;
  if t.kicked_at is not null then raise exception 'TARGET_NOT_ACTIVE'; end if;
  select requester_auth_uid into v_new from public.request_secrets where request_id=r.id;
  -- Conflicto: la sesión no puede controlar ya otro jugador activo.
  perform 1 from public.players where game_id=g.id and auth_uid=v_new and kicked_at is null and id<>t.id;
  if found then raise exception 'SESSION_HAS_ACTIVE_PLAYER'; end if;
  v_old := t.auth_uid;
  update public.players set auth_uid=v_new, row_version=row_version+1 where id=t.id;
  update public.player_recovery_requests set status='approved', resolved_at=now() where id=r.id;
  update public.player_recovery_requests set status='cancelled', resolved_at=now() where player_id=t.id and status='pending' and id<>r.id;
  -- auditoría server-only del uid anterior y nuevo (audit_events no es legible por clientes).
  perform public._audit(g.id,'recovery_accepted',auth.uid(),t.id,array[t.id],
    jsonb_build_object('prev_uid',v_old),jsonb_build_object('new_uid',v_new),null,false);
  return jsonb_build_object('status','approved');
end $$;

-- ---------- request_reentry (sesión expulsada) ----------
create or replace function public.request_reentry(p_code text, p_name text, p_device text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); g public.games; prior public.players; r public.player_reentry_requests; v_active int; v_max int; v_exists int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where code=upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  perform 1 from public.games where id=g.id for update;
  if g.status<>'lobby' then raise exception 'GAME_NOT_JOINABLE'; end if;
  -- Detección: esta sesión DEBE estar expulsada en la partida.
  select * into prior from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is not null order by kicked_at desc limit 1;
  if not found then raise exception 'NOT_KICKED'; end if;
  -- No puede controlar ya un jugador activo.
  perform 1 from public.players where game_id=g.id and auth_uid=v_uid and kicked_at is null;
  if found then raise exception 'SESSION_HAS_ACTIVE_PLAYER'; end if;
  if char_length(btrim(p_name)) not between 2 and 24 then raise exception 'INVALID_NAME'; end if;
  -- Solicitud pendiente existente (misma sesión) -> idempotente.
  select count(*) into v_exists from public.player_reentry_requests rr
    join public.request_secrets s on s.request_id=rr.id
    where rr.game_id=g.id and rr.status='pending' and s.requester_auth_uid=v_uid;
  if v_exists>0 then
    select * into r from public.player_reentry_requests rr
      join public.request_secrets s on s.request_id=rr.id
      where rr.game_id=g.id and rr.status='pending' and s.requester_auth_uid=v_uid limit 1;
    return jsonb_build_object('request_ref',r.public_ref,'status',r.status);
  end if;
  insert into public.player_reentry_requests(game_id,prior_player_id,desired_name,device_label)
  values (g.id,prior.id,btrim(p_name),p_device) returning * into r;
  insert into public.request_secrets(request_id,requester_auth_uid) values (r.id,v_uid);
  perform public._audit(g.id,'reentry_requested',v_uid,prior.id,array[prior.id],null,jsonb_build_object('request',r.public_ref),null,false);
  return jsonb_build_object('request_ref',r.public_ref,'status',r.status);
end $$;

-- ---------- resolve_reentry (host) ----------
create or replace function public.resolve_reentry(p_request_ref text, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.player_reentry_requests; g public.games; v_new uuid; v_active int; v_max int; np public.players;
begin
  select * into r from public.player_reentry_requests where public_ref=p_request_ref for update;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(r.game_id);
  if r.status<>'pending' then return jsonb_build_object('status',r.status,'idempotent',true); end if;
  if not p_accept then
    update public.player_reentry_requests set status='rejected', resolved_at=now() where id=r.id;
    perform public._audit(g.id,'reentry_rejected',auth.uid(),r.prior_player_id,array[r.prior_player_id],null,jsonb_build_object('request',r.public_ref),null,false);
    return jsonb_build_object('status','rejected');
  end if;
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  select requester_auth_uid into v_new from public.request_secrets where request_id=r.id;
  v_max := coalesce((g.config->>'max_players')::int,16);
  select count(*) into v_active from public.players where game_id=g.id and kicked_at is null;
  if v_active >= v_max then raise exception 'GAME_FULL'; end if;
  -- Conflicto: la sesión no debe controlar ya un jugador activo.
  perform 1 from public.players where game_id=g.id and auth_uid=v_new and kicked_at is null;
  if found then raise exception 'SESSION_HAS_ACTIVE_PLAYER'; end if;
  -- Crea fila NUEVA (nunca reactiva la histórica). Nombre debe estar libre.
  begin
    insert into public.players(game_id,auth_uid,display_name) values (g.id,v_new,r.desired_name) returning * into np;
  exception when unique_violation then raise exception 'NAME_TAKEN'; end;
  update public.player_reentry_requests set status='approved', resolved_at=now(), new_player_id=np.id where id=r.id;
  perform public._audit(g.id,'reentry_accepted',auth.uid(),np.id,array[r.prior_player_id,np.id],
    jsonb_build_object('prior',r.prior_player_id),jsonb_build_object('new_player',np.id),null,false);
  return jsonb_build_object('status','approved','new_public_ref',np.public_ref);
end $$;

-- ---------- get_request_status (polling del solicitante; sin uid) ----------
create or replace function public.get_request_status(p_request_ref text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v text; v_kind text;
begin
  select status::text into v from public.player_recovery_requests where public_ref=p_request_ref;
  if found then return jsonb_build_object('kind','recovery','status',v); end if;
  select status::text into v from public.player_reentry_requests where public_ref=p_request_ref;
  if found then return jsonb_build_object('kind','reentry','status',v); end if;
  raise exception 'REQUEST_NOT_FOUND' using errcode='P0002';
end $$;

-- ---------- my_status ----------
create or replace function public.my_status(p_game uuid)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if exists(select 1 from public.players where game_id=p_game and auth_uid=auth.uid() and kicked_at is null) then return 'active'; end if;
  if exists(select 1 from public.players where game_id=p_game and auth_uid=auth.uid() and kicked_at is not null) then return 'kicked'; end if;
  return 'not_member';
end $$;

-- ---------- heartbeat ----------
create or replace function public.heartbeat(p_game uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.players set last_seen_at=now() where game_id=p_game and auth_uid=auth.uid() and kicked_at is null;
end $$;

-- ---------- Grants: revocar público, conceder función a función a authenticated ----------
revoke execute on all functions in schema public from public;
-- is_game_member lo invocan las POLÍTICAS RLS como el rol del usuario: requiere EXECUTE.
grant execute on function public.is_game_member(uuid) to authenticated;
do $$ declare f text; begin
  for f in select unnest(array[
    'peek_game(text)','create_game_tx(text,text,text,jsonb,uuid,text,text,text,integer)',
    'join_game(text,text,uuid)','rename_player(uuid,text)','choose_token(uuid,text)','set_ready(uuid,boolean)',
    'kick_player(uuid,text)','update_config(uuid,jsonb,integer)','cancel_game(uuid)','start_game(uuid,integer)',
    'request_recovery(text,text,text)','resolve_recovery(text,boolean)','request_reentry(text,text,text)',
    'resolve_reentry(text,boolean)','get_request_status(text)','my_status(uuid)','heartbeat(uuid)'])
  loop execute format('grant execute on function public.%s to authenticated;', f); end loop;
end $$;
