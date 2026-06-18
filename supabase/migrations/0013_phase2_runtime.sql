-- Fase 2 — Estado autoritativo de la partida activa (runtime), constraint para FK,
-- generador de referencia pública del ledger y emisor Broadcast activo.
-- Aplica sobre 0000–0012. No toca propiedades/tablero/otras mecánicas.

-- ── Promoción del índice único TOTAL a CONSTRAINT (destino válido de FK) ──────────
-- players_game_pubref_key es un índice único TOTAL sobre (game_id, public_ref).
-- PostgreSQL no admite un índice como destino de FK; lo promovemos a constraint.
-- NOTA: al adoptar el nombre de la constraint, el índice subyacente pasa a llamarse
-- players_game_pubref_uniq. Ninguna migración/test posterior debe depender del nombre previo.
alter table public.players
  add constraint players_game_pubref_uniq unique using index players_game_pubref_key;

-- ── Referencia pública opaca del ledger: 'L-XXXXXXXXXX' (distinta de 'P-' de jugadores) ──
-- Gestiona colisión: varios intentos, comprueba unicidad por partida y, si se agotan,
-- falla con error saneado. Seguro bajo el bloqueo game_runtime FOR UPDATE (sin escritura
-- concurrente en el mismo juego). Referencia a public.ledger (creada en 0014) en cuerpo diferido.
create or replace function public.gen_ledger_ref(p_game uuid)
returns text language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_ref text; i int;
begin
  for i in 1..10 loop
    v_ref := 'L-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    if not exists (select 1 from public.ledger where game_id = p_game and ledger_ref = v_ref) then
      return v_ref;
    end if;
  end loop;
  raise exception 'LEDGER_REF_EXHAUSTED';
end $$;
revoke all on function public.gen_ledger_ref(uuid) from public, anon, authenticated;

-- ── Estado activo (1:1 con games). current_player_ref NO se almacena: se deriva ──────
create table public.game_runtime (
  game_id          uuid primary key references public.games(id) on delete cascade,
  turn_order_refs  text[] not null,                 -- public_ref[] (NUNCA ids internos)
  turn_index       int    not null default 1,       -- 1-based: current = turn_order_refs[turn_index]
  turn_number      int    not null default 1,       -- monótono; NO se reinicia al cerrar vuelta
  ledger_seq       bigint not null default 0,        -- contador bloqueable (FOR UPDATE) para ledger.seq
  runtime_version  bigint not null default 0,        -- concurrencia optimista del estado ACTIVO
  started_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint game_runtime_order_nonempty check (array_length(turn_order_refs, 1) >= 1),
  constraint game_runtime_index_range    check (turn_index >= 1 and turn_index <= array_length(turn_order_refs, 1))
);

alter table public.game_runtime enable row level security;          -- sin políticas => deny-all directo
revoke all on public.game_runtime from anon, authenticated;

-- ── Emisor Broadcast activo: SOLO { runtime_version } a room:<code> ───────────────
-- Señal de invalidación; el cliente siempre vuelve a pedir get_active_snapshot_by_code.
-- No incluye game_id, saldos, importes, jugadores ni movimientos.
create or replace function public._emit_active_signal(p_game uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_code text; v_ver bigint;
begin
  select g.code, r.runtime_version into v_code, v_ver
  from public.games g join public.game_runtime r on r.game_id = g.id
  where g.id = p_game;
  if v_code is null then return; end if;                 -- partida inexistente/sin runtime: no emitir
  perform realtime.send(jsonb_build_object('runtime_version', v_ver), 'active_state_changed', 'room:' || v_code, true);
end $$;
revoke all on function public._emit_active_signal(uuid) from public, anon, authenticated;
