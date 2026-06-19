-- Fase 4 (corrección 3) — Snapshot: links_to_index + guardian_toll en spaces; board_links con las 4 esquinas de montaje.
-- tableros (board_links), para que la vista visual refleje el doble tablero. Mantiene privacidad de
-- saldos y el resto del contrato. Saneado (sin ids internos).
create or replace function public.get_active_snapshot_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; rt public.game_runtime; me public.players; v_cur text; v_players jsonb; v_ledger jsonb;
        v_is_host boolean; v_late jsonb; v_props jsonb; v_purchase jsonb; v_auctions jsonb; v_leave jsonb; v_bankrupt jsonb;
        v_start_bonus int; v_boards jsonb; v_spaces jsonb; v_positions jsonb; v_my_pos jsonb; v_current jsonb; v_links jsonb;
        v_my_board text; v_my_index int;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into g from public.games where code = upper(btrim(p_code));
  if not found then raise exception 'GAME_NOT_FOUND' using errcode = 'P0002'; end if;
  if g.status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  select * into me from public.players where game_id = g.id and auth_uid = auth.uid() and kicked_at is null and left_at is null;
  if not found then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  select * into rt from public.game_runtime where game_id = g.id;
  v_cur := rt.turn_order_refs[rt.turn_index];
  v_is_host := me.id = g.host_player_id;
  v_start_bonus := coalesce((g.config->>'start_bonus')::int, 200);

  -- Privacidad: cada jugador solo ve su propio saldo.
  select jsonb_agg(jsonb_build_object(
           'public_ref', p.public_ref, 'display_name', p.display_name, 'token_id', p.token_id,
           'balance', case when p.public_ref = me.public_ref then b.balance else null end,
           'is_current', p.public_ref = v_cur,
           'status', case when p.bankrupt_at is not null then 'bankrupt' else 'active' end)
           order by case when p.bankrupt_at is not null then 1 else 0 end, array_position(rt.turn_order_refs, p.public_ref))
    into v_players
    from public.players p
    join public.player_balances b on b.game_id = p.game_id and b.player_ref = p.public_ref
    where p.game_id = g.id and p.kicked_at is null and p.left_at is null
      and (p.public_ref = any(rt.turn_order_refs) or p.bankrupt_at is not null);

  select jsonb_agg(jsonb_build_object(
           'ledger_ref', l.ledger_ref, 'seq', l.seq, 'kind', l.kind, 'from_ref', l.from_ref, 'to_ref', l.to_ref,
           'amount', l.amount, 'before_balance', l.before_balance, 'after_balance', l.after_balance,
           'reason', l.reason, 'actor_ref', l.actor_ref,
           'reverts_ref', (select r.ledger_ref from public.ledger r where r.id = l.reverts_ledger_id),
           'created_at', l.created_at) order by l.seq desc)
    into v_ledger
    from (select * from public.ledger where game_id = g.id order by seq desc limit 25) l;

  select coalesce(jsonb_agg(jsonb_build_object(
           'property_ref', c.property_ref, 'board_key', c.board_key, 'group_key', c.group_key,
           'name', c.name, 'kind', c.kind, 'price', c.price, 'base_rent', c.base_rent,
           'is_buyable', c.is_buyable, 'sort_order', c.sort_order,
           'owner_ref', (select o.owner_ref from public.property_ownership o
                          where o.game_id = g.id and o.property_ref = c.property_ref and o.released_at is null),
           'in_auction', exists(select 1 from public.property_auctions a where a.game_id=g.id and a.property_ref=c.property_ref and a.status='active'))
           order by c.board_key, c.sort_order), '[]'::jsonb)
    into v_props from public.property_catalog c where c.active;

  select coalesce(jsonb_agg(jsonb_build_object(
           'auction_ref', a.public_ref, 'property_ref', a.property_ref,
           'property_name', (select name from public.property_catalog where property_ref=a.property_ref),
           'high_bid', a.high_bid, 'high_bidder_ref', a.high_bidder_ref,
           'started_by_ref', a.started_by_ref) order by a.started_at), '[]'::jsonb)
    into v_auctions from public.property_auctions a where a.game_id=g.id and a.status='active';

  if v_is_host then
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', pr.public_ref, 'property_ref', pr.property_ref,
             'property_name', (select name from public.property_catalog where property_ref=pr.property_ref),
             'requester_ref', pr.requester_ref,
             'requester_name', (select display_name from public.players where game_id=g.id and public_ref=pr.requester_ref)) order by pr.created_at), '[]'::jsonb)
      into v_purchase from public.property_purchase_requests pr where pr.game_id=g.id and pr.status='pending';
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', lr.public_ref, 'requester_ref', lr.requester_ref,
             'requester_name', (select display_name from public.players where game_id=g.id and public_ref=lr.requester_ref)) order by lr.created_at), '[]'::jsonb)
      into v_leave from public.player_leave_requests lr where lr.game_id=g.id and lr.status='pending';
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', br.public_ref, 'requester_ref', br.requester_ref,
             'requester_name', (select display_name from public.players where game_id=g.id and public_ref=br.requester_ref),
             'kind', br.kind, 'creditor_ref', br.creditor_ref,
             'creditor_name', (select display_name from public.players where game_id=g.id and public_ref=br.creditor_ref),
             'reason', br.reason) order by br.created_at), '[]'::jsonb)
      into v_bankrupt from public.bankruptcy_requests br where br.game_id=g.id and br.status='pending';
    select coalesce(jsonb_agg(jsonb_build_object(
             'request_ref', lr.public_ref, 'name', lr.desired_name, 'token', lr.desired_token, 'device_label', lr.device_label) order by lr.created_at), '[]'::jsonb)
      into v_late from public.late_join_requests lr where lr.game_id=g.id and lr.status='pending';
  else
    v_purchase := '[]'::jsonb; v_leave := '[]'::jsonb; v_bankrupt := '[]'::jsonb; v_late := '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'board_key', t.board_key, 'ring_size', t.n, 'start_bonus', v_start_bonus, 'provisional', t.prov) order by t.board_key), '[]'::jsonb)
    into v_boards
    from (select board_key, count(*)::int as n, bool_or(provisional) as prov from public.board_spaces where active group by board_key) t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'space_ref', s.space_ref, 'board_key', s.board_key, 'space_index', s.space_index,
           'name', s.name, 'space_type', s.space_type, 'property_ref', s.property_ref, 'is_start', s.is_start,
           'provisional', s.provisional, 'guardian', s.guardian, 'links_to_board', s.links_to_board, 'links_to_index', s.links_to_index, 'guardian_toll', s.guardian_toll)
           order by s.board_key, s.space_index), '[]'::jsonb)
    into v_spaces from public.board_spaces s where s.active;

  -- Enlaces de montaje entre tableros (esquinas con guardián).
  select coalesce(jsonb_agg(jsonb_build_object(
           'board_key', s.board_key, 'space_index', s.space_index, 'space_type', s.space_type,
           'links_to_board', s.links_to_board, 'links_to_index', s.links_to_index, 'guardian', s.guardian) order by s.board_key, s.space_index), '[]'::jsonb)
    into v_links from public.board_spaces s where s.active and s.links_to_board is not null;

  select coalesce(jsonb_agg(jsonb_build_object(
           'player_ref', pp.player_ref, 'board_key', pp.board_key, 'space_index', pp.space_index)
           order by pp.player_ref), '[]'::jsonb)
    into v_positions
    from public.player_positions pp
    join public.players p on p.game_id = pp.game_id and p.public_ref = pp.player_ref
    where pp.game_id = g.id and p.kicked_at is null and p.left_at is null;

  select pp.board_key, pp.space_index into v_my_board, v_my_index
    from public.player_positions pp where pp.game_id = g.id and pp.player_ref = me.public_ref;
  if v_my_board is not null then
    v_my_pos := jsonb_build_object('board_key', v_my_board, 'space_index', v_my_index);
    select jsonb_build_object('space_ref', s.space_ref, 'board_key', s.board_key, 'space_index', s.space_index,
             'name', s.name, 'space_type', s.space_type, 'property_ref', s.property_ref, 'is_start', s.is_start)
      into v_current from public.board_spaces s
      where s.board_key = v_my_board and s.space_index = v_my_index and s.active;
  else
    v_my_pos := null; v_current := null;
  end if;

  return jsonb_build_object(
    'game', jsonb_build_object('code', g.code, 'status', g.status,
      'config', jsonb_build_object(
        'initial_money', coalesce((g.config->>'initial_money')::int, 3000),
        'min_players',   coalesce((g.config->>'min_players')::int, 6),
        'max_players',   coalesce((g.config->>'max_players')::int, 16),
        'allow_late_join', coalesce((g.config->>'allow_late_join')::boolean, false),
        'start_bonus', v_start_bonus)),
    'me', jsonb_build_object('public_ref', me.public_ref, 'is_host', v_is_host,
      'balance', (select balance from public.player_balances where game_id = g.id and player_ref = me.public_ref),
      'is_current', me.public_ref = v_cur,
      'is_spectator', me.bankrupt_at is not null),
    'turn', jsonb_build_object('turn_number', rt.turn_number, 'current_player_ref', v_cur, 'order', to_jsonb(rt.turn_order_refs)),
    'players', coalesce(v_players, '[]'::jsonb),
    'ledger_recent', coalesce(v_ledger, '[]'::jsonb),
    'properties', v_props,
    'auctions', v_auctions,
    'purchase_requests', v_purchase,
    'leave_requests', v_leave,
    'bankruptcy_requests', v_bankrupt,
    'late_join_requests', v_late,
    'boards', v_boards,
    'spaces', v_spaces,
    'board_links', v_links,
    'positions', v_positions,
    'my_position', v_my_pos,
    'current_space', v_current,
    'last_roll', rt.last_roll,
    'last_move', rt.last_move,
    'runtime_status', rt.runtime_status,
    'control', jsonb_build_object('paused_by_ref', rt.paused_by_ref, 'finished_by_ref', rt.finished_by_ref, 'reason', rt.status_reason),
    'runtime_version', rt.runtime_version);
end $$;
