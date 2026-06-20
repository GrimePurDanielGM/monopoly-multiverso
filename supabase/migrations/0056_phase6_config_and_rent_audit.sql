-- Fase 6 (pulido) — Config del lobby: stock inicial de casas/hoteles (mín 32/12) y "construir sin grupo
-- completo". start_game aplica el stock configurado. pay_rent añade auditoría rent_calculated con desglose.
-- Helpers de elegibilidad/uniformidad que respetan allow_build_without_monopoly (los usan las RPCs de 0057).

-- ── update_config: acepta initial_houses_available (≥32), initial_hotels_available (≥12) y
--    allow_build_without_monopoly (bool), además de la config existente. Solo lobby. ──
create or replace function public.update_config(p_game uuid, p_patch jsonb, p_expected_version int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; v_cfg jsonb; v_active_tokens int; v_max int; v_min int;
begin
  g := public._require_host(p_game);
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  if g.version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if p_patch ? 'dice_mode' and (p_patch->>'dice_mode') not in ('virtual_only','physical_allowed','physical_only') then raise exception 'INVALID_DICE_MODE'; end if;
  if p_patch ? 'initial_houses_available' and (p_patch->>'initial_houses_available')::int < 32 then raise exception 'INVALID_BUILDING_STOCK'; end if;
  if p_patch ? 'initial_hotels_available' and (p_patch->>'initial_hotels_available')::int < 12 then raise exception 'INVALID_BUILDING_STOCK'; end if;
  v_cfg := g.config;
  if p_patch ? 'name' then
    if char_length(btrim(p_patch->>'name')) not between 3 and 40 then raise exception 'INVALID_GAME_NAME'; end if;
    update public.games set name=btrim(p_patch->>'name') where id=g.id;
  end if;
  v_cfg := v_cfg
    || (case when p_patch ? 'initial_money'   then jsonb_build_object('initial_money',(p_patch->>'initial_money')::int) else '{}'::jsonb end)
    || (case when p_patch ? 'min_players'     then jsonb_build_object('min_players',(p_patch->>'min_players')::int)   else '{}'::jsonb end)
    || (case when p_patch ? 'max_players'     then jsonb_build_object('max_players',(p_patch->>'max_players')::int)   else '{}'::jsonb end)
    || (case when p_patch ? 'allow_late_join' then jsonb_build_object('allow_late_join',(p_patch->>'allow_late_join')::boolean) else '{}'::jsonb end)
    || (case when p_patch ? 'dice_mode'       then jsonb_build_object('dice_mode',(p_patch->>'dice_mode')) else '{}'::jsonb end)
    || (case when p_patch ? 'initial_houses_available' then jsonb_build_object('initial_houses_available',greatest(32,(p_patch->>'initial_houses_available')::int)) else '{}'::jsonb end)
    || (case when p_patch ? 'initial_hotels_available' then jsonb_build_object('initial_hotels_available',greatest(12,(p_patch->>'initial_hotels_available')::int)) else '{}'::jsonb end)
    || (case when p_patch ? 'allow_build_without_monopoly' then jsonb_build_object('allow_build_without_monopoly',(p_patch->>'allow_build_without_monopoly')::boolean) else '{}'::jsonb end);
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

-- ── start_game: igual que 0025, pero fija el stock de construcciones desde la config (mín 32/12). ──
create or replace function public.start_game(p_game uuid, p_expected_version int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; v_active int; v_min int; v_incomplete int; v_pending int; v_order uuid[]; v_init int;
begin
  g := public._require_host(p_game);
  if g.status = 'active' then return jsonb_build_object('status','active','turn_order',to_jsonb(g.turn_order),'idempotent',true); end if;
  if g.status <> 'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  if g.version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;

  v_min := coalesce((g.config->>'min_players')::int, 6);
  select count(*) into v_active from public.players where game_id = g.id and kicked_at is null;
  if v_active < v_min then raise exception 'NOT_ENOUGH_PLAYERS'; end if;
  select count(*) into v_incomplete from public.players
    where game_id = g.id and kicked_at is null and (token_id is null or join_status <> 'ready' or char_length(btrim(display_name)) < 2);
  if v_incomplete > 0 then raise exception 'PLAYERS_INCOMPLETE'; end if;
  select count(*) into v_pending from public.player_recovery_requests r
    join public.players p on p.id = r.player_id and p.kicked_at is null
    where r.game_id = g.id and r.status = 'pending';
  if v_pending > 0 then raise exception 'PENDING_RECOVERIES'; end if;

  select array_agg(id order by gen_random_uuid()) into v_order
  from public.players where game_id = g.id and kicked_at is null;

  update public.games set status = 'active', started_at = now(), turn_order = v_order, version = version + 1
    where id = g.id returning * into g;

  insert into public.game_runtime(game_id, turn_order_refs, turn_index, turn_number, ledger_seq, runtime_version)
  select g.id, array_agg(p.public_ref order by o.ord), 1, 1, 0, 0
  from unnest(v_order) with ordinality as o(pid, ord)
  join public.players p on p.id = o.pid;
  -- Fase 6: stock de construcciones desde la config (mínimos 32/12).
  update public.game_runtime set
    houses_available = greatest(32, coalesce((g.config->>'initial_houses_available')::int, 32)),
    hotels_available = greatest(12, coalesce((g.config->>'initial_hotels_available')::int, 12))
    where game_id = g.id;

  v_init := coalesce((g.config->>'initial_money')::int, 3000);
  insert into public.player_balances(game_id, player_ref, balance)
    select g.id, p.public_ref, v_init from public.players p where p.game_id = g.id and p.kicked_at is null;

  if v_init > 0 then
    with seeded as (
      select p.public_ref, row_number() over (order by array_position(v_order, p.id)) as rn
      from public.players p where p.game_id = g.id and p.kicked_at is null)
    insert into public.ledger(ledger_ref, game_id, seq, kind, from_ref, to_ref, amount, request_id)
      select public.gen_ledger_ref(g.id), g.id, rn, 'seed', null, public_ref, v_init, null from seeded;
    update public.game_runtime set ledger_seq = v_active where game_id = g.id;
  end if;

  insert into public.player_positions(game_id, player_ref, board_key, space_index)
    select g.id, p.public_ref, public._p4_initial_board(), 0
    from public.players p where p.game_id = g.id and p.kicked_at is null;

  perform public._audit(g.id, 'game_started', auth.uid(), null, v_order, null,
            jsonb_build_object('turn_order', to_jsonb(v_order)), null, false);
  return jsonb_build_object('status','active','turn_order',to_jsonb(g.turn_order),'idempotent',false);
end $$;

-- ── ¿permite la partida construir sin monopolio? ──
create or replace function public._p6_allow_no_monopoly(p_game uuid) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce((select (config->>'allow_build_without_monopoly')::boolean from public.games where id=p_game), false);
$$;
-- ¿es elegible el grupo para construir? monopolio, o (si la config lo permite) basta con poseer la propiedad.
create or replace function public._p6_build_eligible(p_game uuid, p_prop text) returns boolean language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_owner text; c public.property_catalog; begin
  select * into c from public.property_catalog where property_ref=p_prop and active;
  if not found or c.kind<>'street' then return false; end if;
  select owner_ref into v_owner from public.property_ownership where game_id=p_game and property_ref=p_prop and released_at is null;
  if v_owner is null then return false; end if;
  if public._p6_is_monopoly(p_game, p_prop) then return true; end if;
  return public._p6_allow_no_monopoly(p_game);
end $$;
-- nivel mín/máx considerando SOLO las calles del grupo que posee p_owner (para uniformidad sin grupo completo).
create or replace function public._p6_owned_group_min(p_game uuid, p_owner text, p_board text, p_group text) returns int
  language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(min(case when s.has_hotel then 5 else coalesce(s.houses,0) end), 0)
  from public.property_catalog c
  join public.property_ownership o on o.property_ref=c.property_ref and o.game_id=p_game and o.owner_ref=p_owner and o.released_at is null
  left join public.game_property_state s on s.game_id=p_game and s.property_ref=c.property_ref
  where c.board_key=p_board and c.group_key=p_group and c.kind='street' and c.active;
$$;
create or replace function public._p6_owned_group_max(p_game uuid, p_owner text, p_board text, p_group text) returns int
  language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(max(case when s.has_hotel then 5 else coalesce(s.houses,0) end), 0)
  from public.property_catalog c
  join public.property_ownership o on o.property_ref=c.property_ref and o.game_id=p_game and o.owner_ref=p_owner and o.released_at is null
  left join public.game_property_state s on s.game_id=p_game and s.property_ref=c.property_ref
  where c.board_key=p_board and c.group_key=p_group and c.kind='street' and c.active;
$$;
-- ¿el resto de calles del grupo que posee p_owner (≠ p_prop) están a 4 casas/hotel? (hotel sin grupo completo)
create or replace function public._p6_owned_rest_max(p_game uuid, p_owner text, p_board text, p_group text, p_prop text) returns boolean
  language sql stable security definer set search_path=public,pg_temp as $$
  select not exists(select 1 from public.property_catalog c
    join public.property_ownership o on o.property_ref=c.property_ref and o.game_id=p_game and o.owner_ref=p_owner and o.released_at is null
    left join public.game_property_state s on s.game_id=p_game and s.property_ref=c.property_ref
    where c.board_key=p_board and c.group_key=p_group and c.kind='street' and c.active and c.property_ref<>p_prop
      and not (coalesce(s.has_hotel,false) or coalesce(s.houses,0)=4));
$$;
revoke all on function public._p6_allow_no_monopoly(uuid) from public, anon, authenticated;
revoke all on function public._p6_build_eligible(uuid,text) from public, anon, authenticated;
revoke all on function public._p6_owned_group_min(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public._p6_owned_group_max(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public._p6_owned_rest_max(uuid,text,text,text,text) from public, anon, authenticated;
