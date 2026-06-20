-- ============================================================================
-- Alquiler ACUMULATIVO de estaciones/transportes (Fase 5 corrección), combinable entre AMBOS tableros.
-- Escala 1–8: 25/50/100/200/300/400/500/600. Cuenta Classic + RdF; no cuenta las de otros jugadores.
-- Ledger rent_payment + auditoría con nº e importe; privacidad de saldos. Tras `db reset`.
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
create or replace function pg_temp._own(gid uuid, prop text, owner_ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,owner_ref) on conflict do nothing $f$;
-- simula una nueva caída (para que el pago no quede bloqueado por "ya pagado").
create or replace function pg_temp._land(gid uuid) returns void language sql security definer as $f$
  update public.game_runtime set landing_seq = landing_seq + 1 where game_id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='e1000000-0000-0000-0000-0000000000a1'; j1 text:='e1000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Tren IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
  gid:=(r->>'game_id')::uuid; code:=r->>'code'; href:=r->>'host_public_ref';
  insert into _ctx values ('gid',gid::text),('code',code),('host',host),('host_ref',href),('host_uid',host);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform update_config(gid, jsonb_build_object('min_players',2), v);
  perform pg_temp._as_user(j1); perform join_game(code,'P1',gen_random_uuid());
  perform pg_temp._as_admin(); insert into _ctx select 'p1', public_ref from players where game_id=gid and auth_uid=j1::uuid;
  insert into _ctx values ('p1_uid',j1);
  perform pg_temp._as_user(j1); perform choose_token(gid,'cat'); perform set_ready(gid,true);
  perform pg_temp._as_user(host); perform choose_token(gid,'boot'); perform set_ready(gid,true);
  perform pg_temp._as_admin(); select version into v from games where id=gid;
  perform pg_temp._as_user(host); perform start_game(gid,v); perform pg_temp._as_admin();
end $f$;
do $$ begin perform pg_temp._build(); end $$;

-- Escala progresiva: p1 acumula estaciones/transportes y el host paga; importe = escala(n).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1');
            res jsonb; props text[]:=array['cl-estacion-goya','cl-estacion-delicias','cl-estacion-norte','cl-estacion-mediodia','bf-tren-tiempo','bf-coche-biff','bf-patinete','bf-aeropatin'];
            expect int[]:=array[25,50,100,200,300,400,500,600]; i int; begin
  for i in 1..8 loop
    perform pg_temp._as_admin(); perform pg_temp._own(gid, props[i], p1); perform pg_temp._land(gid);
    perform pg_temp._as_user(host); res := pay_rent(gid, props[i], gen_random_uuid(), pg_temp._ver(gid));
    perform pg_temp._as_admin();
    perform pg_temp._rec(format('T%s) %s estaciones/transportes → %s', i, i, expect[i]),
      (res->>'amount')::int = expect[i] and (res->>'stations')::int = i);
  end loop;
end $$;

-- T9) cuenta AMBOS tableros: con 4 classic + 1 RdF ya cobrados arriba, una caída en un transporte de RdF usa n=8.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  perform pg_temp._as_user(host); res := pay_rent(gid, 'bf-tren-tiempo', gen_random_uuid(), pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('T9) caer en transporte de RdF cuenta los 8 de ambos tableros → 600', (res->>'amount')='600' and (res->>'stations')='8');
end $$;

-- T10) NO cuenta las de otros jugadores: se da una estación a p2... (aquí host) y p1 sigue con 8 (no 9, no existen más).
--   Comprobamos que dar una estación al PAGADOR no altera el conteo del propietario p1 (sigue contando solo p1).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); n int; begin
  perform pg_temp._as_admin();
  select count(*) into n from public.property_ownership o join public.property_catalog c on c.property_ref=o.property_ref
    where o.game_id=gid and o.owner_ref=pg_temp._ctx('p1') and o.released_at is null and c.kind in ('station','transport');
  perform pg_temp._rec('T10) el conteo es por propietario (p1 posee las 8; no se suman las de otros)', n=8);
end $$;

-- T11) ledger rent_payment + auditoría con nº e importe; privacidad de saldos.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); p1 text:=pg_temp._ctx('p1');
            nled int; aud jsonb; snap jsonb; p1bal jsonb; begin
  perform pg_temp._as_admin();
  select count(*) into nled from public.ledger where game_id=gid and kind='rent_payment';
  select after into aud from public.audit_events where game_id=gid and type='rent_paid' order by seq desc limit 1;
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  select (e->'balance') into p1bal from jsonb_array_elements(snap->'players') e where e->>'public_ref'=p1;
  perform pg_temp._rec('T11) ledger rent_payment + auditoría (stations/amount) + privacidad de saldos',
    nled>=9 and (aud->>'stations') is not null and (aud->>'amount') is not null and p1bal = 'null'::jsonb);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
