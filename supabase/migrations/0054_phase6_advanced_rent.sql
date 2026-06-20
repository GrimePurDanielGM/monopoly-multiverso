-- Fase 6 — Alquiler avanzado de CALLES en pay_rent. Mantiene estaciones/transportes (escala 1–8),
-- servicios por pay_utility_rent, y el bloqueo de doble pago por caída (RENT_ALREADY_PAID).
-- Calle: hipotecada → sin alquiler (NO_RENT_DUE) · hotel → rent_hotel · 1–4 casas → rent_N ·
--        monopolio sin casas → base×2 · sin monopolio → base.

create or replace function public.pay_rent(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_owner text;
        v_idem jsonb; v_ver bigint; v_bal bigint; v_amount bigint; v_n int; v_res jsonb; v_is_station boolean;
        v_h int; v_hotel boolean; v_mort boolean; v_mono boolean; v_basis text;
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
  v_basis := c.kind;
  if v_is_station then
    select count(*) into v_n from public.property_ownership o
      join public.property_catalog cc on cc.property_ref = o.property_ref
      where o.game_id = p_game and o.owner_ref = v_owner and o.released_at is null and cc.kind in ('station','transport') and cc.active;
    v_amount := public._p3_station_rent(v_n);
  else
    -- CALLE: depende de hipoteca / hotel / casas / monopolio
    select houses, has_hotel, mortgaged into v_h, v_hotel, v_mort from public._p6_state(p_game, p_property_ref);
    if v_mort then
      v_amount := 0; v_basis := 'mortgaged';
    elsif v_hotel then
      v_amount := coalesce(c.rent_hotel, c.base_rent); v_basis := 'hotel';
    elsif v_h >= 1 then
      v_amount := coalesce(case v_h when 1 then c.rent_1 when 2 then c.rent_2 when 3 then c.rent_3 else c.rent_4 end, c.base_rent);
      v_basis := 'houses_' || v_h;
    else
      v_mono := public._p6_is_monopoly(p_game, p_property_ref);
      if v_mono then v_amount := c.base_rent * 2; v_basis := 'monopoly'; else v_amount := c.base_rent; v_basis := 'base'; end if;
    end if;
  end if;

  if v_amount <= 0 then raise exception 'NO_RENT_DUE'; end if;   -- incluye calle hipotecada
  if rt.landing_seq <= rt.rent_resolved_seq then raise exception 'RENT_ALREADY_PAID'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < v_amount then raise exception 'INSUFFICIENT_FUNDS'; end if;
  perform public._p2_move(p_game, me.public_ref, v_owner, v_amount);
  perform public._p2_post(p_game, 'rent_payment', me.public_ref, v_owner, v_amount,
                          null, null, null, me.public_ref, null, p_request_id);
  update public.game_runtime set rent_resolved_seq = rt.landing_seq where game_id = p_game;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'rent_paid', auth.uid(), me.id, array[me.id], null,
            jsonb_build_object('property', c.property_ref, 'payer', me.public_ref, 'owner', v_owner, 'amount', v_amount,
                               'kind', c.kind, 'basis', v_basis)
            || (case when v_is_station then jsonb_build_object('stations', v_n) else '{}'::jsonb end)
            || (case when not v_is_station then jsonb_build_object('houses', coalesce(v_h,0), 'has_hotel', coalesce(v_hotel,false)) else '{}'::jsonb end),
            null, false);
  perform public._emit_active_signal(p_game);
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  v_res := jsonb_build_object('property_ref', c.property_ref, 'paid_to', v_owner, 'amount', v_amount,
                              'balance', v_bal, 'runtime_version', v_ver, 'basis', v_basis)
           || (case when v_is_station then jsonb_build_object('stations', v_n) else '{}'::jsonb end);
  perform public._p2_save(p_game, p_request_id, 'pay_rent', v_res);
  return v_res;
end $$;
