-- ============================================================================
-- Catálogo de casillas (Fase 4): derivado del catálogo real, anillo start+propiedades.
-- Tras `supabase db reset`. No requiere partida (lecturas privilegiadas).
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;

-- B1) hay casillas para ambos tableros.
do $$ declare nc int; nb int; begin
  select count(*) into nc from public.board_spaces where board_key='classic' and active;
  select count(*) into nb from public.board_spaces where board_key='back_to_the_future' and active;
  perform pg_temp._rec('B1) casillas en ambos tableros (classic>0 y bf>0)', nc>0 and nb>0);
end $$;

-- B2) exactamente una salida (is_start, índice 0) por tablero.
do $$ declare n int; begin
  select count(*) into n from public.board_spaces
   where is_start and space_index=0 and space_type='start' and board_key in ('classic','back_to_the_future');
  select count(*) into n from (select board_key from public.board_spaces where is_start group by board_key having count(*)=1) t;
  perform pg_temp._rec('B2) una única salida por tablero', n=2);
end $$;

-- B3) Classic = anillo real de 40 casillas (orden físico); RdF = derivado provisional (1 + nº props).
do $$ declare rc int; rb int; pb int; begin
  rc := public._p4_ring_size('classic'); rb := public._p4_ring_size('back_to_the_future');
  select count(*) into pb from public.property_catalog where board_key='back_to_the_future' and active;
  perform pg_temp._rec('B3) Classic=40 casillas; RdF=derivado (1 + nº props)', rc = 40 and rb = pb+1);
end $$;

-- B3b) Classic: índices clave del orden real (no debe confundir Ronda de Valencia con Bilbao).
do $$ declare ok boolean; begin
  select (select property_ref from public.board_spaces where board_key='classic' and space_index=1)='cl-ronda-valencia'
     and (select name from public.board_spaces where board_key='classic' and space_index=2)='Caja de Comunidad'
     and (select property_ref from public.board_spaces where board_key='classic' and space_index=11)='cl-bilbao'
     and (select space_type from public.board_spaces where board_key='classic' and space_index=10)='jail'
     and (select space_type from public.board_spaces where board_key='classic' and space_index=30)='go_to_jail'
     and (select space_type from public.board_spaces where board_key='classic' and space_index=20)='parking'
     and (select property_ref from public.board_spaces where board_key='classic' and space_index=39)='cl-prado'
    into ok;
  perform pg_temp._rec('B3b) Classic: orden real (1 Ronda, 2 Comunidad, 11 Bilbao, 10 cárcel, 30 ir-cárcel, 39 Prado)', ok);
end $$;

-- B3c) RdF marcado como provisional (orden por confirmar).
do $$ declare allprov boolean; begin
  select bool_and(provisional) into allprov from public.board_spaces where board_key='back_to_the_future' and active;
  perform pg_temp._rec('B3c) RdF marcado provisional', allprov);
end $$;

-- B4) cada propiedad COMPRABLE tiene exactamente una casilla 'property' que la referencia.
do $$ declare missing int; dup int; begin
  select count(*) into missing from public.property_catalog c
    where c.active and not exists (select 1 from public.board_spaces s where s.property_ref=c.property_ref);
  select count(*) into dup from (
    select property_ref from public.board_spaces where property_ref is not null group by property_ref having count(*)>1) d;
  perform pg_temp._rec('B4) cada propiedad tiene 1 casilla (sin faltantes ni duplicadas)', missing=0 and dup=0);
end $$;

-- B5) las casillas 'property' apuntan a property_ref del catálogo; las no-propiedad no tienen property_ref.
do $$ declare bad1 int; bad2 int; begin
  select count(*) into bad1 from public.board_spaces s where s.space_type='property'
    and (s.property_ref is null or not exists(select 1 from public.property_catalog c where c.property_ref=s.property_ref));
  select count(*) into bad2 from public.board_spaces s where s.space_type<>'property' and s.property_ref is not null;
  perform pg_temp._rec('B5) enlace casilla↔propiedad correcto (no inventa, no comprables sin property_ref)', bad1=0 and bad2=0);
end $$;

-- B6) índices contiguos 0..N-1 por tablero (sin huecos ni duplicados).
do $$ declare gaps int; begin
  select count(*) into gaps from (
    select board_key,
           count(*) as n, min(space_index) as lo, max(space_index) as hi, count(distinct space_index) as d
    from public.board_spaces where active group by board_key) t
   where not (lo=0 and d=n and hi=n-1);
  perform pg_temp._rec('B6) índices 0..N-1 contiguos por tablero', gaps=0);
end $$;

do $$ declare n_ok int; n_all int; begin
  select count(*) filter (where ok), count(*) into n_ok, n_all from _t;
  raise notice '──────────── board_phase4: % / % OK ────────────', n_ok, n_all;
  if n_ok <> n_all then raise exception 'FALLOS: %', (select string_agg(name,' | ') from _t where not ok); end if;
end $$;
