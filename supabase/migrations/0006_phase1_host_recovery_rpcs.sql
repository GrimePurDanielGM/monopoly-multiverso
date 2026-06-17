-- Fase 1 — RPC de recuperación de host. SOLO service_role (las invoca la Edge
-- recover_host tras verificar el PIN con el pepper). El PIN/pepper NUNCA tocan la BD.

create or replace function public.host_recovery_success(p_code text, p_new_uid uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; hp public.players; v_old uuid;
begin
  select * into g from public.games where code=upper(btrim(p_code)) for update;
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  select * into hp from public.players where id=g.host_player_id for update;
  if hp.id is null then raise exception 'HOST_MISSING'; end if;
  -- Conflicto: el nuevo uid no puede controlar ya otro jugador activo de la partida.
  perform 1 from public.players where game_id=g.id and auth_uid=p_new_uid and kicked_at is null and id<>hp.id;
  if found then raise exception 'SESSION_HAS_ACTIVE_PLAYER'; end if;
  v_old := hp.auth_uid;
  update public.players set auth_uid=p_new_uid, row_version=row_version+1 where id=hp.id;
  update public.host_recovery set failed_attempts=0, locked_until=null, updated_at=now() where game_id=g.id;
  perform public._audit(g.id,'host_recovered',null,hp.id,array[hp.id],
    jsonb_build_object('prev_uid',v_old),jsonb_build_object('new_uid',p_new_uid),null,false);
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.host_recovery_fail(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; hr public.host_recovery;
begin
  select * into g from public.games where code=upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;
  select * into hr from public.host_recovery where game_id=g.id for update;
  update public.host_recovery set failed_attempts=failed_attempts+1,
    locked_until = case when failed_attempts+1 >= 5 then now() + interval '15 minutes' else locked_until end,
    updated_at=now()
  where game_id=g.id returning * into hr;
  perform public._audit(g.id,'host_recovery_failed',null,null,null,null,
    jsonb_build_object('failed_attempts',hr.failed_attempts,'locked_until',hr.locked_until),null,false);
  return jsonb_build_object('failed_attempts',hr.failed_attempts,'locked_until',hr.locked_until);
end $$;

-- Solo service_role (Edge). Nunca público ni authenticated.
revoke execute on function public.host_recovery_success(text,uuid) from public;
revoke execute on function public.host_recovery_fail(text)        from public;
grant  execute on function public.host_recovery_success(text,uuid) to service_role;
grant  execute on function public.host_recovery_fail(text)        to service_role;
