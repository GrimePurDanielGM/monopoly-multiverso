-- ============================================================================
-- Bug B — «Deshacer última acción» global del anfitrión.
-- Hasta ahora host_revert_movement solo revertía el DINERO de un asiento del ledger; si un jugador
-- compraba una propiedad (o construía) por error, el dinero volvía pero la propiedad/casa se quedaba.
-- host_undo_last localiza la ÚLTIMA acción reversible (último asiento del ledger no revertido, que no sea
-- seed/host_revert/quiebra) y deshace TANTO el dinero COMO el estado asociado, despachando por `kind`:
--   · property_purchase / property_auction_purchase → libera la posesión (acquired_by_ledger_ref).
--   · building_purchase / hotel_purchase / building_sale / hotel_sale → revierte casas/hotel + stock
--     (la propiedad se localiza por game_building_requests.result_ledger_ref, que ahora se rellena).
--   · mortgage_received / unmortgage_payment → revierte el flag de hipoteca (propiedad vía active_requests).
--   · tax_payment / card_bank_charge (alimentan el bote) → descuenta del bote lo añadido.
--   · parking_pot_payout (vació el bote) → restaura el bote (tope 2.500 €).
--   · resto (alquileres, transferencias, pagos de carta entre jugadores, ajustes) → solo dinero (es el deshacer completo).
-- Llamadas repetidas recorren el historial hacia atrás (cada deshacer marca su compensación, excluida del siguiente).
-- ============================================================================

-- ── resolve_building_request: idéntico a 0057 + guarda el ledger_ref resultante (para poder deshacer la construcción). ──
create or replace function public.resolve_building_request(p_request_ref text, p_accept boolean, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.game_building_requests; g public.games; rt public.game_runtime; v_host_ref text; v_ver bigint; v_res jsonb; v_lref text;
begin
  select * into r from public.game_building_requests where public_ref=p_request_ref for update;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(r.game_id);
  select * into rt from public.game_runtime where game_id=g.id for update;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  if rt.runtime_status='paused' then raise exception 'GAME_PAUSED'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'idempotent', true); end if;
  select public_ref into v_host_ref from public.players where id=g.host_player_id;
  if not p_accept then
    update public.game_building_requests set status='rejected', resolved_at=now(), resolved_by_ref=v_host_ref where id=r.id;
    perform public._audit(g.id,'building_rejected',auth.uid(),null,null,null,jsonb_build_object('request',r.public_ref,'property',r.property_ref,'action',r.action),null,false);
    perform public._emit_active_signal(g.id);
    return jsonb_build_object('status','rejected');
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  -- Revalidar + ejecutar (el estado puede haber cambiado desde la solicitud).
  case r.action
    when 'build_house' then v_res := public._p6_do_build_house(g.id, r.requester_ref, r.property_ref, gen_random_uuid(), false);
    when 'build_hotel' then v_res := public._p6_do_build_hotel(g.id, r.requester_ref, r.property_ref, gen_random_uuid(), false);
    when 'sell_house'  then v_res := public._p6_do_sell_house(g.id, r.requester_ref, r.property_ref, gen_random_uuid(), false);
    when 'sell_hotel'  then v_res := public._p6_do_sell_hotel(g.id, r.requester_ref, r.property_ref, gen_random_uuid(), false);
  end case;
  -- el _p6_do_* acaba de postear EXACTAMENTE un asiento (mantenemos el lock del runtime) → es el último por seq.
  select ledger_ref into v_lref from public.ledger where game_id=g.id order by seq desc limit 1;
  update public.game_building_requests set status='approved', resolved_at=now(), resolved_by_ref=v_host_ref, result_ledger_ref=v_lref where id=r.id;
  v_ver := public._p2_bump(g.id);
  perform public._audit(g.id,'building_approved',auth.uid(),null,null,null,jsonb_build_object('request',r.public_ref,'property',r.property_ref,'action',r.action),null,false);
  perform public._emit_active_signal(g.id);
  return v_res || jsonb_build_object('status','approved','runtime_version',v_ver);
end $$;
grant execute on function public.resolve_building_request(text, boolean, bigint) to authenticated;

-- ── Deshacer la última acción (anfitrión). ──
create or replace function public.host_undo_last(p_game uuid, p_reason text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; v_idem jsonb; v_ver bigint; m public.ledger;
        v_from text; v_to text; v_bal bigint; v_host_ref text; v_comp text; v_res jsonb;
        v_result jsonb; v_prop text;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'REASON_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);

  -- Última acción reversible: último asiento que no sea semilla/compensación/quiebra y que no esté ya revertido.
  select * into m from public.ledger l
   where l.game_id = p_game
     and l.kind not in ('seed','late_join_seed','host_revert')
     and not exists (select 1 from public.ledger r where r.game_id = p_game and r.reverts_ledger_id = l.id)
   order by l.seq desc limit 1;
  if not found then raise exception 'NOTHING_TO_UNDO'; end if;
  if m.kind in ('player_exit_to_bank','player_exit_distribution','player_exit_remainder_to_bank',
                'bankruptcy_cash_to_bank','bankruptcy_cash_to_player') then
    raise exception 'CANNOT_UNDO_KIND';   -- repartos de quiebra/salida: no se deshacen automáticamente
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;

  -- 1) DINERO: compensación inversa (intercambia from/to; banco = NULL se conserva).
  v_from := m.to_ref; v_to := m.from_ref;
  if v_from is not null then
    select balance into v_bal from public.player_balances where game_id = p_game and player_ref = v_from for update;
    if v_bal < m.amount then raise exception 'WOULD_GO_NEGATIVE'; end if;
  end if;
  perform public._p2_move(p_game, v_from, v_to, m.amount);

  -- 2) ESTADO: según el tipo de asiento.
  if m.kind in ('property_purchase','property_auction_purchase') then
    update public.property_ownership set released_at = now(), released_reason = 'host_undo'
      where game_id = p_game and acquired_by_ledger_ref = m.ledger_ref and released_at is null;

  elsif m.kind = 'building_purchase' then          -- se construyó una casa
    select property_ref into v_prop from public.game_building_requests where game_id=p_game and result_ledger_ref=m.ledger_ref;
    if v_prop is not null then
      update public.game_property_state set houses = greatest(houses - 1, 0), updated_at = now() where game_id=p_game and property_ref=v_prop;
      update public.game_runtime set houses_available = houses_available + 1 where game_id=p_game;
    end if;
  elsif m.kind = 'hotel_purchase' then             -- se construyó un hotel
    select property_ref into v_prop from public.game_building_requests where game_id=p_game and result_ledger_ref=m.ledger_ref;
    if v_prop is not null then
      update public.game_property_state set has_hotel=false, houses=4, updated_at=now() where game_id=p_game and property_ref=v_prop;
      update public.game_runtime set hotels_available = hotels_available + 1, houses_available = houses_available - 4 where game_id=p_game;
    end if;
  elsif m.kind = 'building_sale' then              -- se vendió una casa
    select property_ref into v_prop from public.game_building_requests where game_id=p_game and result_ledger_ref=m.ledger_ref;
    if v_prop is not null then
      update public.game_property_state set houses = houses + 1, updated_at=now() where game_id=p_game and property_ref=v_prop;
      update public.game_runtime set houses_available = houses_available - 1 where game_id=p_game;
    end if;
  elsif m.kind = 'hotel_sale' then                 -- se vendió un hotel
    select property_ref into v_prop from public.game_building_requests where game_id=p_game and result_ledger_ref=m.ledger_ref;
    if v_prop is not null then
      update public.game_property_state set has_hotel=true, houses=0, updated_at=now() where game_id=p_game and property_ref=v_prop;
      update public.game_runtime set hotels_available = hotels_available - 1, houses_available = houses_available + 4 where game_id=p_game;
    end if;

  elsif m.kind = 'mortgage_received' then          -- se hipotecó (RPC directa: propiedad en active_requests)
    select ar.result into v_result from public.active_requests ar where ar.game_id=p_game and ar.request_id=m.request_id;
    v_prop := v_result->>'property_ref';
    if v_prop is not null then update public.game_property_state set mortgaged=false, updated_at=now() where game_id=p_game and property_ref=v_prop; end if;
  elsif m.kind = 'unmortgage_payment' then         -- se deshipotecó
    select ar.result into v_result from public.active_requests ar where ar.game_id=p_game and ar.request_id=m.request_id;
    v_prop := v_result->>'property_ref';
    if v_prop is not null then update public.game_property_state set mortgaged=true, updated_at=now() where game_id=p_game and property_ref=v_prop; end if;
  end if;

  -- Bote del Parking: las cargas que lo alimentan lo reducen al deshacer; el cobro del bote lo restaura (tope 2.500).
  if m.kind in ('tax_payment','card_bank_charge') then
    update public.game_runtime set parking_pot = greatest(parking_pot - m.amount, 0) where game_id = p_game;
  elsif m.kind = 'parking_pot_payout' then
    update public.game_runtime set parking_pot = least(2500, parking_pot + m.amount) where game_id = p_game;
  end if;

  -- 3) Compensación en el ledger + auditoría + señal de realtime.
  select public_ref into v_host_ref from public.players where id = g.host_player_id;
  v_comp := public._p2_post(p_game, 'host_revert', v_from, v_to, m.amount, null, null, p_reason, v_host_ref, m.id, p_request_id);
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game, 'host_undo_last', auth.uid(), g.host_player_id, null,
            jsonb_build_object('reverts', m.ledger_ref, 'kind', m.kind, 'property', v_prop),
            jsonb_build_object('compensation', v_comp), p_reason, false);
  perform public._emit_active_signal(p_game);
  v_res := jsonb_build_object('changed', true, 'reverted_ref', m.ledger_ref, 'reverted_kind', m.kind,
             'property_ref', v_prop, 'compensation_ref', v_comp, 'runtime_version', v_ver);
  perform public._p2_save(p_game, p_request_id, 'host_undo_last', v_res);
  return v_res;
end $$;
revoke all on function public.host_undo_last(uuid, text, uuid, bigint) from public, anon, authenticated;
grant execute on function public.host_undo_last(uuid, text, uuid, bigint) to authenticated;
