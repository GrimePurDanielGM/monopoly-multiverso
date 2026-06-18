-- Fase 2 — Redefinición de start_game: conserva EXACTAMENTE el comportamiento de Fase 1
-- (firma, idempotencia, sorteo único, validaciones, errores, auditoría, permisos) y AÑADE,
-- en la MISMA transacción del paso lobby->active, la inicialización del runtime y la siembra
-- de saldos/ledger. La rama idempotente (status ya 'active') no reinicializa nada.
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

  -- Orden criptográfico (gen_random_uuid) UNA sola vez; se almacena (igual que Fase 1).
  select array_agg(id order by gen_random_uuid()) into v_order
  from public.players where game_id = g.id and kicked_at is null;

  update public.games set status = 'active', started_at = now(), turn_order = v_order, version = version + 1
    where id = g.id returning * into g;

  -- ── Fase 2: runtime + siembra, en la MISMA transacción ──────────────────────────
  -- Orden de turnos saneado: traduce ids -> public_ref (sin exponer ids).
  insert into public.game_runtime(game_id, turn_order_refs, turn_index, turn_number, ledger_seq, runtime_version)
  select g.id, array_agg(p.public_ref order by o.ord), 1, 1, 0, 0
  from unnest(v_order) with ordinality as o(pid, ord)
  join public.players p on p.id = o.pid;

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

  perform public._audit(g.id, 'game_started', auth.uid(), null, v_order, null,
            jsonb_build_object('turn_order', to_jsonb(v_order)), null, false);
  return jsonb_build_object('status','active','turn_order',to_jsonb(g.turn_order),'idempotent',false);
end $$;
