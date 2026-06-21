-- ============================================================================
-- Fase 7 — Snapshot de tratos (incoming/outgoing/reviews/recent, saneado, privacidad de saldos).
-- Tras `supabase db reset`. Setup: partida activa con host (H), p1, p2; p1 posee Ronda (calle), p2 la estación de Goya.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
drop table if exists _ctx; create temp table _ctx(k text primary key, v text);
grant select, insert, update, delete on _t, _ctx to authenticated;
create or replace function pg_temp._as_user(uid text) returns void language plpgsql as $f$
begin perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true); if auth.uid()<>uid::uuid then raise exception 'bad'; end if; end $f$;
create or replace function pg_temp._as_admin() returns void language plpgsql as $f$ begin perform set_config('role', session_user, true); end $f$;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;
create or replace function pg_temp._ctx(k text) returns text language sql as $f$ select v from _ctx where k=$1 $f$;
create or replace function pg_temp._ver(gid uuid) returns bigint language sql security definer as $f$ select runtime_version from public.game_runtime where game_id=gid $f$;
create or replace function pg_temp._bal(gid uuid, ref text) returns bigint language sql security definer as $f$ select balance from public.player_balances where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._own(gid uuid, prop text, ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,ref) on conflict do nothing $f$;
create or replace function pg_temp._reown(gid uuid, prop text, ref text) returns void language sql security definer as $f$
  with rel as (update public.property_ownership set released_at=now() where game_id=gid and property_ref=prop and released_at is null returning 1)
  insert into public.property_ownership(game_id,property_ref,owner_ref) select gid,prop,ref from (select 1) s left join rel on true $f$;
create or replace function pg_temp._tstatus(gid uuid, tref text) returns text language sql security definer as $f$
  select status::text from public.game_trade_proposals where game_id=gid and public_ref=tref $f$;
create or replace function pg_temp._ownerof(gid uuid, prop text) returns text language sql security definer as $f$
  select owner_ref from public.property_ownership where game_id=gid and property_ref=prop and released_at is null $f$;
create or replace function pg_temp._cardcount(gid uuid, ref text) returns int language sql security definer as $f$
  select count(*)::int from public.game_held_cards where game_id=gid and player_ref=ref $f$;
create or replace function pg_temp._givecard(gid uuid, ref text, card text) returns void language sql security definer as $f$
  insert into public.game_held_cards(game_id,player_ref,card_ref) values (gid,ref,card) $f$;
create or replace function pg_temp._sethouses(gid uuid, prop text, n int) returns void language sql security definer as $f$
  insert into public.game_property_state(game_id,property_ref,houses) values (gid,prop,n)
    on conflict (game_id,property_ref) do update set houses=n $f$;
create or replace function pg_temp._setmort(gid uuid, prop text) returns void language sql security definer as $f$
  insert into public.game_property_state(game_id,property_ref,mortgaged) values (gid,prop,true)
    on conflict (game_id,property_ref) do update set mortgaged=true $f$;
create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='f8000000-0000-0000-0000-0000000000a1'; j1 text:='f8000000-0000-0000-0000-000000000001';
        j2 text:='f8000000-0000-0000-0000-000000000002'; r jsonb; gid uuid; code text; v int; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Tratos IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_uid',host) on conflict (k) do update set v=excluded.v;
  perform pg_temp._as_admin(); insert into _ctx select 'host_ref', public_ref from players where game_id=gid and auth_uid=host::uuid on conflict (k) do update set v=excluded.v;
  select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_user(j2); perform join_game(code,'P2',gen_random_uuid());
  perform pg_temp._as_admin();
  insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid on conflict (k) do update set v=excluded.v;
  insert into _ctx select 'p2', public_ref from players where game_id=gid and auth_uid=j2::uuid on conflict (k) do update set v=excluded.v;
  insert into _ctx values ('p1_uid',j1),('p2_uid',j2) on conflict (k) do update set v=excluded.v;
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(j2); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'iron'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v);
  perform pg_temp._as_admin();
  perform pg_temp._own(gid,'cl-ronda-valencia',pg_temp._ctx('p1'));
  perform pg_temp._own(gid,'cl-estacion-goya',pg_temp._ctx('p2'));
  update public.player_balances set balance=100000 where game_id=gid;
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- N1) snapshot del creador muestra outgoing; del destinatario incoming.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); p1u text:=pg_temp._ctx('p1_uid'); p2u text:=pg_temp._ctx('p2_uid'); r jsonb; t text; so jsonb; si jsonb; begin
  perform pg_temp._as_user(p1u); r := create_trade_proposal(gid, pg_temp._ctx('p2'), 0, 300, array['cl-ronda-valencia'], null, null, null, null, gen_random_uuid()); t:=r->>'trade_ref';
  so := get_active_snapshot_by_code(code);  -- como p1
  perform pg_temp._as_user(p2u); si := get_active_snapshot_by_code(code);  -- como p2
  perform pg_temp._as_admin();
  perform pg_temp._rec('N1) outgoing en el creador / incoming en el destinatario',
    (so#>>'{outgoing_trades,0,trade_ref}')=t and (si#>>'{incoming_trades,0,trade_ref}')=t and (so#>>'{incoming_trades,0,trade_ref}') is null);
  insert into _ctx values ('tn', t) on conflict (k) do update set v=excluded.v;
end $$;
-- N2) snapshot del host muestra trade_reviews al pasar a host_review.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host_uid'); p2u text:=pg_temp._ctx('p2_uid'); t text:=pg_temp._ctx('tn'); snap jsonb; begin
  perform pg_temp._as_user(p2u); perform accept_trade_proposal(t, pg_temp._ver(gid), gen_random_uuid());
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code);
  perform pg_temp._as_admin(); perform pg_temp._rec('N2) host ve trade_reviews en host_review', (snap#>>'{trade_reviews,0,trade_ref}')=t and (snap#>>'{trade_reviews,0,requires_host}')='true');
end $$;
-- N3) recent_trades tras ejecutar.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); host text:=pg_temp._ctx('host_uid'); p1u text:=pg_temp._ctx('p1_uid'); t text:=pg_temp._ctx('tn'); snap jsonb; found boolean; begin
  perform pg_temp._as_user(host); perform resolve_trade_proposal(t, true, pg_temp._ver(gid));
  perform pg_temp._as_user(p1u); snap := get_active_snapshot_by_code(code);
  perform pg_temp._as_admin();
  select exists(select 1 from jsonb_array_elements(snap->'recent_trades') e where e->>'trade_ref'=t and e->>'status'='executed') into found;
  perform pg_temp._rec('N3) recent_trades incluye el trato ejecutado', found);
end $$;
-- N4) saneado: serializa el snapshot y comprueba que no aparece auth_uid ni la columna id interna.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); p1u text:=pg_temp._ctx('p1_uid'); snap jsonb; txt text; begin
  perform pg_temp._as_user(p1u); snap := get_active_snapshot_by_code(code); txt := snap::text;
  perform pg_temp._as_admin();
  perform pg_temp._rec('N4) snapshot de tratos saneado (sin auth_uid)', position('auth_uid' in txt)=0 and position(pg_temp._ctx('host_uid') in txt)=0);
end $$;
-- N5) privacidad de saldos: en el snapshot de p1, el saldo de p2 es null.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; code text:=pg_temp._ctx('code'); p1u text:=pg_temp._ctx('p1_uid'); p2 text:=pg_temp._ctx('p2'); snap jsonb; v_bal jsonb; begin
  perform pg_temp._as_user(p1u); snap := get_active_snapshot_by_code(code);
  perform pg_temp._as_admin();
  select e->'balance' into v_bal from jsonb_array_elements(snap->'players') e where e->>'public_ref'=p2;
  perform pg_temp._rec('N5) privacidad de saldos intacta (saldo ajeno null)', v_bal = 'null'::jsonb);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
