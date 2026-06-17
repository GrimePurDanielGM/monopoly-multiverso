-- Fase 1 — Endurecimiento autoritativo de create_game_tx: el host_token es OBLIGATORIO,
-- no nulo, no vacío, existente, ACTIVO y de la catalog_version vigente. Además, el cliente
-- NO puede inyectar una token_catalog_version arbitraria: se FUERZA en servidor a la vigente (0).
-- ADITIVA: redefine la función (no edita migraciones aplicadas). Conserva EXACTAMENTE firma,
-- permisos, SECURITY DEFINER, search_path, idempotencia, creación atómica, auditoría y el resto
-- del comportamiento. No cambia fichas históricas ni desactiva/borra filas.

create or replace function public.create_game_tx(
  p_name text, p_host_name text, p_host_token text, p_config jsonb,
  p_request_id uuid, p_pin_hash text, p_pin_salt text, p_algo text, p_iterations int
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); g public.games; hp public.players; v_code text; v_try int := 0; v_cfg jsonb;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Idempotencia por request_id (sin re-validar: el reintento devuelve la partida ya creada).
  select * into g from public.games where create_request_id = p_request_id;
  if found then
    select * into hp from public.players where id = g.host_player_id;
    return jsonb_build_object('game_id',g.id,'code',g.code,'host_public_ref',hp.public_ref,'idempotent',true);
  end if;
  if char_length(btrim(p_name)) not between 3 and 40 then raise exception 'INVALID_GAME_NAME'; end if;
  if char_length(btrim(p_host_name)) not between 2 and 24 then raise exception 'INVALID_NAME'; end if;

  v_cfg := jsonb_build_object('initial_money',3000,'min_players',6,'max_players',16,'token_catalog_version',0)
           || coalesce(p_config,'{}'::jsonb);
  -- NUEVO: la versión de catálogo la fija el servidor (vigente = 0); se ignora el valor del cliente.
  v_cfg := v_cfg || jsonb_build_object('token_catalog_version', 0);

  -- NUEVO: el host_token es OBLIGATORIO y debe ser una ficha ACTIVA de la versión vigente.
  if p_host_token is null or btrim(p_host_token) = '' then
    raise exception 'TOKEN_REQUIRED';
  end if;
  perform 1 from public.token_catalog
   where id = p_host_token
     and active = true
     and catalog_version = coalesce((v_cfg->>'token_catalog_version')::int, 0);
  if not found then
    raise exception 'TOKEN_INVALID';
  end if;

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

  if hp.game_id <> g.id then raise exception 'HOST_INTEGRITY'; end if;
  perform 1 from public.games where id=g.id and host_player_id is not null;
  if not found then raise exception 'HOST_NULL_AFTER_CREATE'; end if;

  perform public._audit(g.id,'game_created',v_uid,hp.id,array[hp.id],null,
    jsonb_build_object('name',g.name,'code',g.code),null,false);
  return jsonb_build_object('game_id',g.id,'code',g.code,'host_public_ref',hp.public_ref,'idempotent',false);
end $$;
