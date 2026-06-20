-- Fase 5 (corrección ampliada) — Dados físicos/virtuales configurables por el anfitrión.
-- · games.config.dice_mode: 'virtual_only' (def) | 'physical_allowed' | 'physical_only'.
-- · set_dice_mode: el anfitrión lo cambia en lobby o en partida activa (no finalizada); auditado.
-- · _p5_roll_resolve: núcleo compartido (intento de cárcel / movimiento) a partir de unos dados ya dados.
-- · roll_and_move (virtual) se bloquea si el modo es physical_only; move_with_physical_roll usa dados dados.

-- ── Cambiar el modo de dados (anfitrión; lobby o activa; auditado dice_mode_changed) ──
create or replace function public.set_dice_mode(p_game uuid, p_mode text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_status text; v_ver bigint; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if p_mode not in ('virtual_only','physical_allowed','physical_only') then raise exception 'INVALID_DICE_MODE'; end if;
  select status into v_status from public.games where id = p_game;
  if not found then raise exception 'GAME_NOT_FOUND' using errcode='P0002'; end if;

  if v_status = 'active' then
    rt := public._p2_lock(p_game);
    if rt.runtime_status = 'finished' then raise exception 'GAME_FINISHED'; end if;
    v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
    g := public._require_host(p_game);
    if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
    update public.games set config = jsonb_set(config, '{dice_mode}', to_jsonb(p_mode)) where id = p_game;
    v_ver := public._p2_bump(p_game);
    perform public._audit(p_game, 'dice_mode_changed', auth.uid(), g.host_player_id, null, null, jsonb_build_object('dice_mode', p_mode), null, false);
    perform public._emit_active_signal(p_game);
    v_res := jsonb_build_object('dice_mode', p_mode, 'runtime_version', v_ver);
    perform public._p2_save(p_game, p_request_id, 'set_dice_mode', v_res);
    return v_res;
  elsif v_status = 'lobby' then
    g := public._require_host(p_game);
    if g.version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
    update public.games set config = jsonb_set(config, '{dice_mode}', to_jsonb(p_mode)), version = version + 1 where id = p_game returning version into v_ver;
    perform public._audit(p_game, 'dice_mode_changed', auth.uid(), g.host_player_id, null, null, jsonb_build_object('dice_mode', p_mode), null, false);
    return jsonb_build_object('dice_mode', p_mode, 'version', v_ver);
  else
    raise exception 'GAME_FINISHED';
  end if;
end $$;
grant execute on function public.set_dice_mode(uuid, text, uuid, bigint) to authenticated;

-- ── Núcleo compartido: resuelve una tirada (dados ya determinados) como intento de cárcel o movimiento. ──
-- Asume que el llamador ya hizo lock/idem/permiso/version-check. Hace bump+emit+save y devuelve el resultado.
create or replace function public._p5_roll_resolve(p_game uuid, p_me public.players, d1 int, d2 int, p_request_id uuid, p_op text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_move jsonb; v_res jsonb; v_jail_board text; v_turns int; v_action_turn int; v_bal bigint; v_ver bigint;
        v_jailed boolean; v_turn_number int;
begin
  select turn_number into v_turn_number from public.game_runtime where game_id = p_game;
  select board_key, jail_turns, action_turn into v_jail_board, v_turns, v_action_turn
    from public.game_jail where game_id=p_game and player_ref=p_me.public_ref;
  v_jailed := found;
  if v_jailed and v_action_turn = v_turn_number then raise exception 'JAIL_ACTION_ALREADY_TAKEN'; end if;

  if v_jailed then
    if d1 = d2 then
      update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', p_me.public_ref, 'jail', 'doubles') where game_id = p_game;
      delete from public.game_jail where game_id=p_game and player_ref=p_me.public_ref;
      perform public._audit(p_game, 'jail_released_by_doubles', auth.uid(), p_me.id, array[p_me.id], null, jsonb_build_object('d1', d1, 'd2', d2), null, false);
      v_move := public._p4_apply_move(p_game, p_me, d1 + d2, p_request_id, 'roll');
      perform public._emit_active_signal(p_game);
      v_res := v_move || jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'jail_result', 'doubles');
    else
      v_turns := v_turns + 1;
      if v_turns >= 3 then
        select balance into v_bal from public.player_balances where game_id=p_game and player_ref=p_me.public_ref for update;
        if v_bal >= 50 then
          update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', p_me.public_ref, 'jail', 'forced_paid') where game_id = p_game;
          perform public._p2_move(p_game, p_me.public_ref, null, 50);
          perform public._p2_post(p_game, 'jail_release_payment', p_me.public_ref, null, 50, null, null, null, p_me.public_ref, null, gen_random_uuid());
          perform public._p5_pot_add(p_game, 50);
          delete from public.game_jail where game_id=p_game and player_ref=p_me.public_ref;
          perform public._audit(p_game, 'jail_forced_release_after_3_turns', auth.uid(), p_me.id, array[p_me.id], null, jsonb_build_object('amount', 50, 'd1', d1, 'd2', d2), null, false);
          v_move := public._p4_apply_move(p_game, p_me, d1 + d2, p_request_id, 'roll');
          perform public._emit_active_signal(p_game);
          v_res := v_move || jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'jail_result', 'forced_paid');
        else
          update public.game_jail set jail_turns = v_turns, action_turn = v_turn_number where game_id=p_game and player_ref=p_me.public_ref;
          update public.game_runtime set
            last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', p_me.public_ref, 'jail', 'forced_pending'),
            pending_payment = jsonb_build_object('kind', 'jail_forced', 'player_ref', p_me.public_ref, 'amount', 50,
              'board', v_jail_board, 'space_index', 10, 'space_name', 'Cárcel') where game_id = p_game;
          v_ver := public._p2_bump(p_game);
          perform public._audit(p_game, 'jail_forced_payment_pending', auth.uid(), p_me.id, array[p_me.id], null, jsonb_build_object('amount', 50), null, false);
          perform public._emit_active_signal(p_game);
          v_res := jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'jail_result', 'forced_pending', 'runtime_version', v_ver);
        end if;
      else
        update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', p_me.public_ref, 'jail', 'failed') where game_id = p_game;
        update public.game_jail set jail_turns = v_turns, action_turn = v_turn_number where game_id=p_game and player_ref=p_me.public_ref;
        v_ver := public._p2_bump(p_game);
        perform public._audit(p_game, 'jail_attempt_failed', auth.uid(), p_me.id, array[p_me.id], null, jsonb_build_object('jail_turns', v_turns, 'd1', d1, 'd2', d2), null, false);
        perform public._emit_active_signal(p_game);
        v_res := jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'jail_result', 'failed', 'jail_turns', v_turns, 'runtime_version', v_ver);
      end if;
    end if;
    perform public._p2_save(p_game, p_request_id, p_op, v_res);
    return v_res;
  end if;

  -- Movimiento normal.
  update public.game_runtime set last_roll = jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2, 'player_ref', p_me.public_ref)
    where game_id = p_game;
  v_move := public._p4_apply_move(p_game, p_me, d1 + d2, p_request_id, 'roll');
  perform public._audit(p_game, 'player_rolled', auth.uid(), p_me.id, array[p_me.id], null,
            jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2), null, false);
  perform public._emit_active_signal(p_game);
  v_res := v_move || jsonb_build_object('d1', d1, 'd2', d2, 'total', d1 + d2);
  perform public._p2_save(p_game, p_request_id, p_op, v_res);
  return v_res;
end $$;
revoke all on function public._p5_roll_resolve(uuid, public.players, int, int, uuid, text) from public, anon, authenticated;

-- ── roll_and_move (dados VIRTUALES): bloqueado si el modo es physical_only ──
create or replace function public.roll_and_move(p_game uuid, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; me public.players; v_idem jsonb; v_cur text; d1 int; d2 int;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.pending_junction is not null then raise exception 'JUNCTION_PENDING'; end if;
  if rt.pending_card is not null then raise exception 'CARD_PENDING'; end if;
  if rt.pending_payment is not null then raise exception 'PAYMENT_PENDING'; end if;
  select * into g from public.games where id = p_game;
  if coalesce(g.config->>'dice_mode','virtual_only') = 'physical_only' then raise exception 'VIRTUAL_DICE_DISABLED'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  perform public._p4_ensure_guardians(p_game);
  perform public._p5_ensure_decks(p_game);
  d1 := floor(random() * 6)::int + 1;
  d2 := floor(random() * 6)::int + 1;
  return public._p5_roll_resolve(p_game, me, d1, d2, p_request_id, 'roll_and_move');
end $$;

-- ── move_with_physical_roll (dados FÍSICOS): requiere modo que los permita y dados válidos 1–6 ──
create or replace function public.move_with_physical_roll(p_game uuid, p_die1 int, p_die2 int, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; me public.players; v_idem jsonb; v_cur text;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if p_die1 is null or p_die2 is null or p_die1 < 1 or p_die1 > 6 or p_die2 < 1 or p_die2 > 6 then raise exception 'INVALID_DIE_VALUE'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  v_cur := rt.turn_order_refs[rt.turn_index];
  if me.public_ref <> v_cur then raise exception 'NOT_CURRENT_PLAYER'; end if;
  if rt.pending_junction is not null then raise exception 'JUNCTION_PENDING'; end if;
  if rt.pending_card is not null then raise exception 'CARD_PENDING'; end if;
  if rt.pending_payment is not null then raise exception 'PAYMENT_PENDING'; end if;
  select * into g from public.games where id = p_game;
  if coalesce(g.config->>'dice_mode','virtual_only') = 'virtual_only' then raise exception 'PHYSICAL_DICE_DISABLED'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  perform public._p4_ensure_positions(p_game);
  perform public._p4_ensure_guardians(p_game);
  perform public._p5_ensure_decks(p_game);
  return public._p5_roll_resolve(p_game, me, p_die1, p_die2, p_request_id, 'move_with_physical_roll');
end $$;
grant execute on function public.move_with_physical_roll(uuid, int, int, uuid, bigint) to authenticated;

-- ── update_config: acepta también dice_mode en el lobby (mismo flujo que el resto de la config). ──
create or replace function public.update_config(p_game uuid, p_patch jsonb, p_expected_version int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; v_cfg jsonb; v_active_tokens int; v_max int; v_min int;
begin
  g := public._require_host(p_game);
  if g.status<>'lobby' then raise exception 'NOT_IN_LOBBY'; end if;
  if g.version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if p_patch ? 'dice_mode' and (p_patch->>'dice_mode') not in ('virtual_only','physical_allowed','physical_only') then raise exception 'INVALID_DICE_MODE'; end if;
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
    || (case when p_patch ? 'dice_mode'       then jsonb_build_object('dice_mode',(p_patch->>'dice_mode')) else '{}'::jsonb end);
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
