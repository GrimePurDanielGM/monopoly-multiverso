-- Fase 5 (corrección ampliada) — Alquiler de SERVICIOS (utilities) combinable entre AMBOS tableros.
-- El alquiler = total de los dados × multiplicador según cuántos servicios ACTIVOS posea el propietario:
--   1 servicio ×4 · 2 servicios ×10 · 3 servicios ×14 · 4 servicios ×20  (se cuentan los 4 de los dos tableros).
-- Fuente del total de dados (en orden): (1) la última tirada del pagador que le hizo caer; (2) dados físicos
-- introducidos; (3) tirada virtual generada si el modo lo permite. Sin tirada válida → UTILITY_ROLL_REQUIRED.

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
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;

  select * into g from public.games where id = p_game;
  v_mode := coalesce(g.config->>'dice_mode','virtual_only');

  -- Total de los dados, por prioridad de fuentes.
  if p_die1 is not null or p_die2 is not null then
    -- dados físicos introducidos
    if v_mode = 'virtual_only' then raise exception 'PHYSICAL_DICE_DISABLED'; end if;
    if p_die1 is null or p_die2 is null or p_die1 < 1 or p_die1 > 6 or p_die2 < 1 or p_die2 > 6 then raise exception 'INVALID_DIE_VALUE'; end if;
    v_total := p_die1 + p_die2;
  elsif rt.last_roll is not null and (rt.last_roll->>'player_ref') = me.public_ref then
    -- la última tirada del pagador (la que le hizo caer)
    v_total := (rt.last_roll->>'total')::int;
  elsif v_mode <> 'physical_only' then
    -- tirada virtual generada para calcular el servicio
    d1 := floor(random() * 6)::int + 1; d2 := floor(random() * 6)::int + 1; v_total := d1 + d2;
  else
    raise exception 'UTILITY_ROLL_REQUIRED';
  end if;

  -- Nº de servicios ACTIVOS del propietario (ambos tableros) y multiplicador.
  select count(*) into v_n from public.property_ownership o
    join public.property_catalog cc on cc.property_ref = o.property_ref
    where o.game_id = p_game and o.owner_ref = v_owner and o.released_at is null and cc.kind = 'utility' and cc.active;
  v_mult := case when v_n >= 4 then 20 when v_n = 3 then 14 when v_n = 2 then 10 else 4 end;
  v_amount := v_total::bigint * v_mult;

  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref for update;
  if v_bal < v_amount then raise exception 'INSUFFICIENT_FUNDS'; end if;
  perform public._p2_move(p_game, me.public_ref, v_owner, v_amount);
  perform public._p2_post(p_game, 'rent_payment', me.public_ref, v_owner, v_amount, null, null, null, me.public_ref, null, p_request_id);
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
