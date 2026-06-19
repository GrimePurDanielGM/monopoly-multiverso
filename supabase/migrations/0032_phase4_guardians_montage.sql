-- Fase 4 (corrección 3) — Montaje REAL de doble tablero (en cruz) + recolocación de los guardianes.
--
-- Los dos tableros se montan desplazados, haciendo coincidir esquinas OPUESTAS:
--   · Cárcel/Solo-visitas del CLASSIC  ↔  Parking gratuito del RdF
--   · Parking gratuito del CLASSIC     ↔  Cárcel/Solo-visitas del RdF
-- (antes estaba modelado Parking↔Parking; se corrige.)
--
-- Cada guardián vive en la CÁRCEL de su tablero y custodia DOS entradas:
--   · Guardián Classic (cárcel, índice 10): Glorieta de Bilbao (Classic, 11)  o  Parking del RdF (20).
--   · Guardián RdF     (cárcel, índice 10): Autocine Pohatchee (RdF, 11)       o  Parking del Classic (20).
-- Mecánica (se ACTIVA con el motor de cruce entre tableros, fase posterior; aquí se modela y visualiza):
--   pasar por la entrada LIBRE es gratis y el guardián se mueve a custodiar esa entrada; pasar por la
--   entrada CUSTODIADA cuesta el peaje y el guardián se queda. Peaje por defecto 100 (ajustable).

alter table public.board_spaces add column if not exists links_to_index int null;
alter table public.board_spaces add column if not exists guardian_toll int null;

-- Reiniciar guardianes/enlaces previos (estaban en las esquinas de Parking).
update public.board_spaces set guardian = false, links_to_board = null, links_to_index = null, guardian_toll = null;

-- Montaje en cruz (las 4 esquinas que coinciden) + guardián en cada cárcel.
update public.board_spaces set links_to_board='back_to_the_future', links_to_index=20, guardian=true, guardian_toll=100
  where board_key='classic' and space_index=10;            -- cárcel Classic ↔ Parking RdF (guardián Classic)
update public.board_spaces set links_to_board='back_to_the_future', links_to_index=10
  where board_key='classic' and space_index=20;            -- Parking Classic ↔ cárcel RdF
update public.board_spaces set links_to_board='classic', links_to_index=20, guardian=true, guardian_toll=100
  where board_key='back_to_the_future' and space_index=10; -- cárcel RdF ↔ Parking Classic (guardián RdF)
update public.board_spaces set links_to_board='classic', links_to_index=10
  where board_key='back_to_the_future' and space_index=20; -- Parking RdF ↔ cárcel Classic

-- Salvaguarda: exactamente 2 guardianes (uno por cárcel) y 4 esquinas de montaje enlazadas en cruz.
do $$
declare v_g int; v_l int; v_ok boolean;
begin
  select count(*) into v_g from public.board_spaces where guardian and space_type='jail';
  select count(*) into v_l from public.board_spaces where links_to_board is not null;
  select (select links_to_index from public.board_spaces where board_key='classic' and space_index=10)=20
     and (select links_to_index from public.board_spaces where board_key='classic' and space_index=20)=10
     and (select links_to_index from public.board_spaces where board_key='back_to_the_future' and space_index=10)=20
     and (select links_to_index from public.board_spaces where board_key='back_to_the_future' and space_index=20)=10
    into v_ok;
  if v_g <> 2 or v_l <> 4 or not v_ok then raise exception 'GUARDIAN_MONTAGE_BROKEN g=% l=% ok=%', v_g, v_l, v_ok; end if;
end $$;
