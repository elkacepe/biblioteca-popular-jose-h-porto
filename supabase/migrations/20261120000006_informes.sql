-- =====================================================================
-- Informes (bibliotecaria y comisión directiva, solo lectura).
-- Todo sale del libro de movimientos y de las tablas de ventas: los informes
-- coinciden por construcción con lo que se registró. Fechas en hora de Córdoba.
-- =====================================================================

create or replace function interno.fecha_local(p_ts timestamptz) returns date
language sql stable security definer set search_path = public, pg_temp
as $$ select (p_ts at time zone (select zona_horaria from public.config where id))::date $$;

create or replace function public.informe_recaudacion(p_desde date default null, p_hasta date default null,
  p_canal public.canal_venta default null)
returns table (canal public.canal_venta, mes text, feria_id int, feria text, ventas bigint,
               ingresos numeric, reintegros numeric, neto numeric, efectivo numeric, transferencias numeric)
language plpgsql stable security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria', 'comision');
  return query
  select m.canal, to_char(interno.fecha_local(m.fecha), 'YYYY-MM'), m.feria_id,
         case when m.feria_id is not null then 'Feria del ' || to_char(f.fecha, 'DD/MM/YYYY') end,
         count(*) filter (where m.tipo = 'venta'),
         coalesce(sum(m.importe) filter (where m.tipo = 'venta'), 0),
         coalesce(-sum(m.importe) filter (where m.tipo = 'reintegro'), 0),
         sum(m.importe),
         coalesce(sum(m.importe) filter (where m.medio = 'efectivo'), 0),
         coalesce(sum(m.importe) filter (where m.medio = 'transferencia'), 0)
  from public.movimientos_dinero m
  left join public.ferias f on f.id = m.feria_id
  where (p_desde is null or interno.fecha_local(m.fecha) >= p_desde)
    and (p_hasta is null or interno.fecha_local(m.fecha) <= p_hasta)
    and (p_canal is null or m.canal = p_canal)
  group by m.canal, to_char(interno.fecha_local(m.fecha), 'YYYY-MM'), m.feria_id, f.fecha
  order by 2 desc, 1, 4;
end $$;

create or replace function public.informe_movimientos(p_desde date default null, p_hasta date default null,
  p_canal public.canal_venta default null)
returns table (id bigint, fecha timestamptz, canal public.canal_venta, tipo text, medio public.medio_pago,
               importe numeric, referencia text, usuario text)
language plpgsql stable security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria', 'comision');
  return query
  select m.id, m.fecha, m.canal, m.tipo, m.medio, m.importe,
         coalesce('Venta #' || v.numero, '') || coalesce(' · Pedido #' || p.numero, '') || coalesce(' · Devolución #' || m.devolucion_id, ''),
         u.nombre
  from public.movimientos_dinero m
  left join public.ventas v on v.id = m.venta_id
  left join public.pedidos p on p.id = v.pedido_id
  left join public.perfiles u on u.id = m.usuario_id
  where (p_desde is null or interno.fecha_local(m.fecha) >= p_desde)
    and (p_hasta is null or interno.fecha_local(m.fecha) <= p_hasta)
    and (p_canal is null or m.canal = p_canal)
  order by m.fecha desc;
end $$;

create or replace function public.informe_mas_vendidos(p_desde date default null, p_hasta date default null,
  p_canal public.canal_venta default null, p_por text default 'titulo')
returns table (nombre text, categoria text, cantidad bigint, importe numeric)
language plpgsql stable security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria', 'comision');
  return query
  select case when p_por = 'categoria' then c.nombre else t.titulo || ' — ' || t.autor end,
         c.nombre, count(*), sum(i.precio_final)
  from public.venta_items i
  join public.ventas v on v.id = i.venta_id
  join public.ejemplares e on e.id = i.ejemplar_id
  join public.titulos t on t.id = e.titulo_id
  join public.categorias c on c.id = t.categoria_id
  where not i.anulado
    and (p_desde is null or interno.fecha_local(v.created_at) >= p_desde)
    and (p_hasta is null or interno.fecha_local(v.created_at) <= p_hasta)
    and (p_canal is null or v.canal = p_canal)
  group by 1, 2
  order by 3 desc, 4 desc;
end $$;

create or replace function public.informe_devoluciones(p_desde date default null, p_hasta date default null,
  p_canal public.canal_venta default null)
returns table (motivo text, canal public.canal_venta, estado public.estado_devolucion, cantidad bigint,
               reintegrado_efectivo numeric, reintegrado_credito numeric)
language plpgsql stable security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria', 'comision');
  return query
  select d.motivo, d.canal, d.estado, count(*),
         coalesce(sum(d.importe_total) filter (where d.estado = 'Aprobada' and d.forma_reintegro = 'efectivo'), 0),
         coalesce(sum(d.importe_total) filter (where d.estado = 'Aprobada' and d.forma_reintegro = 'credito'), 0)
  from public.devoluciones d
  where (p_desde is null or interno.fecha_local(d.created_at) >= p_desde)
    and (p_hasta is null or interno.fecha_local(d.created_at) <= p_hasta)
    and (p_canal is null or d.canal = p_canal)
  group by 1, 2, 3 order by 4 desc;
end $$;

create or replace function public.informe_entregas_fallidas(p_desde date default null, p_hasta date default null)
returns table (fecha date, zona text, pedido int, intento smallint, motivo text, repartidor text, estado_actual public.estado_pedido)
language plpgsql stable security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria', 'comision');
  return query
  select r.fecha, z.nombre, p.numero, e.intento, e.motivo, u.nombre, p.estado
  from public.entregas e
  join public.recorridos r on r.id = e.recorrido_id
  join public.zonas z on z.id = r.zona_id
  join public.pedidos p on p.id = e.pedido_id
  left join public.perfiles u on u.id = e.marcado_por
  where e.resultado = 'No entregada'
    and (p_desde is null or r.fecha >= p_desde) and (p_hasta is null or r.fecha <= p_hasta)
  order by r.fecha desc;
end $$;

create or replace function public.informe_antiguedad(p_dias int default 180)
returns table (codigo text, titulo text, categoria text, estado public.estado_ejemplar, ubicacion text, precio numeric, dias int)
language plpgsql stable security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria', 'comision');
  return query
  select e.codigo, t.titulo, c.nombre, e.estado, u.codigo, e.precio, (interno.hoy() - interno.fecha_local(e.en_deposito_desde))::int
  from public.ejemplares e
  join public.titulos t on t.id = e.titulo_id
  join public.categorias c on c.id = t.categoria_id
  left join public.ubicaciones u on u.id = e.ubicacion_id
  where e.estado in ('En venta', 'En clasificación')
    and interno.fecha_local(e.en_deposito_desde) <= interno.hoy() - p_dias
  order by 7 desc;
end $$;

revoke execute on function public.informe_recaudacion(date, date, public.canal_venta), public.informe_movimientos(date, date, public.canal_venta),
  public.informe_mas_vendidos(date, date, public.canal_venta, text), public.informe_devoluciones(date, date, public.canal_venta),
  public.informe_entregas_fallidas(date, date), public.informe_antiguedad(int) from public, anon;
grant execute on function public.informe_recaudacion(date, date, public.canal_venta), public.informe_movimientos(date, date, public.canal_venta),
  public.informe_mas_vendidos(date, date, public.canal_venta, text), public.informe_devoluciones(date, date, public.canal_venta),
  public.informe_entregas_fallidas(date, date), public.informe_antiguedad(int) to authenticated;
revoke all on function interno.fecha_local(timestamptz) from public, anon, authenticated;
