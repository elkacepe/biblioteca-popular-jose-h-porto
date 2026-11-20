-- =====================================================================
-- Datos de referencia (de prueba): configuración, categorías, zonas, ubicaciones.
-- =====================================================================
insert into public.config (id) values (true) on conflict do nothing;

insert into public.categorias (nombre, precio_base, color, orden) values
  ('Novela',                    4000, '#21395B', 1),
  ('Policial',                  4000, '#1C1C1C', 2),
  ('Ensayo y política',         4500, '#B23A32', 3),
  ('Historia argentina',        5000, '#2F6B5E', 4),
  ('Poesía',                    3500, '#7A4E8C', 5),
  ('Infantil',                  2500, '#E0A83B', 6),
  ('Juvenil',                   3000, '#C7662B', 7),
  ('Manual escolar',            1500, '#5B6B7A', 8),
  ('Cocina y hobbies',          3000, '#8C6A2F', 9),
  ('Colección de tapa dura',    6000, '#5A1F1B', 10)
on conflict (nombre) do nothing;

-- Reparto de prueba: martes (2) y jueves (4), de 15 a 19.
insert into public.zonas (nombre, dia_semana, hora_inicio, hora_fin) values
  ('Centro',          2, '15:00', '19:00'),
  ('Villa del Lago',  2, '15:00', '19:00'),
  ('Santa Rita',      2, '15:00', '19:00'),
  ('La Cuesta',       4, '15:00', '19:00'),
  ('Playas de Oro',   4, '15:00', '19:00')
on conflict (nombre) do nothing;

insert into public.ubicaciones (codigo, tipo)
select 'Estante ' || l || n, 'estante'::public.tipo_ubicacion
from unnest(array['A', 'B', 'C']) l, generate_series(1, 6) n
on conflict (codigo) do nothing;

insert into public.ubicaciones (codigo, tipo)
select 'Caja de feria ' || n, 'caja_feria'::public.tipo_ubicacion from generate_series(1, 12) n
on conflict (codigo) do nothing;

insert into public.ubicaciones (codigo, tipo) values
  ('Acervo · Sala de lectura', 'acervo'),
  ('Mesa de devoluciones', 'devoluciones'),
  ('Bolsa de reciclado', 'reciclado')
on conflict (codigo) do nothing;
