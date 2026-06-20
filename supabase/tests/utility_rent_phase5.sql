-- ============================================================================
-- Alquiler de SERVICIOS combinable entre tableros (Fase 5 corrección ampliada): pay_utility_rent.
-- total dados × multiplicador (1→×4, 2→×10, 3→×14, 4→×20), contando servicios de AMBOS tableros.
-- Sin tirada válida → UTILITY_ROLL_REQUIRED. Ledger/auditoría con total/multiplicador/nº servicios.
-- No rompe privacidad de saldos. Tras `db reset`.
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
-- concede un servicio al propietario; fija la última tirada del pagador (host) con un total dado.
create or replace function pg_temp._own(gid uuid, prop text, owner_ref text) returns void language sql security definer as $f$
  insert into public.property_ownership(game_id,property_ref,owner_ref) values (gid,prop,owner_ref) on conflict do nothing $f$;
-- fija la última tirada del pagador Y simula una nueva caída (++landing_seq), para que el bloqueo de doble
-- pago por caída no impida cada pago de este suite (en juego real cada caída viene de un movimiento).
create or replace function pg_temp._setroll(gid uuid, ref text, total int) returns void language plpgsql security definer as $f$
begin update public.game_runtime set last_roll = jsonb_build_object('d1',1,'d2',total-1,'total',total,'player_ref',ref),
  landing_seq = landing_seq + 1 where game_id=gid; end $f$;
create or replace function pg_temp._land(gid uuid) returns void language sql security definer as $f$
  update public.game_runtime set landing_seq = landing_seq + 1 where game_id=gid $f$;

create or replace function pg_temp._build() returns void language plpgsql as $f$
declare host text:='d4000000-0000-0000-0000-0000000000a1'; j1 text:='d4000000-0000-0000-0000-000000000001'; r jsonb; gid uuid; code text; v int; href text; begin
  perform pg_temp._as_user(host); r:=create_game_tx('Util IT','Anf','penguin','{}',gen_random_uuid(),'H','S','A',1);
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

-- U1) 1 servicio → ×4 (tirada 8 → 32). Propietario p1, paga host con su última tirada.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); p1 text:=pg_temp._ctx('p1'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-cia-electricidad',p1); perform pg_temp._setroll(gid,href,8);
  perform pg_temp._as_user(host); res := pay_utility_rent(gid,'cl-cia-electricidad',null,null,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('U1) 1 servicio ×4: tirada 8 → 32',
    (res->>'utilities')='1' and (res->>'multiplier')='4' and (res->>'dice_total')='8' and (res->>'amount')='32');
end $$;

-- U2) 2 servicios → ×10 (tirada 8 → 80).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); p1 text:=pg_temp._ctx('p1'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'cl-cia-aguas',p1); perform pg_temp._setroll(gid,href,8);
  perform pg_temp._as_user(host); res := pay_utility_rent(gid,'cl-cia-electricidad',null,null,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('U2) 2 servicios ×10: tirada 8 → 80',
    (res->>'utilities')='2' and (res->>'multiplier')='10' and (res->>'amount')='80');
end $$;

-- U3) 3 servicios → ×14 (tirada 8 → 112). El 3º es de RdF (cuenta entre tableros).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); p1 text:=pg_temp._ctx('p1'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'bf-mr-fusion',p1); perform pg_temp._setroll(gid,href,8);
  perform pg_temp._as_user(host); res := pay_utility_rent(gid,'cl-cia-electricidad',null,null,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('U3) 3 servicios ×14: tirada 8 → 112 (ejemplo del spec)',
    (res->>'utilities')='3' and (res->>'multiplier')='14' and (res->>'amount')='112');
end $$;

-- U4) 4 servicios → ×20 (tirada 8 → 160).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); p1 text:=pg_temp._ctx('p1'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._own(gid,'bf-condensador-flujo',p1); perform pg_temp._setroll(gid,href,8);
  perform pg_temp._as_user(host); res := pay_utility_rent(gid,'cl-cia-electricidad',null,null,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('U4) 4 servicios ×20: tirada 8 → 160', (res->>'utilities')='4' and (res->>'multiplier')='20' and (res->>'amount')='160');
end $$;

-- U5) cuenta entre AMBOS tableros: caer en un servicio de RdF usa los 4 servicios del propietario (×20).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); href text:=pg_temp._ctx('host_ref'); res jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._setroll(gid,href,5);
  perform pg_temp._as_user(host); res := pay_utility_rent(gid,'bf-mr-fusion',null,null,gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin();
  perform pg_temp._rec('U5) servicio de RdF cuenta los 4 de ambos tableros: tirada 5 ×20 → 100',
    (res->>'utilities')='4' and (res->>'multiplier')='20' and (res->>'amount')='100');
end $$;

-- U6) sin tirada válida y modo physical_only sin dados físicos → UTILITY_ROLL_REQUIRED.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); p1 text:=pg_temp._ctx('p1'); ok boolean:=false; begin
  perform pg_temp._as_user(host); perform set_dice_mode(gid,'physical_only',gen_random_uuid(),pg_temp._ver(gid));
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  update public.game_runtime set last_roll = jsonb_build_object('total',7,'player_ref',p1) where game_id=gid; -- tirada de OTRO, no del pagador
  perform pg_temp._as_user(host);
  begin perform pay_utility_rent(gid,'cl-cia-electricidad',null,null,gen_random_uuid(),pg_temp._ver(gid)); exception when others then ok:=(sqlerrm='UTILITY_ROLL_REQUIRED'); end;
  perform pg_temp._as_admin();
  perform pg_temp._rec('U6) sin tirada válida (physical_only) → UTILITY_ROLL_REQUIRED', ok);
end $$;

-- U7) con dados físicos introducidos (physical_only): calcula y registra ledger + auditoría.
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); res jsonb; nled int; aud jsonb; begin
  perform pg_temp._as_admin(); perform pg_temp._land(gid);
  perform pg_temp._as_user(host); res := pay_utility_rent(gid,'cl-cia-electricidad',3,3,gen_random_uuid(),pg_temp._ver(gid)); -- 6 ×20 = 120
  perform pg_temp._as_admin();
  select count(*) into nled from public.ledger where game_id=gid and kind='rent_payment' and amount=120;
  select after into aud from public.audit_events where game_id=gid and type='utility_rent_paid' order by seq desc limit 1;
  perform pg_temp._rec('U7) dados físicos: 6×20=120; ledger rent_payment + auditoría con total/mult/nº',
    (res->>'amount')='120' and nled>=1 and (aud->>'dice_total')='6' and (aud->>'multiplier')='20' and (aud->>'utilities')='4');
end $$;

-- U8) privacidad de saldos: en el snapshot del pagador, el saldo de OTRO jugador es null (oculto).
do $$ declare gid uuid:=pg_temp._ctx('gid')::uuid; host text:=pg_temp._ctx('host'); code text:=pg_temp._ctx('code'); p1 text:=pg_temp._ctx('p1'); snap jsonb; p1bal jsonb; mebal jsonb; begin
  perform pg_temp._as_user(host); snap := get_active_snapshot_by_code(code); perform pg_temp._as_admin();
  select (e->'balance') into p1bal from jsonb_array_elements(snap->'players') e where e->>'public_ref'=p1;
  mebal := snap#>'{me,balance}';
  perform pg_temp._rec('U8) privacidad: saldo de otro jugador oculto (null) y el mío visible',
    p1bal = 'null'::jsonb and mebal is not null and jsonb_typeof(mebal)='number');
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
