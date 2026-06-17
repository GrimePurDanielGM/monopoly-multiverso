-- Evita cuelgues indefinidos: realtime.messages es una tabla muy activa en el proyecto
-- alojado; si CREATE POLICY no consigue el lock pronto, falla rápido en vez de bloquear.
set lock_timeout = '10s';

-- Fase 1 — Realtime del lobby por BROADCAST PRIVADO desde la BD (no Postgres Changes).
-- Los triggers emiten SOLO una señal de invalidación { game_id } al topic privado room:<CODE>.
-- El cliente, al recibir cualquier evento, vuelve a llamar a get_lobby_snapshot. El broadcast
-- nunca transporta filas ni datos internos. Canales privados autorizados por RLS sobre
-- realtime.messages: solo miembros activos reciben; los clientes solo pueden hacer Presence,
-- nunca emitir broadcast (no pueden suplantar eventos oficiales). API verificada: realtime.send.

-- ---------- Helper de autorización (por CÓDIGO de partida; usado por las políticas de realtime) ----------
create or replace function public.is_active_member_by_code(p_code text)
returns boolean language sql security definer set search_path = public, pg_temp stable as $$
  select exists (
    select 1
    from public.players p
    join public.games  g on g.id = p.game_id
    where g.code = upper(btrim(p_code))
      and p.auth_uid = auth.uid()
      and p.kicked_at is null
  )
$$;
revoke execute on function public.is_active_member_by_code(text) from public;
grant  execute on function public.is_active_member_by_code(text) to authenticated;

-- ---------- Emisión de la señal mínima ----------
create or replace function public._emit_lobby_signal(p_game uuid, p_event text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_code text;
begin
  select code into v_code from public.games where id = p_game;
  if v_code is null then return; end if;                 -- partida inexistente (p. ej. cascade): no emitir
  perform realtime.send(jsonb_build_object('game_id', p_game), p_event, 'room:' || v_code, true);
end $$;

-- ---------- Triggers: players ----------
create or replace function public._trg_players_lobby()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._emit_lobby_signal(coalesce(NEW.game_id, OLD.game_id), 'lobby_changed');
  return null;
end $$;

create trigger players_lobby_ins_del after insert or delete on public.players
  for each row execute function public._trg_players_lobby();

-- En UPDATE solo señaliza cambios RELEVANTES (excluye heartbeat/last_seen_at para evitar tormentas).
create trigger players_lobby_upd after update on public.players
  for each row when (
       OLD.display_name is distinct from NEW.display_name
    or OLD.token_id     is distinct from NEW.token_id
    or OLD.join_status  is distinct from NEW.join_status
    or OLD.kicked_at    is distinct from NEW.kicked_at
  ) execute function public._trg_players_lobby();

-- ---------- Triggers: games (status -> evento específico; resto -> lobby_changed) ----------
create or replace function public._trg_games_lobby()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if    NEW.status = 'active'    and OLD.status <> 'active'    then perform public._emit_lobby_signal(NEW.id, 'game_started');
  elsif NEW.status = 'cancelled' and OLD.status <> 'cancelled' then perform public._emit_lobby_signal(NEW.id, 'game_cancelled');
  else  perform public._emit_lobby_signal(NEW.id, 'lobby_changed');
  end if;
  return null;
end $$;

-- Excluye los UPDATE que solo tocan audit_seq (de _audit) para no duplicar señales.
create trigger games_lobby_signal after update on public.games
  for each row when (
       OLD.status         is distinct from NEW.status
    or OLD.config         is distinct from NEW.config
    or OLD.version        is distinct from NEW.version
    or OLD.name           is distinct from NEW.name
    or OLD.host_player_id is distinct from NEW.host_player_id
  ) execute function public._trg_games_lobby();

-- ---------- Triggers: solicitudes -> recovery_requested ----------
create or replace function public._trg_request_signal()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._emit_lobby_signal(NEW.game_id, 'recovery_requested');
  return null;
end $$;

create trigger recovery_req_signal after insert on public.player_recovery_requests
  for each row execute function public._trg_request_signal();
create trigger reentry_req_signal after insert on public.player_reentry_requests
  for each row execute function public._trg_request_signal();

-- ---------- Autorización de canales privados (RLS sobre realtime.messages) ----------
-- realtime.messages ya tiene RLS habilitada (deny-all por defecto).
-- SELECT: un miembro ACTIVO de room:<CODE> recibe broadcast y presence de SU sala.
create policy "lobby members can receive" on realtime.messages
  for select to authenticated
  using (
        realtime.topic() like 'room:%'
    and extension in ('broadcast','presence')
    and public.is_active_member_by_code(split_part(realtime.topic(), ':', 2))
  );

-- INSERT: el cliente SOLO puede Presence (extension='presence'); NUNCA broadcast.
-- Los eventos oficiales los emiten los triggers como 'postgres' (saltan RLS). Así un cliente
-- no puede suplantar lobby_changed/game_started/etc. ni escuchar/emitir en salas ajenas.
create policy "lobby members can presence only" on realtime.messages
  for insert to authenticated
  with check (
        realtime.topic() like 'room:%'
    and extension = 'presence'
    and public.is_active_member_by_code(split_part(realtime.topic(), ':', 2))
  );
