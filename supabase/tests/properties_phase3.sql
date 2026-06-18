-- ============================================================================
-- Catálogo REAL de propiedades (Fase 3 corrección). Tras `supabase db reset`.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
grant select, insert, update, delete on _t to authenticated;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;

-- 1) catálogo real sustituye al de prueba (56 props; 0 refs de prueba tipo 'cl-marron-1'/'cl-celeste-1').
do $$ declare n int; test_refs int; begin
  select count(*) into n from property_catalog where active;
  select count(*) into test_refs from property_catalog where property_ref in ('cl-marron-1','cl-celeste-1','cl-estacion-1','cl-salida','bf-flux','bf-1955-1');
  perform pg_temp._rec('1) catálogo real cargado (56) y sin refs de prueba', n=56 and test_refs=0);
end $$;

-- 2) distribución por tablero/tipo correcta.
do $$ declare ok boolean; begin
  select
    (select count(*) from property_catalog where board_key='classic' and kind='street')=22
    and (select count(*) from property_catalog where board_key='classic' and kind='station')=4
    and (select count(*) from property_catalog where board_key='classic' and kind='utility')=2
    and (select count(*) from property_catalog where board_key='back_to_the_future' and kind='street')=22
    and (select count(*) from property_catalog where board_key='back_to_the_future' and kind='transport')=4
    and (select count(*) from property_catalog where board_key='back_to_the_future' and kind='utility')=2
    into ok;
  perform pg_temp._rec('2) distribución por tablero/tipo (22 calles + 4 estaciones/transportes + 2 utilities por tablero)', ok);
end $$;

-- 3) todas las propiedades tienen property_ref no vacío.
do $$ declare bad int; begin
  select count(*) into bad from property_catalog where property_ref is null or btrim(property_ref)='';
  perform pg_temp._rec('3) todas las propiedades tienen property_ref', bad=0);
end $$;

-- 4) no hay property_ref duplicados (los nombres repetidos van con sufijo).
do $$ declare dups int; begin
  select count(*) into dups from (select property_ref from property_catalog group by property_ref having count(*)>1) z;
  perform pg_temp._rec('4) sin property_ref duplicados', dups=0);
end $$;

-- 5) precio provisional marcado (price_source) y coherente con la hipoteca (price = 2×hipoteca esperado);
--    utilities comprables con base_rent=0; estaciones/transportes base_rent=25.
do $$ declare not_board int; bad_util int; bad_sta int; begin
  select count(*) into not_board from property_catalog where price_source <> 'board';
  select count(*) into bad_util from property_catalog where kind='utility' and (not is_buyable or base_rent<>0 or price<>150);
  select count(*) into bad_sta from property_catalog where kind in ('station','transport') and (base_rent<>25 or price<>200);
  perform pg_temp._rec('5) precio confirmado por tablero (price_source=board) + utilities base 0 + estaciones/transportes base 25',
    not_board=0 and bad_util=0 and bad_sta=0);
end $$;

-- 6) estación de Goya presente como estación válida Classic.
do $$ declare ok boolean; begin
  select exists(select 1 from property_catalog where property_ref='cl-estacion-goya' and board_key='classic' and kind='station' and name='Estación de Goya' and base_rent=25) into ok;
  perform pg_temp._rec('6) Estación de Goya (hecha a mano) presente como estación válida', ok);
end $$;

-- 7) catálogo deny-all: SELECT directo como authenticated denegado.
do $$ declare ok boolean:=false; begin
  perform set_config('request.jwt.claims', json_build_object('sub','99000000-0000-0000-0000-000000000001','role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  begin perform 1 from public.property_catalog limit 1; exception when others then ok:=(sqlstate='42501'); end;
  perform set_config('role', session_user, true);
  perform pg_temp._rec('7) property_catalog deny-all (SELECT directo denegado)', ok);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── properties_phase3: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
