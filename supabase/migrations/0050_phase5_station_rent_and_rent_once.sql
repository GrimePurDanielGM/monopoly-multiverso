-- Fase 5 (corrección) — Alquiler ACUMULATIVO de estaciones/transportes (combinable entre tableros) y
-- BLOQUEO de doble pago de alquiler por la misma caída (pay_rent y pay_utility_rent).
-- Escala estaciones/transportes (1–8, contando Classic + Regreso al Futuro):
--   1→25 · 2→50 · 3→100 · 4→200 · 5→300 · 6→400 · 7→500 · 8→600.

create or replace function public._p3_station_rent(n int) returns int language sql immutable as $$
  select case when n >= 8 then 600 when n = 7 then 500 when n = 6 then 400 when n = 5 then 300
              when n = 4 then 200 when n = 3 then 100 when n = 2 then 50 when n = 1 then 25 else 0 end;
$$;

-- pay_rent: calles por base_rent; estaciones/transportes por escala acumulativa (servicios → pay_utility_rent).
-- Una sola vez por caída: si landing_seq <= rent_resolved_seq → RENT_ALREADY_PAID.
create or replace function public.pay_rent(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_owner text;
        v_idem jsonb; v_ver bigint; v_bal bigint; v_amount bigint; v_n int; v_res jsonb; v_is_station boolean;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id);
  if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind = 'utility' then raise exception 'NOT_A_UTILITY'; end if;  -- los servicios van por pay_utility_rent
  select owner_ref into v_owner from public.property_ownership
    where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if v_owner is null then raise exception 'PROPERTY_NOT_OWNED'; end if;
  if not (v_owner = any(rt.turn_order_refs)) then raise exception 'PROPERTY_NOT_OWNED'; end if;
  if v_owner = me.public_ref then raise exception 'SELF_RENT'; end if;

  v_is_station := c.kind in ('station', 'transport');
  if v_is_station then
    -- nº de estaciones/transportes ACTIVOS del propietario (ambos tableros) → escala acumulativa
    select count(*) into v_n from public.property_ownership o
      join public.property_catalog cc on cc.property_ref = o.property_ref
      where o.game_id = p_game and o.owner_ref = v_owner and o.released_at is null and cc.kind in ('station','transport') and cc.active;
    v_amount := public._p3_station_rent(v_n);
  else
    v_amount := c.base_rent;
  end if;
  if v_amount <= 0 then raise exception 'NO_RENT_DUE'; end if;
  if rt.landing_seq <= rt.rent_resolved_seq then raise exception 'RENT_ALREADY_PAID'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < v_amount then raise exception 'INSUFFICIENT_FUNDS'; end if;
  perform public._p2_move(p_game, me.public_ref, v_owner, v_amount);
  perform public._p2_post(p_game, 'rent_payment', me.public_ref, v_owner, v_amount,
                          null, null, null, me.public_ref, null, p_request_id);
  update public.game_runtime set rent_resolved_seq = rt.landing_seq where game_id = p_game;  -- caída resuelta
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'rent_paid', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', c.property_ref, 'payer', me.public_ref, 'owner', v_owner, 'amount', v_amount,
                               'kind', c.kind) || (case when v_is_station then jsonb_build_object('stations', v_n) else '{}'::jsonb end),
            null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', c.property_ref, 'paid_to', v_owner, 'amount', v_amount,
                              'balance', v_bal, 'runtime_version', v_ver)
           || (case when v_is_station then jsonb_build_object('stations', v_n) else '{}'::jsonb end);
  perform public._p2_save(p_game, p_request_id, 'pay_rent', v_res);
  return v_res;
end $$;

-- pay_utility_rent: idéntico a 0047 pero con el bloqueo de doble pago por caída.
create or replace function public.pay_utility_rent(p_game uuid, p_property_ref text, p_die1 int, p_die2 int, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; g public.games; c public.property_catalog; v_owner text;
        v_idem jsonb; v_ver bigint; v_bal bigint; v_total int; v_n int; v_mult int; v_amount bigint; v_mode text;
        d1 int; d2 int; v_res jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if c.kind <> 'utility' then raise exception 'NOT_A_UTILITY'; end if;
  select owner_ref into v_owner from public.property_ownership
    where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if v_owner is null then raise exception 'PROPERTY_NOT_OWNED'; end if;
  if not (v_owner = any(rt.turn_order_refs)) then raise exception 'PROPERTY_NOT_OWNED'; end if;
  if v_owner = me.public_ref then raise exception 'SELF_RENT'; end if;
  if rt.landing_seq <= rt.rent_resolved_seq then raise exception 'RENT_ALREADY_PAID'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;

  select * into g from public.games where id = p_game;
  v_mode := coalesce(g.config->>'dice_mode','virtual_only');
  if p_die1 is not null or p_die2 is not null then
    if v_mode = 'virtual_only' then raise exception 'PHYSICAL_DICE_DISABLED'; end if;
    if p_die1 is null or p_die2 is null or p_die1 < 1 or p_die1 > 6 or p_die2 < 1 or p_die2 > 6 then raise exception 'INVALID_DIE_VALUE'; end if;
    v_total := p_die1 + p_die2;
  elsif rt.last_roll is not null and (rt.last_roll->>'player_ref') = me.public_ref then
    v_total := (rt.last_roll->>'total')::int;
  elsif v_mode <> 'physical_only' then
    d1 := floor(random() * 6)::int + 1; d2 := floor(random() * 6)::int + 1; v_total := d1 + d2;
  else
    raise exception 'UTILITY_ROLL_REQUIRED';
  end if;

  select count(*) into v_n from public.property_ownership o
    join public.property_catalog cc on cc.property_ref = o.property_ref
    where o.game_id = p_game and o.owner_ref = v_owner and o.released_at is null and cc.kind = 'utility' and cc.active;
  v_mult := case when v_n >= 4 then 20 when v_n = 3 then 14 when v_n = 2 then 10 else 4 end;
  v_amount := v_total::bigint * v_mult;

  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < v_amount then raise exception 'INSUFFICIENT_FUNDS'; end if;
  perform public._p2_move(p_game, me.public_ref, v_owner, v_amount);
  perform public._p2_post(p_game, 'rent_payment', me.public_ref, v_owner, v_amount, null, null, null, me.public_ref, null, p_request_id);
  update public.game_runtime set rent_resolved_seq = rt.landing_seq where game_id = p_game;  -- caída resuelta
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'utility_rent_paid', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', c.property_ref, 'payer', me.public_ref, 'owner', v_owner,
                               'dice_total', v_total, 'utilities', v_n, 'multiplier', v_mult, 'amount', v_amount), null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', c.property_ref, 'paid_to', v_owner, 'dice_total', v_total,
            'utilities', v_n, 'multiplier', v_mult, 'amount', v_amount, 'balance', v_bal, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'pay_utility_rent', v_res);
  return v_res;
end $$;
grant execute on function public.pay_utility_rent(uuid, text, int, int, uuid, bigint) to authenticated;
