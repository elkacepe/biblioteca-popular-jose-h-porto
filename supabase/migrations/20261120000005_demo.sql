-- =====================================================================
-- Datos de demostración (sintéticos) y botón «Reiniciar datos».
-- Las fechas se calculan respecto de hoy, así la demo siempre tiene
-- una feria por venir, un martes de reparto y una reserva por vencer.
-- =====================================================================

create or replace function interno.ts(p_fecha date, p_hora time) returns timestamptz
language sql stable as $$ select (p_fecha + p_hora) at time zone (select zona_horaria from public.config where id) $$;

create or replace function interno.u(p_email text) returns uuid
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v uuid;
begin
  select id into v from public.perfiles where email = p_email;
  if v is null then
    raise exception 'Falta la cuenta de prueba %. Ejecutá supabase/seed.sql primero.', p_email;
  end if;
  return v;
end $$;

create or replace function interno.ubic(p_codigo text) returns int
language sql stable security definer set search_path = public, pg_temp
as $$ select id from public.ubicaciones where codigo = p_codigo $$;

create or replace function interno.demo_titulo(p_titulo text, p_autor text, p_editorial text, p_anio int, p_cat text, p_acervo boolean)
returns int
language sql security definer set search_path = public, pg_temp
as $$
  insert into public.titulos (titulo, autor, editorial, anio, categoria_id, en_acervo)
  values (p_titulo, p_autor, p_editorial, p_anio, (select id from public.categorias where nombre = p_cat), p_acervo)
  returning id
$$;

create or replace function interno.demo_ej(p_titulo int, p_lote int, p_ef public.estado_fisico, p_estante text,
  p_dias int, p_estado public.estado_ejemplar default 'En venta') returns uuid
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v uuid; v_sug numeric; v_ubic int; v_fecha timestamptz := now() - make_interval(days => p_dias);
begin
  select interno.precio_sugerido(categoria_id, p_ef) into v_sug from public.titulos where id = p_titulo;
  v_ubic := case p_estado when 'Acervo' then interno.ubic('Acervo · Sala de lectura')
                          when 'Descartado' then interno.ubic('Bolsa de reciclado')
                          else interno.ubic(p_estante) end;
  insert into public.ejemplares (titulo_id, lote_id, estado_fisico, precio_sugerido, precio, estado, ubicacion_id,
    ubicacion_deposito_id, motivo_descarte, destino_reciclado, en_deposito_desde, created_at)
  values (p_titulo, p_lote, p_ef, case when p_estado <> 'Acervo' then v_sug end,
    case when p_estado in ('En venta', 'En clasificación') then v_sug end, p_estado, v_ubic,
    case when p_estado in ('Acervo', 'Descartado') then v_ubic else interno.ubic(p_estante) end,
    case when p_estado = 'Descartado' then 'Hojas sueltas y humedad' end, p_estado = 'Descartado', v_fecha, v_fecha)
  returning id into v;
  insert into public.historial_ejemplar (ejemplar_id, estado_anterior, estado_nuevo, motivo, fecha)
  values (v, null, p_estado, case p_estado when 'Acervo' then 'Primer ejemplar del título: queda en el acervo'
                                           else 'Ingresó por donación' end, v_fecha);
  insert into public.traslados (ejemplar_id, desde_id, hacia_id, motivo, automatico, fecha)
  values (v, null, v_ubic, 'Ingreso por donación', true, v_fecha);
  return v;
end $$;

-- Toma n ejemplares En venta de una categoría (o de cualquiera) que no estén ya usados.
create or replace function interno.demo_tomar(p_n int, p_cat text default null) returns uuid[]
language sql security definer set search_path = public, pg_temp
as $$
  select coalesce(array_agg(id), '{}') from (
    select e.id from public.ejemplares e join public.titulos t on t.id = e.titulo_id
    join public.categorias c on c.id = t.categoria_id
    where e.estado = 'En venta' and (p_cat is null or c.nombre = p_cat) and e.created_at < now() - interval '10 days'
    order by md5(e.id::text) limit p_n) x
$$;

create or replace function interno.demo_venta(p_canal public.canal_venta, p_feria int, p_jornada int, p_pedido int,
  p_comprador uuid, p_medio public.medio_pago, p_fecha timestamptz, p_ids uuid[], p_vendedor uuid,
  p_sale_de_biblioteca boolean default true)
returns int
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_id int; v_socio boolean := false; c public.config := interno.config(); p public.pedidos; x uuid;
        v_sub numeric; v_desc numeric := 0; v_promo numeric := 0; v_total numeric;
begin
  if p_canal = 'web' then
    select * into p from public.pedidos where id = p_pedido;
    insert into public.ventas (canal, pedido_id, comprador_id, es_socio, subtotal, descuento_socio, envio, total, medio_pago, vendedor_id, created_at)
    values ('web', p.id, p.comprador_id, p.es_socio, p.subtotal, p.descuento_socio, p.envio, p.total, p_medio, p_vendedor, p_fecha)
    returning id into v_id;
    insert into public.venta_items (venta_id, ejemplar_id, precio, descuento, precio_final)
    select v_id, ejemplar_id, precio, descuento, precio_final from public.pedido_items where pedido_id = p.id;
    v_total := p.total;
  else
    if p_canal = 'mostrador' and p_comprador is not null then v_socio := interno.es_socio_al_dia(p_comprador); end if;
    if p_canal = 'feria' then
      select sum(precio), sum(case when sin_cargo then precio else 0 end) into v_sub, v_promo from interno.promo_feria(p_ids);
    else
      select sum(precio), sum(case when v_socio then round(precio * c.descuento_socio_pct / 100) else 0 end)
        into v_sub, v_desc from public.ejemplares where id = any(p_ids);
    end if;
    v_total := v_sub - v_desc - v_promo;
    insert into public.ventas (canal, feria_id, jornada_id, comprador_id, es_socio, subtotal, descuento_socio, descuento_promo,
      total, medio_pago, vendedor_id, created_at)
    values (p_canal, p_feria, p_jornada, p_comprador, v_socio, v_sub, v_desc, v_promo, v_total, p_medio, p_vendedor, p_fecha)
    returning id into v_id;
    if p_canal = 'feria' then
      insert into public.venta_items (venta_id, ejemplar_id, precio, descuento, precio_final, promo_sin_cargo)
      select v_id, ejemplar_id, precio, case when sin_cargo then precio else 0 end, case when sin_cargo then 0 else precio end, sin_cargo
      from interno.promo_feria(p_ids);
    else
      insert into public.venta_items (venta_id, ejemplar_id, precio, descuento, precio_final)
      select v_id, id, precio, d, precio - d from public.ejemplares
      cross join lateral (select case when v_socio then round(precio * c.descuento_socio_pct / 100) else 0 end d) z
      where id = any(p_ids);
    end if;
  end if;

  foreach x in array p_ids loop
    update public.ejemplares set estado = 'Vendido', reservado_hasta = null, caja_feria_id = null,
      pedido_id = case when p_canal = 'web' then p_pedido end,
      ubicacion_id = case when p_sale_de_biblioteca then null else ubicacion_id end
    where id = x;
    insert into public.historial_ejemplar (ejemplar_id, estado_anterior, estado_nuevo, usuario_id, motivo, fecha)
    values (x, (case p_canal when 'feria' then 'En feria' when 'web' then 'Reservado' else 'En venta' end)::public.estado_ejemplar, 'Vendido', p_vendedor,
            'Venta ' || p_canal, p_fecha);
    if p_sale_de_biblioteca then
      insert into public.traslados (ejemplar_id, desde_id, hacia_id, usuario_id, motivo, automatico, fecha)
      values (x, null, null, p_vendedor, 'Sale de la biblioteca (venta ' || p_canal || ')', true, p_fecha);
    end if;
  end loop;

  if v_total > 0 then
    insert into public.movimientos_dinero (fecha, canal, tipo, medio, importe, venta_id, feria_id, jornada_id, usuario_id, detalle)
    values (p_fecha, p_canal, 'venta', p_medio, v_total, v_id, p_feria, p_jornada, p_vendedor, 'Venta (demo)');
  end if;
  return v_id;
end $$;

create or replace function interno.demo_pedido(p_comprador uuid, p_modalidad public.modalidad_entrega, p_zona text,
  p_direccion text, p_creado timestamptz, p_ids uuid[]) returns int
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare yo public.perfiles; c public.config := interno.config(); v_socio boolean; v_sub numeric; v_desc numeric; v_env numeric := 0; v_id int;
begin
  select * into yo from public.perfiles where id = p_comprador;
  v_socio := interno.es_socio_al_dia(p_comprador);
  select sum(precio), sum(case when v_socio then round(precio * c.descuento_socio_pct / 100) else 0 end)
    into v_sub, v_desc from public.ejemplares where id = any(p_ids);
  if p_modalidad = 'envio' then
    v_env := case when v_socio and cardinality(p_ids) >= c.envio_gratis_socio_desde then 0 else c.costo_envio end;
  end if;
  insert into public.pedidos (comprador_id, estado, modalidad, zona_id, contacto_nombre, telefono, direccion, es_socio,
    subtotal, descuento_socio, envio, total, reservado_hasta, created_at)
  values (p_comprador, 'Reservado', p_modalidad, (select id from public.zonas where nombre = p_zona), yo.nombre, yo.telefono,
    p_direccion, v_socio, v_sub, v_desc, v_env, v_sub - v_desc + v_env,
    p_creado + make_interval(hours => c.horas_reserva_web), p_creado)
  returning id into v_id;
  insert into public.pedido_items (pedido_id, ejemplar_id, precio, descuento, precio_final)
  select v_id, id, precio, d, precio - d from public.ejemplares
  cross join lateral (select case when v_socio then round(precio * c.descuento_socio_pct / 100) else 0 end d) z
  where id = any(p_ids);
  insert into public.historial_pedido (pedido_id, estado, nota, fecha) values
    (v_id, 'Nuevo', 'Pedido armado en la web', p_creado), (v_id, 'Reservado', 'Reserva de 48 horas', p_creado);
  update public.ejemplares set estado = 'Reservado', pedido_id = v_id,
    reservado_hasta = p_creado + make_interval(hours => c.horas_reserva_web) where id = any(p_ids);
  return v_id;
end $$;

-- Cobra un pedido de la demo en una fecha dada (sin pasar por el mantenimiento).
create or replace function interno.demo_cobrar(p_pedido int, p_fecha timestamptz, p_medio public.medio_pago, p_bibliotecaria uuid)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.demo_venta('web', null, null, p_pedido, null, p_medio, p_fecha,
    array(select ejemplar_id from public.pedido_items where pedido_id = p_pedido), p_bibliotecaria, false);
  update public.pedidos set estado = 'Cobrado', cobrado_en = p_fecha, medio_pago = p_medio, reservado_hasta = null where id = p_pedido;
  insert into public.historial_pedido (pedido_id, estado, usuario_id, nota, fecha)
  values (p_pedido, 'Cobrado', p_bibliotecaria, 'Cobro registrado (' || p_medio || ')', p_fecha);
end $$;

create or replace function interno.demo_entregar(p_pedido int, p_fecha timestamptz) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  update public.pedidos set estado = case when modalidad = 'envio' then 'Entregado' else 'Retirado' end::public.estado_pedido,
    entregado_en = p_fecha where id = p_pedido;
  update public.ejemplares set ubicacion_id = null where pedido_id = p_pedido;
  insert into public.historial_pedido (pedido_id, estado, nota, fecha)
  select p_pedido, estado, 'Entregado', p_fecha from public.pedidos where id = p_pedido;
end $$;

create or replace function interno.cargar_demo() returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare
  hoy date := interno.hoy();
  v_marta uuid := interno.u('marta@porto.test');   v_comision uuid := interno.u('comision@porto.test');
  v_norma uuid := interno.u('norma@porto.test');   v_ruben uuid := interno.u('ruben@porto.test');
  v_julia uuid := interno.u('julia@porto.test');   v_hugo uuid := interno.u('hugo@porto.test');
  v_carla uuid := interno.u('carla@porto.test');   v_elena uuid := interno.u('elena@porto.test');
  v_tomas uuid := interno.u('tomas@porto.test');   v_lucia uuid := interno.u('lucia@porto.test');
  v_centro uuid[];
  l1 int; l2 int; l3 int; l4 int; l5 int;
  t record; i int; n int; v_ej uuid; v_ids uuid[];
  v_prox date; v_feria_prox int; v_feria_oct int; v_feria_sep int; v_caja int;
  v_mar_prox date; v_mar_pas date; v_jue_prox date; r_centro int; r_centro_pas int; r_lago int; r_cuesta int;
  v_ped int; v_j int; v_venta int; v_dev int; d date; k int; v_sofia_item int;
begin
  -- Perfiles de prueba ------------------------------------------------
  update public.perfiles set rol = 'bibliotecaria', nombre = 'Marta Ferreyra', telefono = '3541 400100' where id = v_marta;
  update public.perfiles set rol = 'comision', nombre = 'Ernesto Paz (tesorería)' where id = v_comision;
  update public.perfiles set rol = 'caja', nombre = 'Norma Quiroga', telefono = '3541 400201' where id = v_norma;
  update public.perfiles set rol = 'caja', nombre = 'Rubén Sosa', telefono = '3541 400202' where id = v_ruben;
  update public.perfiles set rol = 'caja', nombre = 'Julia Benítez', telefono = '3541 400203' where id = v_julia;
  update public.perfiles set rol = 'repartidor', nombre = 'Hugo Ledesma', telefono = '3541 400301' where id = v_hugo;
  update public.perfiles set rol = 'repartidor', nombre = 'Carla Moyano', telefono = '3541 400302' where id = v_carla;
  update public.perfiles set rol = 'comprador', nombre = 'Elena Rivarola', telefono = '3541 500101',
    direccion = 'Los Cerezos 145', zona_id = (select id from zonas where nombre = 'Villa del Lago'),
    numero_socio = '1047', cuota_al_dia_hasta = hoy + 40, credito = 0 where id = v_elena;
  update public.perfiles set rol = 'comprador', nombre = 'Tomás Aguirre', telefono = '3541 500102',
    direccion = 'Av. del Lago 2200', zona_id = (select id from zonas where nombre = 'Playas de Oro'),
    numero_socio = '0882', cuota_al_dia_hasta = hoy - 50, credito = 0 where id = v_tomas;
  update public.perfiles set rol = 'comprador', nombre = 'Lucía Peralta', telefono = '3541 500103',
    direccion = 'San Martín 870', zona_id = (select id from zonas where nombre = 'Centro'),
    numero_socio = null, cuota_al_dia_hasta = null, credito = 0 where id = v_lucia;
  v_centro := array[interno.u('raul@porto.test'), interno.u('sofia@porto.test'), interno.u('andres@porto.test'),
                    interno.u('beatriz@porto.test'), interno.u('ines@porto.test'), interno.u('diego@porto.test')];
  update public.perfiles p set rol = 'comprador', zona_id = (select id from zonas where nombre = 'Centro'), credito = 0,
    numero_socio = case when p.email in ('raul@porto.test', 'beatriz@porto.test') then '1' || right(md5(p.email), 3) end,
    cuota_al_dia_hasta = case when p.email in ('raul@porto.test', 'beatriz@porto.test') then hoy + 20 end,
    nombre = case p.email when 'raul@porto.test' then 'Raúl Godoy' when 'sofia@porto.test' then 'Sofía Luna'
      when 'andres@porto.test' then 'Andrés Bustos' when 'beatriz@porto.test' then 'Beatriz Ocampo'
      when 'ines@porto.test' then 'Inés Carrizo' else 'Diego Funes' end,
    telefono = '3541 6' || right('00000' || (abs(hashtext(p.email)) % 100000)::text, 5),
    direccion = case p.email when 'raul@porto.test' then 'Libertad 345' when 'sofia@porto.test' then '9 de Julio 51'
      when 'andres@porto.test' then 'Gral. Paz 1120' when 'beatriz@porto.test' then 'Belgrano 77, dpto. 2'
      when 'ines@porto.test' then 'Sarmiento 610' else 'Uruguay 230' end
  where p.id = any(v_centro);

  -- Lotes de donaciones -------------------------------------------------
  insert into lotes (codigo, procedencia, anonima, estado, recibido_en, recibido_por, observaciones) values
    ('L-2026-001', 'Familia Bustos (mudanza)', false, 'Clasificado', now() - interval '260 days', v_marta, 'Tres cajas grandes'),
    ('L-2026-002', null, true, 'Clasificado', now() - interval '120 days', v_marta, 'Dejadas en la puerta un sábado'),
    ('L-2026-003', 'Colegio San Martín', false, 'Clasificado', now() - interval '45 days', v_marta, 'Manuales y lecturas escolares'),
    ('L-2026-004', 'Vecina de barrio Los Manantiales', false, 'En clasificación', now() - interval '6 days', v_marta, null),
    ('L-2026-005', null, true, 'Recibido', now() - interval '1 day', v_marta, 'Bolsa con policiales');
  select id into l1 from lotes where codigo = 'L-2026-001';
  select id into l2 from lotes where codigo = 'L-2026-002';
  select id into l3 from lotes where codigo = 'L-2026-003';
  select id into l4 from lotes where codigo = 'L-2026-004';
  select id into l5 from lotes where codigo = 'L-2026-005';

  -- Títulos: clásicos de dominio público y títulos sintéticos. -----------------
  -- (titulo, autor, editorial, año, categoría, ya en acervo, copias, estante, lote, días en depósito, estado físico)
  for t in select * from (values
    ('Amalia', 'José Mármol', 'Sopena', 1851, 'Novela', true, 3, 'Estante A1', 1, 250, 'Bueno'),
    ('Don Segundo Sombra', 'Ricardo Güiraldes', 'Losada', 1926, 'Novela', true, 3, 'Estante A1', 1, 240, 'Muy bueno'),
    ('Los siete locos', 'Roberto Arlt', 'Claridad', 1929, 'Novela', true, 2, 'Estante A1', 2, 110, 'Bueno'),
    ('El juguete rabioso', 'Roberto Arlt', 'Claridad', 1926, 'Novela', true, 2, 'Estante A1', 2, 100, 'Regular'),
    ('María', 'Jorge Isaacs', 'Kapelusz', 1867, 'Novela', true, 2, 'Estante A2', 1, 230, 'Bueno'),
    ('Madame Bovary', 'Gustave Flaubert', 'Tor', 1857, 'Novela', true, 2, 'Estante A2', 2, 90, 'Muy bueno'),
    ('Orgullo y prejuicio', 'Jane Austen', 'Tor', 1813, 'Novela', true, 3, 'Estante A2', 2, 80, 'Bueno'),
    ('Crimen y castigo', 'Fiódor Dostoievski', 'Sopena', 1866, 'Novela', true, 2, 'Estante A2', 1, 200, 'Regular'),
    ('Los miserables', 'Victor Hugo', 'Sopena', 1862, 'Novela', true, 1, 'Estante A3', 1, 210, 'Bueno'),
    ('Las tardes del Dique', 'Celina Arrieta', 'Ediciones del Lago', 1998, 'Novela', false, 2, 'Estante A3', 4, 5, 'Muy bueno'),
    ('El sabueso de los Baskerville', 'Arthur Conan Doyle', 'Tor', 1902, 'Policial', true, 3, 'Estante B1', 1, 230, 'Bueno'),
    ('Estudio en escarlata', 'Arthur Conan Doyle', 'Tor', 1887, 'Policial', true, 2, 'Estante B1', 2, 100, 'Muy bueno'),
    ('Los crímenes de la calle Morgue', 'Edgar Allan Poe', 'Acme', 1841, 'Policial', true, 2, 'Estante B1', 2, 95, 'Bueno'),
    ('El misterio del cuarto amarillo', 'Gaston Leroux', 'Acme', 1907, 'Policial', true, 2, 'Estante B1', 1, 190, 'Bueno'),
    ('Muerte en el Dique San Roque', 'Osvaldo Caro', 'Serrana', 2004, 'Policial', true, 3, 'Estante B2', 2, 70, 'Muy bueno'),
    ('El caso de la pensión Las Glicinas', 'Hebe Lucero', 'Serrana', 2011, 'Policial', true, 2, 'Estante B2', 4, 6, 'Bueno'),
    ('La sombra del Cucú', 'Hebe Lucero', 'Serrana', 2015, 'Policial', false, 3, 'Estante B2', 4, 6, 'Muy bueno'),
    ('Facundo', 'Domingo F. Sarmiento', 'Eudeba', 1845, 'Ensayo y política', true, 3, 'Estante B3', 1, 260, 'Bueno'),
    ('Bases', 'Juan Bautista Alberdi', 'Eudeba', 1852, 'Ensayo y política', true, 2, 'Estante B3', 1, 255, 'Regular'),
    ('Las multitudes argentinas', 'José M. Ramos Mejía', 'Eudeba', 1899, 'Ensayo y política', true, 1, 'Estante B3', 2, 100, 'Bueno'),
    ('Crónicas de la cooperativa', 'Aníbal Ferreyra', 'Cuadernos Serranos', 1987, 'Ensayo y política', true, 2, 'Estante B3', 3, 40, 'Muy bueno'),
    ('Recuerdos de provincia', 'Domingo F. Sarmiento', 'Kapelusz', 1850, 'Historia argentina', true, 2, 'Estante B4', 1, 245, 'Bueno'),
    ('Una excursión a los indios ranqueles', 'Lucio V. Mansilla', 'Kapelusz', 1870, 'Historia argentina', true, 2, 'Estante B4', 1, 240, 'Muy bueno'),
    ('Historia de Belgrano', 'Bartolomé Mitre', 'Peuser', 1857, 'Historia argentina', true, 1, 'Estante B4', 2, 110, 'Regular'),
    ('Carlos Paz: cien veranos', 'Raquel Toledo', 'Cuadernos Serranos', 2013, 'Historia argentina', true, 3, 'Estante B4', 3, 40, 'Muy bueno'),
    ('Martín Fierro', 'José Hernández', 'Kapelusz', 1872, 'Poesía', true, 4, 'Estante C1', 1, 250, 'Bueno'),
    ('Fausto', 'Estanislao del Campo', 'Kapelusz', 1866, 'Poesía', true, 2, 'Estante C1', 2, 95, 'Bueno'),
    ('Azul...', 'Rubén Darío', 'Tor', 1888, 'Poesía', true, 2, 'Estante C1', 2, 90, 'Muy bueno'),
    ('Rimas', 'Gustavo Adolfo Bécquer', 'Sopena', 1871, 'Poesía', true, 2, 'Estante C1', 1, 220, 'Regular'),
    ('Versos del lago', 'Amalia Ortiz', 'Ediciones del Lago', 2001, 'Poesía', true, 1, 'Estante C1', 3, 40, 'Muy bueno'),
    ('Cuentos de la selva', 'Horacio Quiroga', 'Losada', 1918, 'Infantil', true, 4, 'Estante C2', 3, 40, 'Bueno'),
    ('Pinocho', 'Carlo Collodi', 'Acme', 1883, 'Infantil', true, 2, 'Estante C2', 2, 85, 'Regular'),
    ('Alicia en el país de las maravillas', 'Lewis Carroll', 'Acme', 1865, 'Infantil', true, 3, 'Estante C2', 1, 200, 'Muy bueno'),
    ('El gato que leía en la plaza', 'Pilar Ruiz', 'Ediciones del Lago', 2019, 'Infantil', true, 2, 'Estante C2', 3, 40, 'Muy bueno'),
    ('La vuelta al mundo en ochenta días', 'Julio Verne', 'Acme', 1872, 'Juvenil', true, 3, 'Estante C3', 1, 215, 'Bueno'),
    ('La isla del tesoro', 'Robert L. Stevenson', 'Acme', 1883, 'Juvenil', true, 2, 'Estante C3', 2, 80, 'Muy bueno'),
    ('Corazón', 'Edmondo De Amicis', 'Kapelusz', 1886, 'Juvenil', true, 2, 'Estante C3', 1, 205, 'Regular'),
    ('Las aventuras de Tom Sawyer', 'Mark Twain', 'Acme', 1876, 'Juvenil', true, 2, 'Estante C3', 2, 75, 'Bueno'),
    ('Matemática 5 · Serie Sierras', 'Equipo Sierras', 'Sierras', 2018, 'Manual escolar', true, 4, 'Estante C4', 3, 40, 'Bueno'),
    ('Lengua y literatura 2', 'Equipo Sierras', 'Sierras', 2017, 'Manual escolar', true, 3, 'Estante C4', 3, 40, 'Regular'),
    ('Geografía de Córdoba', 'Equipo Sierras', 'Sierras', 2016, 'Manual escolar', true, 2, 'Estante C4', 3, 40, 'Bueno'),
    ('Recetario de la abuela serrana', 'Nélida Giménez', 'Cuadernos Serranos', 1994, 'Cocina y hobbies', true, 2, 'Estante C5', 2, 85, 'Bueno'),
    ('Tejido a dos agujas', 'Rosa Medina', 'Hilos', 1989, 'Cocina y hobbies', true, 2, 'Estante C5', 1, 230, 'Regular'),
    ('Huerta en el patio', 'Julián Pereyra', 'Hilos', 2009, 'Cocina y hobbies', true, 2, 'Estante C5', 4, 6, 'Muy bueno'),
    ('Don Quijote de la Mancha', 'Miguel de Cervantes', 'Edición ilustrada', 1605, 'Colección de tapa dura', true, 2, 'Estante C6', 1, 250, 'Muy bueno'),
    ('Las mil y una noches', 'Anónimo', 'Edición ilustrada', 1900, 'Colección de tapa dura', true, 2, 'Estante C6', 1, 245, 'Bueno'),
    ('El matadero y La cautiva', 'Esteban Echeverría', 'Edición ilustrada', 1871, 'Colección de tapa dura', true, 1, 'Estante C6', 2, 100, 'Muy bueno')
  ) x(titulo, autor, editorial, anio, cat, acervo, copias, estante, lote, dias, ef) loop
    i := interno.demo_titulo(t.titulo, t.autor, t.editorial, t.anio, t.cat, t.acervo);
    for n in 1..(t.copias * 2) loop
      v_ej := interno.demo_ej(i, case t.lote when 1 then l1 when 2 then l2 when 3 then l3 else l4 end,
        case when n = 2 and t.ef = 'Muy bueno' then 'Bueno' else t.ef end::public.estado_fisico,
        t.estante, t.dias,
        case when not t.acervo and n = 1 then 'Acervo'
             when t.lote = 4 and n = t.copias * 2 then 'En clasificación'
             else 'En venta' end::public.estado_ejemplar);
    end loop;
    if not t.acervo then update titulos set en_acervo = true where id = i; end if;
  end loop;
  -- Un descarte por mal estado, con destino a reciclado.
  perform interno.demo_ej((select id from titulos where titulo = 'Pinocho'), l2, 'Muy malo', 'Estante C2', 85, 'Descartado');

  -- Ferias --------------------------------------------------------------
  v_prox := hoy + ((7 - extract(isodow from hoy)::int) % 7);                -- este domingo (o hoy si es domingo)
  d := (date_trunc('month', v_prox) - interval '1 month')::date;
  d := d + ((7 - extract(isodow from d)::int) % 7) + 14;                    -- tercer domingo del mes anterior
  insert into ferias (fecha, estado) values (d, 'Cerrada') returning id into v_feria_oct;
  d := (date_trunc('month', v_prox) - interval '2 month')::date;
  d := d + ((7 - extract(isodow from d)::int) % 7) + 14;
  insert into ferias (fecha, estado) values (d, 'Cerrada') returning id into v_feria_sep;
  insert into ferias (fecha, estado) values (v_prox, 'Planificada') returning id into v_feria_prox;

  -- Ferias pasadas: ventas, arqueo y cajas liberadas.
  for k in 1..2 loop
    i := case k when 1 then v_feria_sep else v_feria_oct end;
    select fecha into d from ferias where id = i;
    insert into asignaciones (usuario_id, tipo, feria_id) values (v_norma, 'feria', i), (v_ruben, 'feria', i);
    insert into cajas_feria (feria_id, numero, ubicacion_id, cupo_total, cupo_disponible, activa)
    values (i, 1, interno.ubic('Caja de feria 1'), 40, 40, false), (i, 2, interno.ubic('Caja de feria 2'), 40, 40, false);
    for n in 1..(case k when 1 then 6 else 8 end) loop
      v_ids := interno.demo_tomar(1 + (n % 4));
      perform interno.demo_venta('feria', i, null, null, null,
        case when n % 3 = 0 then 'transferencia' else 'efectivo' end::public.medio_pago,
        interno.ts(d, time '10:05' + make_interval(mins => n * 17)), v_ids, case when n % 2 = 0 then v_ruben else v_norma end);
    end loop;
    insert into arqueos (canal, feria_id, cantidad_ventas, ejemplares_vendidos, efectivo_esperado, efectivo_contado,
      transferencias_registradas, transferencias_informadas, diferencia, motivo_diferencia, ejemplares_devueltos, cerrado_por, cerrado_en)
    select 'feria', i, (select count(*) from ventas where feria_id = i),
      (select count(*) from venta_items vi join ventas v on v.id = vi.venta_id where v.feria_id = i),
      ef, ef + case k when 2 then -500 else 0 end, tr, tr, case k when 2 then -500 else 0 end,
      case k when 2 then 'Faltó cambio al empezar y se redondeó una venta' end, case k when 1 then 31 else 27 end,
      v_norma, interno.ts(d, '13:20')
    from (select coalesce(sum(importe) filter (where medio = 'efectivo'), 0) ef,
                 coalesce(sum(importe) filter (where medio = 'transferencia'), 0) tr
          from movimientos_dinero where feria_id = i) m;
  end loop;

  -- Feria que viene: 3 cajas armadas, Norma y Rubén asignados.
  insert into asignaciones (usuario_id, tipo, feria_id) values (v_norma, 'feria', v_feria_prox), (v_ruben, 'feria', v_feria_prox);
  for k in 1..3 loop
    insert into cajas_feria (feria_id, numero, ubicacion_id, cupo_total, cupo_disponible)
    values (v_feria_prox, k, interno.ubic('Caja de feria ' || (k + 9)), 40, 40) returning id into v_caja;
    v_ids := interno.demo_tomar(case k when 1 then 14 when 2 then 11 else 9 end);
    update ejemplares set estado = 'En feria', caja_feria_id = v_caja,
      ubicacion_id = (select ubicacion_id from cajas_feria where id = v_caja) where id = any(v_ids);
    insert into historial_ejemplar (ejemplar_id, estado_anterior, estado_nuevo, usuario_id, motivo)
    select x, 'En venta', 'En feria', v_marta, 'Armado de caja ' || k from unnest(v_ids) x;
    insert into traslados (ejemplar_id, desde_id, hacia_id, usuario_id, motivo)
    select x, (select ubicacion_deposito_id from ejemplares where id = x), (select ubicacion_id from cajas_feria where id = v_caja),
           v_marta, 'Armado de caja para la feria del ' || to_char(v_prox, 'DD/MM') from unnest(v_ids) x;
    update cajas_feria set cupo_disponible = cupo_total - cardinality(v_ids) where id = v_caja;
  end loop;

  -- Mostrador: jornadas pasadas cerradas; Julia asignada. ------------------
  insert into asignaciones (usuario_id, tipo) values (v_julia, 'mostrador');
  for k in 1..10 loop
    d := hoy - (k * 6);
    if extract(isodow from d) > 5 then d := d - (extract(isodow from d)::int - 5); end if;
    continue when exists (select 1 from jornadas_mostrador where fecha = d);
    insert into jornadas_mostrador (fecha, estado, abierta_por, abierta_en) values (d, 'Cerrada', v_julia, interno.ts(d, '08:35'))
    returning id into v_j;
    for n in 1..(1 + k % 3) loop
      v_ids := interno.demo_tomar(1 + (n % 2));
      perform interno.demo_venta('mostrador', null, v_j, null, case when n = 2 then v_elena end,
        case when n = 3 then 'transferencia' else 'efectivo' end::public.medio_pago,
        interno.ts(d, time '09:10' + make_interval(mins => n * 50)), v_ids, v_julia);
    end loop;
    insert into arqueos (canal, jornada_id, cantidad_ventas, ejemplares_vendidos, efectivo_esperado, efectivo_contado,
      transferencias_registradas, transferencias_informadas, diferencia, cerrado_por, cerrado_en)
    select 'mostrador', v_j, (select count(*) from ventas where jornada_id = v_j),
      (select count(*) from venta_items vi join ventas v on v.id = vi.venta_id where v.jornada_id = v_j),
      ef, ef, tr, tr, 0, v_julia, interno.ts(d, '19:05')
    from (select coalesce(sum(importe) filter (where medio = 'efectivo'), 0) ef,
                 coalesce(sum(importe) filter (where medio = 'transferencia'), 0) tr
          from movimientos_dinero where jornada_id = v_j) m;
  end loop;

  -- Una devolución de mostrador ya aprobada (reintegro en efectivo).
  select v.id into v_venta from ventas v where v.canal = 'mostrador' order by v.created_at desc limit 1;
  select id into i from venta_items where venta_id = v_venta limit 1;
  insert into devoluciones (venta_item_id, venta_id, ejemplar_id, canal, motivo, detalle, defecto_no_informado, forma_reintegro,
    estado, resultado_ejemplar, importe_libro, importe_envio, importe_total, solicitada_por, revisada_por, created_at, resuelta_en)
  select vi.id, v_venta, vi.ejemplar_id, 'mostrador', 'Páginas faltantes o dañadas', 'Faltan las páginas 33 a 40', true, 'efectivo',
    'Aprobada', 'Descartado', vi.precio_final, 0, vi.precio_final, v_marta, v_marta, v.created_at + interval '2 days', v.created_at + interval '2 days'
  from venta_items vi join ventas v on v.id = vi.venta_id where vi.id = i
  returning id into v_dev;
  update venta_items set anulado = true where id = i;
  update ejemplares set estado = 'En devolución' where id = (select ejemplar_id from venta_items where id = i);
  update ejemplares set estado = 'Descartado', motivo_descarte = 'Faltan páginas (devolución)' where id = (select ejemplar_id from venta_items where id = i);
  insert into movimientos_dinero (fecha, canal, tipo, medio, importe, venta_id, devolucion_id, usuario_id, detalle)
  select resuelta_en, 'mostrador', 'reintegro', 'efectivo', -importe_total, venta_id, id, v_marta, 'Devolución #' || id
  from devoluciones where id = v_dev;

  -- Reparto ---------------------------------------------------------------
  perform interno.asegurar_recorridos();
  v_mar_prox := hoy + ((2 - extract(isodow from hoy)::int + 7) % 7);
  v_mar_pas := v_mar_prox - 7;
  v_jue_prox := hoy + ((4 - extract(isodow from hoy)::int + 7) % 7);
  insert into recorridos (zona_id, fecha, hora_inicio, hora_fin, cupo_total, cupo_disponible, repartidor_id, estado)
  values ((select id from zonas where nombre = 'Centro'), v_mar_pas, '15:00', '19:00', 12, 12, v_hugo, 'Finalizado')
  on conflict (zona_id, fecha) do update set repartidor_id = v_hugo, estado = 'Finalizado'
  returning id into r_centro_pas;
  select id into r_centro from recorridos where zona_id = (select id from zonas where nombre = 'Centro') and fecha = v_mar_prox;
  select id into r_lago from recorridos where zona_id = (select id from zonas where nombre = 'Villa del Lago') and fecha = v_mar_prox;
  select id into r_cuesta from recorridos where zona_id = (select id from zonas where nombre = 'La Cuesta') and fecha = v_jue_prox;
  update recorridos set repartidor_id = v_hugo
   where fecha between hoy and hoy + 14 and zona_id in (select id from zonas where dia_semana = 2);
  update recorridos set repartidor_id = v_carla
   where fecha between hoy and hoy + 14 and zona_id in (select id from zonas where dia_semana = 4);

  -- Martes pasado, zona Centro: 4 entregas, 3 entregadas y 1 fallida «No había nadie».
  for k in 1..4 loop
    v_ped := interno.demo_pedido(v_centro[k], 'envio', 'Centro',
      (select direccion from perfiles where id = v_centro[k]), interno.ts(v_mar_pas - 3, '20:15'), interno.demo_tomar(1 + k % 2));
    perform interno.demo_cobrar(v_ped, interno.ts(v_mar_pas - 2, '10:00'), 'transferencia', v_marta);
    update pedidos set estado = 'En reparto' where id = v_ped;
    insert into entregas (recorrido_id, pedido_id, intento, resultado, motivo, marcado_por, marcado_en)
    values (r_centro_pas, v_ped, 1, case when k = 4 then 'No entregada' else 'Entregada' end::resultado_entrega,
      case when k = 4 then 'No había nadie' end, v_hugo, interno.ts(v_mar_pas, time '15:20' + make_interval(mins => k * 25)));
    update recorridos set cupo_disponible = cupo_disponible - 1 where id = r_centro_pas;
    if k < 4 then
      perform interno.demo_entregar(v_ped, interno.ts(v_mar_pas, time '15:20' + make_interval(mins => k * 25)));
      if k = 2 then  -- Sofía pide devolver un libro con páginas faltantes
        select vi.id into v_sofia_item from venta_items vi join ventas v on v.id = vi.venta_id where v.pedido_id = v_ped limit 1;
      end if;
    else
      -- Primera falla: queda para el martes que viene.
      update pedidos set estado = 'Preparado', intentos_fallidos = 1 where id = v_ped;
      insert into historial_pedido (pedido_id, estado, nota, fecha)
      values (v_ped, 'Preparado', 'No se pudo entregar: No había nadie. Reprogramado.', interno.ts(v_mar_pas, '17:00'));
      insert into entregas (recorrido_id, pedido_id, intento) values (r_centro, v_ped, 2);
      update pedidos set recorrido_id = r_centro where id = v_ped;
      update recorridos set cupo_disponible = cupo_disponible - 1 where id = r_centro;
    end if;
  end loop;

  -- Martes que viene, zona Centro: 9 entregas en total (1 reprogramada + 8 nuevas). Quedan 3 lugares.
  for k in 1..8 loop
    v_ped := interno.demo_pedido(case when k <= 6 then v_centro[k] when k = 7 then v_lucia else v_centro[1] end, 'envio', 'Centro',
      case when k = 7 then 'San Martín 870' else (select direccion from perfiles where id = v_centro[least(k, 6)]) end,
      now() - make_interval(hours => 30 + k), interno.demo_tomar(1 + k % 3));
    perform interno.demo_cobrar(v_ped, now() - make_interval(hours => 20 + k),
      case when k % 2 = 0 then 'efectivo' else 'transferencia' end::medio_pago, v_marta);
    if k % 3 <> 0 then update pedidos set estado = 'Preparado' where id = v_ped; end if;
    insert into entregas (recorrido_id, pedido_id, intento) values (r_centro, v_ped, 1);
    update pedidos set recorrido_id = r_centro where id = v_ped;
    update recorridos set cupo_disponible = cupo_disponible - 1 where id = r_centro;
  end loop;

  -- Villa del Lago: pedido de Elena (socia, 4 libros: envío sin cargo) cobrado y asignado.
  v_ped := interno.demo_pedido(v_elena, 'envio', 'Villa del Lago', 'Los Cerezos 145', now() - interval '26 hours', interno.demo_tomar(4));
  perform interno.demo_cobrar(v_ped, now() - interval '22 hours', 'transferencia', v_marta);
  insert into entregas (recorrido_id, pedido_id, intento) values (r_lago, v_ped, 1);
  update pedidos set recorrido_id = r_lago where id = v_ped;
  update recorridos set cupo_disponible = cupo_disponible - 1 where id = r_lago;

  -- La Cuesta (jueves): un pedido para Carla.
  v_ped := interno.demo_pedido(v_centro[3], 'envio', 'La Cuesta', 'Los Aromos 12, La Cuesta', now() - interval '40 hours', interno.demo_tomar(2));
  perform interno.demo_cobrar(v_ped, now() - interval '30 hours', 'efectivo', v_marta);
  update pedidos set estado = 'Preparado' where id = v_ped;
  insert into entregas (recorrido_id, pedido_id, intento) values (r_cuesta, v_ped, 1);
  update pedidos set recorrido_id = r_cuesta where id = v_ped;
  update recorridos set cupo_disponible = cupo_disponible - 1 where id = r_cuesta;

  -- Tomás: dos entregas fallidas, ahora «Retiro en biblioteca» desde hace 5 días.
  v_ped := interno.demo_pedido(v_tomas, 'envio', 'Playas de Oro', 'Av. del Lago 2200', now() - interval '20 days', interno.demo_tomar(2, 'Policial'));
  perform interno.demo_cobrar(v_ped, now() - interval '19 days', 'efectivo', v_marta);
  insert into recorridos (zona_id, fecha, hora_inicio, hora_fin, cupo_total, cupo_disponible, repartidor_id, estado)
  values ((select id from zonas where nombre = 'Playas de Oro'), v_jue_prox - 14, '15:00', '19:00', 12, 11, v_carla, 'Finalizado'),
         ((select id from zonas where nombre = 'Playas de Oro'), v_jue_prox - 7, '15:00', '19:00', 12, 11, v_carla, 'Finalizado')
  on conflict (zona_id, fecha) do nothing;
  insert into entregas (recorrido_id, pedido_id, intento, resultado, motivo, marcado_por, marcado_en)
  select r.id, v_ped, row_number() over (order by r.fecha), 'No entregada',
         case when r.fecha = v_jue_prox - 14 then 'No había nadie' else 'Dirección incompleta' end, v_carla, interno.ts(r.fecha, '16:30')
  from recorridos r where r.zona_id = (select id from zonas where nombre = 'Playas de Oro') and r.fecha in (v_jue_prox - 14, v_jue_prox - 7);
  update pedidos set estado = 'Retiro en biblioteca', intentos_fallidos = 2, retiro_desde = now() - interval '5 days' where id = v_ped;
  insert into historial_pedido (pedido_id, estado, nota, fecha)
  values (v_ped, 'Retiro en biblioteca', 'Segunda entrega fallida: queda para retirar en la biblioteca', now() - interval '5 days');

  -- Reservas web sin cobrar: la de Lucía ya pasó las 48 h (se cancela sola en la primera consulta); la de Elena es reciente.
  v_ped := interno.demo_pedido(v_lucia, 'retiro', null, null, now() - interval '49 hours', interno.demo_tomar(2, 'Novela'));
  v_ped := interno.demo_pedido(v_elena, 'retiro', null, null, now() - interval '3 hours', interno.demo_tomar(1, 'Historia argentina'));

  -- Ventas web de meses anteriores (para los informes).
  for k in 1..8 loop
    d := hoy - (20 + k * 11);
    v_ped := interno.demo_pedido(case when k % 2 = 0 then v_elena else v_centro[1 + k % 6] end,
      case when k % 3 = 0 then 'retiro' else 'envio' end::modalidad_entrega,
      case when k % 3 = 0 then null when k % 2 = 0 then 'Villa del Lago' else 'Centro' end,
      case when k % 3 = 0 then null else 'Dirección de prueba ' || k end, interno.ts(d, '19:00'), interno.demo_tomar(1 + k % 3));
    perform interno.demo_cobrar(v_ped, interno.ts(d + 1, '10:00'), case when k % 2 = 0 then 'transferencia' else 'efectivo' end::medio_pago, v_marta);
    perform interno.demo_entregar(v_ped, interno.ts(d + 3, '16:00'));
  end loop;

  -- Devolución pedida por Sofía (web, dentro de los 7 días): espera revisión.
  insert into devoluciones (venta_item_id, venta_id, ejemplar_id, canal, comprador_id, motivo, detalle, defecto_no_informado,
    forma_reintegro, solicitada_por, created_at)
  select vi.id, vi.venta_id, vi.ejemplar_id, 'web', v.comprador_id, 'Páginas faltantes o dañadas',
         'Le faltan las últimas páginas', true, 'credito', v.comprador_id, now() - interval '1 day'
  from venta_items vi join ventas v on v.id = vi.venta_id where vi.id = v_sofia_item;
end $$;

-- Reinicio de la demo (solo bibliotecaria). Las cuentas de Auth no se tocan.
create or replace function public.reiniciar_demo()
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria');
  perform set_config('porto.reinicio', 'on', true);
  truncate public.operaciones, public.movimientos_credito, public.movimientos_dinero, public.devoluciones, public.arqueos,
    public.venta_items, public.ventas, public.entregas, public.historial_pedido, public.pedido_items,
    public.historial_ejemplar, public.traslados, public.ejemplares, public.pedidos, public.recorridos,
    public.cajas_feria, public.asignaciones, public.ferias, public.jornadas_mostrador, public.lotes, public.titulos
    restart identity cascade;
  alter sequence public.ejemplar_codigo_seq restart with 1001;
  alter sequence public.pedido_numero_seq restart with 501;
  alter sequence public.venta_numero_seq restart with 1;
  update public.config set permitir_fuera_de_horario = true where id;
  perform interno.cargar_demo();
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.reiniciar_demo() from public, anon;
grant execute on function public.reiniciar_demo() to authenticated;
revoke all on all functions in schema interno from public, anon, authenticated;
grant execute on function interno.es_staff(), interno.mis_ferias(), interno.atiendo_mostrador(),
  interno.mis_recorridos(), interno.mis_pedidos_reparto() to authenticated;
