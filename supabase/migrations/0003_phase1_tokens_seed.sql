-- Fase 1 — Catálogo PROVISIONAL de fichas (20, todas activas). catalog_version = 0.
insert into public.token_catalog (id, label, icon, sort_order) values
  ('delorean','DeLorean','car',1),
  ('hoverboard','Hoverboard','board',2),
  ('flux_capacitor','Condensador de flujo','bolt',3),
  ('plutonium_case','Maletín de plutonio','radioactive',4),
  ('clock_tower','Torre del reloj','clock',5),
  ('sports_almanac','Almanaque deportivo','book',6),
  ('time_train','Tren del tiempo','train',7),
  ('guitar','Guitarra','guitar',8),
  ('mr_fusion','Mr. Fusión','battery',9),
  ('einstein_dog','Einstein','dog',10),
  ('self_lacing_shoe','Zapatilla autoajustable','shoe',11),
  ('cowboy_hat','Sombrero vaquero','hat-cowboy',12),
  ('top_hat','Sombrero de copa','hat-top',13),
  ('roadster','Coche clásico','car-classic',14),
  ('thimble','Dedal','thimble',15),
  ('boot','Bota','boot',16),
  ('scottie_dog','Perro','dog-scottie',17),
  ('battleship','Acorazado','ship',18),
  ('wheelbarrow','Carretilla','wheelbarrow',19),
  ('cat','Gato','cat',20)
on conflict (id) do nothing;
