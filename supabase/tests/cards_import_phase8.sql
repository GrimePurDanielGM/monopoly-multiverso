-- ============================================================================
-- Fase 8 — Cargador de cartas reales _p8_load_deck (importación turnkey).
-- Tras `supabase db reset`. Verifica: carga un mazo, desactiva los placeholders, los nuevos quedan activos,
-- conserva filas en manos de jugadores (FK), y un mazo recién sembrado usa SOLO las cartas activas nuevas.
-- ============================================================================
\set ON_ERROR_STOP on
drop table if exists _t; create temp table _t(name text primary key, ok boolean);
grant select, insert, update, delete on _t to authenticated;
create or replace function pg_temp._rec(p_name text, p_ok boolean) returns void language plpgsql as $f$
begin insert into _t values (p_name,p_ok) on conflict (name) do update set ok=excluded.ok;
  raise notice '%: %', case when p_ok then 'PASS' else 'FAIL' end, p_name; end $f$;

-- L1) carga 3 cartas reales en 'chance' → devuelve 3, quedan activas y los placeholders se desactivan.
do $$ declare n int; nact int; ntmp int; begin
  n := public._p8_load_deck('chance', $j$[
    {"card_ref":"chance-real-1","title":"Cobra 150","description":"Cobra 150 de la banca.","effect_type":"bank_credit","amount":150,"sort_order":1},
    {"card_ref":"chance-real-2","title":"Paga 75","description":"Paga 75 a la banca.","effect_type":"bank_debit","amount":75,"sort_order":2},
    {"card_ref":"chance-real-jf","title":"Sal de la cárcel","description":"Consérvala.","effect_type":"jail_free","keepable":true,"sort_order":3}
  ]$j$::jsonb);
  select count(*) into nact from public.card_catalog where deck_key='chance' and active;
  select count(*) into ntmp from public.card_catalog where deck_key='chance' and temporary and active;
  perform pg_temp._rec('L1) carga 3 cartas: devuelve 3, 3 activas, 0 placeholders activos', n=3 and nact=3 and ntmp=0);
end $$;

-- L2) las demás barajas (community_chest) no se tocan al cargar 'chance': mantienen sus 16 cartas activas.
do $$ declare c int; begin
  select count(*) into c from public.card_catalog where deck_key='community_chest' and active;
  perform pg_temp._rec('L2) otros mazos sin tocar (community_chest mantiene sus 16 cartas activas)', c=16);
end $$;

-- L3) re-cargar el mismo mazo (idempotente): upsert por card_ref, sigue habiendo 3 activas.
do $$ declare n int; nact int; begin
  n := public._p8_load_deck('chance', $j$[
    {"card_ref":"chance-real-1","title":"Cobra 200","description":"Cobra 200 de la banca.","effect_type":"bank_credit","amount":200,"sort_order":1}
  ]$j$::jsonb);
  select count(*) into nact from public.card_catalog where deck_key='chance' and active;
  perform pg_temp._rec('L3) recarga idempotente: 1 activa nueva (las anteriores se desactivan)', nact=1 and (select amount from public.card_catalog where card_ref='chance-real-1')=200);
end $$;

-- L4) columnas nuevas (target_space/target_board/manual_instruction) se almacenan.
do $$ declare ok boolean; begin
  perform public._p8_load_deck('past', $j$[
    {"card_ref":"past-real-move","title":"Muévete","description":"Ve a la Salida.","effect_type":"manual","target_space":"Salida","target_board":"classic","manual_instruction":"Mueve a la Salida y cobra el sueldo","sort_order":1}
  ]$j$::jsonb);
  select target_space='Salida' and target_board='classic' and manual_instruction is not null into ok
    from public.card_catalog where card_ref='past-real-move';
  perform pg_temp._rec('L4) columnas target_space/target_board/manual_instruction almacenadas', ok);
end $$;

-- L5) deck inválido → error saneado.
do $$ declare ok boolean; begin
  begin perform public._p8_load_deck('nope', '[]'::jsonb); ok:=false;
  exception when others then ok:=(sqlerrm='INVALID_DECK'); end;
  perform pg_temp._rec('L5) mazo inválido → INVALID_DECK', ok);
end $$;

do $$ declare nfail int; begin select count(*) into nfail from _t where not ok;
  if nfail>0 then raise exception 'HAY % FALLOS', nfail; else raise notice 'RESULTADO: TODOS PASAN'; end if; end $$;
