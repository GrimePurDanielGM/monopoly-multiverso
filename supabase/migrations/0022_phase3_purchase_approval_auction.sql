-- Fase 3 (corrección) — Compra de propiedad SIEMPRE bajo aprobación del anfitrión + subasta.
-- El cliente ya no ejecuta compra directa: solicita (request_property_purchase) y el anfitrión aprueba
-- (resolve_property_purchase) o inicia subasta. Patrón Fase 2 en las mutaciones económicas.

-- ── Ledger: compra por subasta (jugador -> banca) ────────────────────────────────
alter table public.ledger drop constraint ledger_kind_check;
alter table public.ledger add constraint ledger_kind_check check (kind in
  ('seed','bank_to_player','player_to_bank','player_to_player','host_player_transfer','host_adjust','host_revert','late_join_seed',
   'player_exit_to_bank','player_exit_distribution','player_exit_remainder_to_bank',
   'property_purchase','rent_payment','property_auction_purchase'));
alter table public.ledger drop constraint ledger_shape;
alter table public.ledger add constraint ledger_shape check (
  case kind
    when 'seed' then from_ref is null and to_ref is not null and reverts_ledger_id is null and request_id is null and before_balance is null and after_balance is null
    when 'late_join_seed' then from_ref is null and to_ref is not null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'bank_to_player' then from_ref is null and to_ref is not null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_bank' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'player_to_player' then from_ref is not null and to_ref is not null and from_ref <> to_ref and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'host_player_transfer' then from_ref is not null and to_ref is not null and from_ref <> to_ref and reason is not null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'host_adjust' then before_balance is not null and after_balance is not null and before_balance <> after_balance and amount = abs(after_balance - before_balance)
      and ((after_balance > before_balance and from_ref is null and to_ref is not null) or (after_balance < before_balance and from_ref is not null and to_ref is null))
      and reason is not null and reverts_ledger_id is null and request_id is not null
    when 'host_revert' then reverts_ledger_id is not null and reason is not null and request_id is not null and before_balance is null and after_balance is null
      and ( ((from_ref is null) <> (to_ref is null)) or (from_ref is not null and to_ref is not null and from_ref <> to_ref) )
    when 'player_exit_to_bank' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'player_exit_distribution' then from_ref is not null and to_ref is not null and from_ref <> to_ref and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'player_exit_remainder_to_bank' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'property_purchase' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'rent_payment' then from_ref is not null and to_ref is not null and from_ref <> to_ref and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    when 'property_auction_purchase' then from_ref is not null and to_ref is null and reverts_ledger_id is null and request_id is not null and before_balance is null and after_balance is null
    else false
  end
);

-- ── Helper interno: asigna una propiedad cobrando el precio a la banca ────────────
create or replace function public._p3_assign_property(
  p_game uuid, p_property_ref text, p_buyer_ref text, p_price bigint, p_kind text, p_request_id uuid
) returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v_ledger text;
begin
  if p_price > 0 then
    perform public._p2_move(p_game, p_buyer_ref, null, p_price);
    v_ledger := public._p2_post(p_game, p_kind, p_buyer_ref, null, p_price, null, null, null, p_buyer_ref, null, p_request_id);
  end if;
  insert into public.property_ownership(game_id, property_ref, owner_ref, acquired_by_ledger_ref)
    values (p_game, p_property_ref, p_buyer_ref, v_ledger);
  return v_ledger;
end $$;
revoke all on function public._p3_assign_property(uuid, text, text, bigint, text, uuid) from public, anon, authenticated;

-- El cliente ya NO puede comprar directamente: se revoca buy_property (queda como helper histórico).
revoke execute on function public.buy_property(uuid, text, uuid, bigint) from public, anon, authenticated;

-- ── Solicitudes de compra ────────────────────────────────────────────────────────
create table public.property_purchase_requests (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null default public.gen_public_ref(),
  game_id uuid not null references public.games(id) on delete cascade,
  property_ref text not null references public.property_catalog(property_ref),
  requester_ref text not null,                                  -- public_ref del solicitante
  status public.request_status not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  resolved_by_ref text null,
  result_ledger_ref text null
);
create unique index ppr_pubref_key on public.property_purchase_requests (public_ref);
create unique index ppr_one_pending on public.property_purchase_requests (game_id, property_ref, requester_ref) where status='pending';
create index ppr_game_pending_idx on public.property_purchase_requests (game_id) where status='pending';
alter table public.property_purchase_requests enable row level security;   -- deny-all
revoke all on public.property_purchase_requests from anon, authenticated;

-- ── Subastas y pujas ─────────────────────────────────────────────────────────────
create table public.property_auctions (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null default public.gen_public_ref(),
  game_id uuid not null references public.games(id) on delete cascade,
  property_ref text not null references public.property_catalog(property_ref),
  status text not null default 'active' check (status in ('active','closed','cancelled')),
  high_bid bigint null,
  high_bidder_ref text null,
  started_by_ref text not null,
  started_at timestamptz not null default now(),
  closed_at timestamptz null,
  close_reason text null,
  winner_ref text null,
  result_ledger_ref text null
);
create unique index pa_pubref_key on public.property_auctions (public_ref);
create unique index pa_one_active on public.property_auctions (game_id, property_ref) where status='active';
create index pa_game_active_idx on public.property_auctions (game_id) where status='active';
alter table public.property_auctions enable row level security;            -- deny-all
revoke all on public.property_auctions from anon, authenticated;

create table public.property_bids (
  id uuid primary key default gen_random_uuid(),
  auction_id uuid not null references public.property_auctions(id) on delete cascade,
  bidder_ref text not null,
  amount bigint not null check (amount > 0),
  created_at timestamptz not null default now(),
  request_id uuid null
);
create index pb_auction_idx on public.property_bids (auction_id, created_at);
alter table public.property_bids enable row level security;                -- deny-all
revoke all on public.property_bids from anon, authenticated;

-- ── request_property_purchase: el jugador solicita; no cambia economía ────────────
create or replace function public.request_property_purchase(p_game uuid, p_property_ref text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; c public.property_catalog; v_idem jsonb; r public.property_purchase_requests; v_existing public.property_purchase_requests;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;  -- guarda pausa/finished
  me := public._require_active_player(p_game);
  select * into c from public.property_catalog where property_ref = p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if not c.is_buyable then raise exception 'PROPERTY_NOT_BUYABLE'; end if;
  if not (me.public_ref = any(rt.turn_order_refs)) then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  perform 1 from public.property_ownership where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if found then raise exception 'PROPERTY_ALREADY_OWNED'; end if;
  perform 1 from public.property_auctions where game_id=p_game and property_ref=p_property_ref and status='active';
  if found then raise exception 'PROPERTY_IN_AUCTION'; end if;
  -- Idempotente: solicitud pendiente existente del mismo jugador para esta propiedad.
  select * into v_existing from public.property_purchase_requests where game_id=p_game and property_ref=p_property_ref and requester_ref=me.public_ref and status='pending';
  if found then
    perform public._p2_save(p_game, p_request_id, 'request_property_purchase', jsonb_build_object('request_ref', v_existing.public_ref, 'status', 'pending'));
    return jsonb_build_object('request_ref', v_existing.public_ref, 'status', 'pending');
  end if;
  insert into public.property_purchase_requests(game_id, property_ref, requester_ref) values (p_game, p_property_ref, me.public_ref) returning * into r;
  perform public._audit(p_game,'property_purchase_requested',auth.uid(),me.id,array[me.id],null,jsonb_build_object('property',p_property_ref,'request',r.public_ref),null,false);
  perform public._emit_active_signal(p_game);
  perform public._p2_save(p_game, p_request_id, 'request_property_purchase', jsonb_build_object('request_ref', r.public_ref, 'status', 'pending'));
  return jsonb_build_object('request_ref', r.public_ref, 'status', 'pending');
end $$;

-- ── resolve_property_purchase: el anfitrión aprueba/rechaza ───────────────────────
create or replace function public.resolve_property_purchase(p_request_ref text, p_accept boolean, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.property_purchase_requests; g public.games; rt public.game_runtime; c public.property_catalog;
        v_host_ref text; v_bal bigint; v_ledger text; v_ver bigint; v_buyer public.players;
begin
  select * into r from public.property_purchase_requests where public_ref=p_request_ref for update;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  g := public._require_host(r.game_id);                         -- bloquea games + valida host
  select * into rt from public.game_runtime where game_id=g.id for update;
  if rt.runtime_status='finished' then raise exception 'GAME_FINISHED'; end if;
  if rt.runtime_status='paused' then raise exception 'GAME_PAUSED'; end if;   -- compras NO se aprueban en pausa
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'idempotent', true); end if;
  select public_ref into v_host_ref from public.players where id=g.host_player_id;
  if not p_accept then
    update public.property_purchase_requests set status='rejected', resolved_at=now(), resolved_by_ref=v_host_ref where id=r.id;
    perform public._audit(g.id,'property_purchase_rejected',auth.uid(),null,null,null,jsonb_build_object('request',r.public_ref,'property',r.property_ref),null,false);
    perform public._emit_active_signal(g.id);
    return jsonb_build_object('status','rejected');
  end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  -- Revalidar: propiedad disponible, no en subasta, comprador activo y con saldo.
  select * into c from public.property_catalog where property_ref=r.property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if not c.is_buyable then raise exception 'PROPERTY_NOT_BUYABLE'; end if;
  perform 1 from public.property_ownership where game_id=g.id and property_ref=r.property_ref and released_at is null;
  if found then raise exception 'PROPERTY_ALREADY_OWNED'; end if;
  perform 1 from public.property_auctions where game_id=g.id and property_ref=r.property_ref and status='active';
  if found then raise exception 'PROPERTY_IN_AUCTION'; end if;
  select * into v_buyer from public.players where game_id=g.id and public_ref=r.requester_ref and kicked_at is null and left_at is null;
  if not found then raise exception 'BUYER_NOT_ACTIVE'; end if;
  if not (r.requester_ref = any(rt.turn_order_refs)) then raise exception 'BUYER_NOT_ACTIVE'; end if;
  select balance into v_bal from public.player_balances where game_id=g.id and player_ref=r.requester_ref for update;
  if v_bal < c.price then raise exception 'INSUFFICIENT_FUNDS'; end if;
  v_ledger := public._p3_assign_property(g.id, r.property_ref, r.requester_ref, c.price, 'property_purchase', gen_random_uuid());
  update public.property_purchase_requests set status='approved', resolved_at=now(), resolved_by_ref=v_host_ref, result_ledger_ref=v_ledger where id=r.id;
  v_ver := public._p2_bump(g.id);
  perform public._audit(g.id,'property_purchase_approved',auth.uid(),v_buyer.id,array[v_buyer.id],null,
    jsonb_build_object('request',r.public_ref,'property',r.property_ref,'buyer',r.requester_ref,'price',c.price),null,false);
  perform public._emit_active_signal(g.id);
  return jsonb_build_object('status','approved','property_ref',r.property_ref,'owner_ref',r.requester_ref,'price',c.price,'runtime_version',v_ver);
end $$;

-- ── start_property_auction: el anfitrión inicia subasta sobre propiedad disponible ─
create or replace function public.start_property_auction(p_game uuid, p_property_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; c public.property_catalog; v_idem jsonb; a public.property_auctions; v_ver bigint;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;  -- guarda pausa/finished
  g := public._require_host(p_game);
  select * into c from public.property_catalog where property_ref=p_property_ref and active;
  if not found then raise exception 'PROPERTY_NOT_FOUND' using errcode='P0002'; end if;
  if not c.is_buyable then raise exception 'PROPERTY_NOT_BUYABLE'; end if;
  perform 1 from public.property_ownership where game_id=p_game and property_ref=p_property_ref and released_at is null;
  if found then raise exception 'PROPERTY_ALREADY_OWNED'; end if;
  perform 1 from public.property_auctions where game_id=p_game and property_ref=p_property_ref and status='active';
  if found then raise exception 'AUCTION_ALREADY_ACTIVE'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  insert into public.property_auctions(game_id, property_ref, started_by_ref)
    values (p_game, p_property_ref, (select public_ref from public.players where id=g.host_player_id)) returning * into a;
  -- Solicitudes de compra pendientes de esa propiedad quedan resueltas (van a subasta).
  update public.property_purchase_requests set status='rejected', resolved_at=now() where game_id=p_game and property_ref=p_property_ref and status='pending';
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game,'property_auction_started',auth.uid(),null,null,null,jsonb_build_object('auction',a.public_ref,'property',p_property_ref),null,false);
  perform public._emit_active_signal(p_game);
  return jsonb_build_object('auction_ref',a.public_ref,'property_ref',p_property_ref,'runtime_version',v_ver);
end $$;

-- ── place_property_bid: un jugador activo puja ───────────────────────────────────
create or replace function public.place_property_bid(p_game uuid, p_auction_ref text, p_amount bigint, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; me public.players; a public.property_auctions; v_idem jsonb; v_bal bigint; v_ver bigint;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  me := public._require_active_player(p_game);
  select * into a from public.property_auctions where public_ref=p_auction_ref and game_id=p_game for update;
  if not found then raise exception 'AUCTION_NOT_FOUND' using errcode='P0002'; end if;
  if a.status <> 'active' then raise exception 'AUCTION_NOT_ACTIVE'; end if;
  if not (me.public_ref = any(rt.turn_order_refs)) then raise exception 'NOT_ACTIVE_MEMBER'; end if;
  if a.high_bid is not null and p_amount <= a.high_bid then raise exception 'BID_TOO_LOW'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=me.public_ref;
  if p_amount > v_bal then raise exception 'INSUFFICIENT_FUNDS'; end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  insert into public.property_bids(auction_id, bidder_ref, amount, request_id) values (a.id, me.public_ref, p_amount, p_request_id);
  update public.property_auctions set high_bid=p_amount, high_bidder_ref=me.public_ref where id=a.id;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game,'property_bid_placed',auth.uid(),me.id,array[me.id],null,jsonb_build_object('auction',a.public_ref,'bidder',me.public_ref,'amount',p_amount),null,false);
  perform public._emit_active_signal(p_game);
  perform public._p2_save(p_game, p_request_id, 'place_property_bid', jsonb_build_object('auction_ref',a.public_ref,'high_bid',p_amount,'runtime_version',v_ver));
  return jsonb_build_object('auction_ref',a.public_ref,'high_bid',p_amount,'high_bidder',me.public_ref,'runtime_version',v_ver);
end $$;

-- ── close_property_auction: el anfitrión cierra (adjudica al ganador o sin pujas) ──
create or replace function public.close_property_auction(p_game uuid, p_auction_ref text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; a public.property_auctions; v_idem jsonb; v_bal bigint; v_ledger text; v_ver bigint; v_winner public.players;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  select * into a from public.property_auctions where public_ref=p_auction_ref and game_id=p_game for update;
  if not found then raise exception 'AUCTION_NOT_FOUND' using errcode='P0002'; end if;
  if a.status <> 'active' then return jsonb_build_object('status', a.status, 'idempotent', true); end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if a.high_bidder_ref is null then
    -- sin pujas: propiedad sigue disponible
    update public.property_auctions set status='closed', closed_at=now(), close_reason='no_bids' where id=a.id;
    v_ver := public._p2_bump(p_game);
    perform public._audit(p_game,'property_auction_closed',auth.uid(),null,null,null,jsonb_build_object('auction',a.public_ref,'property',a.property_ref,'result','no_bids'),null,false);
    perform public._emit_active_signal(p_game);
    return jsonb_build_object('status','closed','result','no_bids','runtime_version',v_ver);
  end if;
  -- con ganador: revalidar saldo y que siga activo y la propiedad disponible
  select * into v_winner from public.players where game_id=p_game and public_ref=a.high_bidder_ref and kicked_at is null and left_at is null;
  if not found or not (a.high_bidder_ref = any(rt.turn_order_refs)) then raise exception 'WINNER_NOT_ACTIVE'; end if;
  perform 1 from public.property_ownership where game_id=p_game and property_ref=a.property_ref and released_at is null;
  if found then raise exception 'PROPERTY_ALREADY_OWNED'; end if;
  select balance into v_bal from public.player_balances where game_id=p_game and player_ref=a.high_bidder_ref for update;
  if v_bal < a.high_bid then raise exception 'WINNER_INSUFFICIENT_FUNDS'; end if;  -- subasta queda abierta; el anfitrión decide
  v_ledger := public._p3_assign_property(p_game, a.property_ref, a.high_bidder_ref, a.high_bid, 'property_auction_purchase', gen_random_uuid());
  update public.property_auctions set status='closed', closed_at=now(), close_reason='awarded', winner_ref=a.high_bidder_ref, result_ledger_ref=v_ledger where id=a.id;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game,'property_auction_closed',auth.uid(),v_winner.id,array[v_winner.id],null,
    jsonb_build_object('auction',a.public_ref,'property',a.property_ref,'result','awarded','winner',a.high_bidder_ref,'amount',a.high_bid),null,false);
  perform public._emit_active_signal(p_game);
  return jsonb_build_object('status','closed','result','awarded','winner',a.high_bidder_ref,'amount',a.high_bid,'runtime_version',v_ver);
end $$;

-- ── cancel_property_auction: el anfitrión cancela (propiedad sigue disponible) ─────
create or replace function public.cancel_property_auction(p_game uuid, p_auction_ref text, p_reason text, p_request_id uuid, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare rt public.game_runtime; g public.games; a public.property_auctions; v_idem jsonb; v_ver bigint;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  rt := public._p2_lock(p_game);
  v_idem := public._p2_idem(p_game, p_request_id); if v_idem is not null then return v_idem; end if;
  g := public._require_host(p_game);
  select * into a from public.property_auctions where public_ref=p_auction_ref and game_id=p_game for update;
  if not found then raise exception 'AUCTION_NOT_FOUND' using errcode='P0002'; end if;
  if a.status <> 'active' then return jsonb_build_object('status', a.status, 'idempotent', true); end if;
  if rt.runtime_version <> p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  update public.property_auctions set status='cancelled', closed_at=now(), close_reason=coalesce(nullif(btrim(p_reason),''),'cancelada') where id=a.id;
  v_ver := public._p2_bump(p_game);
  perform public._audit(p_game,'property_auction_cancelled',auth.uid(),null,null,null,jsonb_build_object('auction',a.public_ref,'property',a.property_ref,'reason',p_reason),p_reason,false);
  perform public._emit_active_signal(p_game);
  return jsonb_build_object('status','cancelled','runtime_version',v_ver);
end $$;

grant execute on function public.request_property_purchase(uuid, text, uuid)              to authenticated;
grant execute on function public.resolve_property_purchase(text, boolean, bigint)          to authenticated;
grant execute on function public.start_property_auction(uuid, text, uuid, bigint)          to authenticated;
grant execute on function public.place_property_bid(uuid, text, bigint, uuid, bigint)      to authenticated;
grant execute on function public.close_property_auction(uuid, text, uuid, bigint)          to authenticated;
grant execute on function public.cancel_property_auction(uuid, text, text, uuid, bigint)   to authenticated;
