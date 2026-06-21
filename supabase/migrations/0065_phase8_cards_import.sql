-- ============================================================================
-- Fase 8 — Infraestructura de importación de cartas reales.
--
-- El sistema de cartas (mazos, robo, descarte, conservables, snapshot, UI) ya está completo desde Fase 5,
-- pero las 36 cartas sembradas son PLACEHOLDERS marcados temporary=true. Esta migración NO inventa cartas:
-- prepara la estructura para importar las cartas reales cuando se aporten los textos/fotos oficiales.
--
-- 1) Columnas opcionales para el modelo de carta enriquecido (no cambian el comportamiento actual):
--      target_space        — casilla destino (space_ref o nombre) para "muévete a …"
--      target_board        — tablero destino para cartas que cruzan de tablero
--      manual_instruction   — texto de instrucción para cartas de resolución manual
-- 2) _p8_load_deck(deck, jsonb) — cargador idempotente y seguro con la FK de game_held_cards: desactiva las
--    cartas activas actuales del mazo e inserta/activa las nuevas. Una futura migración con los textos reales
--    sólo tendrá que llamar a esta función (ver docs/cards_import_template.csv y docs/datos-pendientes.md).
-- ============================================================================

alter table public.card_catalog add column if not exists target_space text;
alter table public.card_catalog add column if not exists target_board text;
alter table public.card_catalog add column if not exists manual_instruction text;

-- Cargador de un mazo completo desde un array JSON de definiciones de carta. Pensado para usarse en una
-- migración futura (no expuesto a clientes). Conserva las cartas ya repartidas (FK) marcándolas inactivas.
create or replace function public._p8_load_deck(p_deck text, p_cards jsonb)
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if p_deck not in ('chance','community_chest','past','future') then raise exception 'INVALID_DECK'; end if;
  -- Las cartas actuales del mazo dejan de robarse; las que estén en manos de jugadores conservan su fila (FK).
  update public.card_catalog set active = false where deck_key = p_deck and active;
  insert into public.card_catalog(
    card_ref, deck_key, title, description, effect_type, amount, keepable, temporary,
    target_space, target_board, manual_instruction, sort_order, active)
  select x.card_ref, p_deck, x.title, x.description, x.effect_type, x.amount,
         coalesce(x.keepable,false), coalesce(x.temporary,false),
         x.target_space, x.target_board, x.manual_instruction, coalesce(x.sort_order,0), true
  from jsonb_to_recordset(p_cards) as x(
    card_ref text, title text, description text, effect_type text, amount int,
    keepable boolean, temporary boolean, target_space text, target_board text, manual_instruction text, sort_order int)
  on conflict (card_ref) do update set
    deck_key = excluded.deck_key, title = excluded.title, description = excluded.description,
    effect_type = excluded.effect_type, amount = excluded.amount, keepable = excluded.keepable,
    temporary = excluded.temporary, target_space = excluded.target_space, target_board = excluded.target_board,
    manual_instruction = excluded.manual_instruction, sort_order = excluded.sort_order, active = true;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public._p8_load_deck(text, jsonb) from public, anon, authenticated;
