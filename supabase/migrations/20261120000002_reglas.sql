-- =====================================================================
-- Reglas de negocio. TODA operación que cambia estado, stock (ejemplares),
-- cupo (cajas y recorridos) o saldo (dinero y crédito) pasa por acá:
-- una función = una transacción. Se bloquean las filas (FOR UPDATE),
-- se valida el estado actual y, si una regla falla, se lanza una excepción
-- y no queda ningún cambio parcial.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Auxiliares internos (no expuestos por la API)
-- ---------------------------------------------------------------------
create or replace function interno.config() returns public.config
language sql stable security definer set search_path = public, pg_temp
as $$ select * from public.config where id $$;

create or replace function interno.ahora_local() returns timestamp
language sql stable security definer set search_path = public, pg_temp
as $$ select (now() at time zone (select zona_horaria from public.config where id)) $$;

create or replace function interno.hoy() returns date
language sql stable as $$ select interno.ahora_local()::date $$;

create or replace function interno.rol() returns public.rol_usuario
language sql stable security definer set search_path = public, pg_temp
as $$ select rol from public.perfiles where id = auth.uid() $$;

-- Errores con formato que entiende la app: hint = 'conflicto' | 'regla' | 'permiso'
create or replace function interno.conflicto(p_mensaje text, p_detalle jsonb default '{}'::jsonb) returns void
language plpgsql as $$
begin
  raise exception using errcode = 'P0001', message = p_mensaje, detail = p_detalle::text, hint = 'conflicto';
end $$;

create or replace function interno.regla(p_mensaje text) returns void
language plpgsql as $$
begin
  raise exception using errcode = 'P0001', message = p_mensaje, hint = 'regla';
end $$;

create or replace function interno.exigir_rol(variadic p_roles public.rol_usuario[]) returns public.rol_usuario
language plpgsql stable security definer set search_path = public, interno, pg_temp
as $$
declare v public.rol_usuario := interno.rol();
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Tenés que ingresar con tu cuenta.', hint = 'permiso';
  end if;
  if v is null or not (v = any(p_roles)) then
    raise exception using errcode = '42501', message = 'Tu cuenta no tiene permiso para esta acción.', hint = 'permiso';
  end if;
  return v;
end $$;

-- Idempotencia --------------------------------------------------------
create or replace function interno.idem_previo(p_clave uuid, p_funcion text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v jsonb;
begin
  if p_clave is null then return null; end if;
  -- Serializa confirmaciones repetidas con la misma clave.
  perform pg_advisory_xact_lock(hashtextextended(p_clave::text, 0));
  select resultado into v from public.operaciones where clave = p_clave and funcion = p_funcion;
  if v is not null then
    return v || jsonb_build_object('repetida', true);
  end if;
  return null;
end $$;

create or replace function interno.idem_guardar(p_clave uuid, p_funcion text, p_resultado jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if p_clave is not null then
    insert into public.operaciones (clave, funcion, usuario_id, resultado)
    values (p_clave, p_funcion, auth.uid(), p_resultado)
    on conflict (clave) do nothing;
  end if;
  return p_resultado;
end $$;

-- Precio sugerido: base de categoría × multiplicador de estado, redondeado a la centena.
create or replace function interno.precio_sugerido(p_categoria smallint, p_estado public.estado_fisico) returns numeric
language sql stable security definer set search_path = public, pg_temp
as $$
  select round(c.precio_base * case p_estado
           when 'Muy bueno' then 1.0 when 'Bueno' then 0.8 when 'Regular' then 0.5 else 0 end / 100) * 100
  from public.categorias c where c.id = p_categoria
$$;

create or replace function interno.es_socio_al_dia(p_perfil uuid) returns boolean
language sql stable security definer set search_path = public, interno, pg_temp
as $$
  select coalesce((select numero_socio is not null and cuota_al_dia_hasta >= interno.hoy()
                   from public.perfiles where id = p_perfil), false)
$$;

-- Transiciones válidas del ejemplar (segunda red de seguridad, a nivel de tabla).
create or replace function interno.transicion_valida(p_de public.estado_ejemplar, p_a public.estado_ejemplar) returns boolean
language sql immutable as $$
  select p_de = p_a or (p_de, p_a) in (
    ('En clasificación', 'En venta'), ('En clasificación', 'Descartado'),
    ('Acervo', 'Descartado'),
    ('En venta', 'Reservado'), ('En venta', 'En feria'), ('En venta', 'Vendido'), ('En venta', 'Descartado'),
    ('En venta', 'En clasificación'),
    ('Reservado', 'En venta'), ('Reservado', 'Vendido'),
    ('En feria', 'En venta'), ('En feria', 'Vendido'),
    ('Vendido', 'En devolución'), ('Vendido', 'En venta'),
    ('En devolución', 'En venta'), ('En devolución', 'Descartado'), ('En devolución', 'Vendido'))
$$;

create or replace function interno.tg_ejemplar_guardia() returns trigger
language plpgsql as $$
begin
  if new.estado is distinct from old.estado and not interno.transicion_valida(old.estado, new.estado) then
    raise exception using errcode = 'P0001',
      message = format('El ejemplar %s no puede pasar de «%s» a «%s».', old.codigo, old.estado, new.estado),
      hint = 'regla';
  end if;
  new.updated_at := now();
  return new;
end $$;

create trigger ejemplares_guardia before update on public.ejemplares
for each row execute function interno.tg_ejemplar_guardia();

-- La rendición cerrada es inmutable salvo la nota de la bibliotecaria.
create or replace function interno.tg_arqueo_bloqueado() returns trigger
language plpgsql as $$
begin
  if old.bloqueado and (
     new.efectivo_esperado, new.efectivo_contado, new.transferencias_registradas, new.transferencias_informadas,
     new.diferencia, new.motivo_diferencia, new.cantidad_ventas, new.ejemplares_vendidos, new.cerrado_en, new.bloqueado)
     is distinct from (
     old.efectivo_esperado, old.efectivo_contado, old.transferencias_registradas, old.transferencias_informadas,
     old.diferencia, old.motivo_diferencia, old.cantidad_ventas, old.ejemplares_vendidos, old.cerrado_en, old.bloqueado) then
    raise exception using errcode = 'P0001', message = 'La rendición está cerrada: solo se puede agregar una nota.', hint = 'regla';
  end if;
  return new;
end $$;

create trigger arqueos_bloqueo before update on public.arqueos
for each row execute function interno.tg_arqueo_bloqueado();

create or replace function interno.tg_arqueo_no_borrar() returns trigger
language plpgsql as $$
begin
  raise exception using errcode = 'P0001', message = 'Las rendiciones no se borran.', hint = 'regla';
end $$;

create trigger arqueos_no_borrar before delete on public.arqueos
for each row when (current_setting('porto.reinicio', true) is distinct from 'on')
execute function interno.tg_arqueo_no_borrar();

-- Cambio de estado con historial (el llamador ya bloqueó y validó la fila).
create or replace function interno.mover(p_ejemplar uuid, p_nuevo public.estado_ejemplar, p_motivo text) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_ant public.estado_ejemplar;
begin
  select estado into v_ant from public.ejemplares where id = p_ejemplar;
  if v_ant is distinct from p_nuevo then
    update public.ejemplares set estado = p_nuevo where id = p_ejemplar;
    insert into public.historial_ejemplar (ejemplar_id, estado_anterior, estado_nuevo, usuario_id, motivo)
    values (p_ejemplar, v_ant, p_nuevo, auth.uid(), p_motivo);
  end if;
end $$;

-- Traslado con registro (usuario, fecha, motivo).
create or replace function interno.trasladar(p_ejemplar uuid, p_hacia int, p_motivo text, p_auto boolean default false) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_desde int;
begin
  select ubicacion_id into v_desde from public.ejemplares where id = p_ejemplar;
  if v_desde is distinct from p_hacia then
    update public.ejemplares set ubicacion_id = p_hacia where id = p_ejemplar;
    insert into public.traslados (ejemplar_id, desde_id, hacia_id, usuario_id, motivo, automatico)
    values (p_ejemplar, v_desde, p_hacia, auth.uid(), p_motivo, p_auto);
  end if;
end $$;

-- Bloquea un conjunto de ejemplares en orden fijo (evita interbloqueos) y
-- devuelve los que NO están en el estado esperado.
create or replace function interno.bloquear_ejemplares(p_ids uuid[], p_estado public.estado_ejemplar)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_conflictos jsonb;
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    perform interno.regla('No elegiste ningún libro.');
  end if;
  if (select count(distinct x) from unnest(p_ids) x) <> cardinality(p_ids) then
    perform interno.regla('Hay un libro repetido en la lista.');
  end if;
  perform 1 from public.ejemplares where id = any(p_ids) order by id for update;
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'codigo', e.codigo, 'titulo', t.titulo, 'estado', e.estado)), '[]'::jsonb)
    into v_conflictos
  from public.ejemplares e join public.titulos t on t.id = e.titulo_id
  where e.id = any(p_ids) and e.estado <> p_estado;
  if (select count(*) from public.ejemplares where id = any(p_ids)) <> cardinality(p_ids) then
    perform interno.regla('Algún libro de la lista no existe.');
  end if;
  return v_conflictos;
end $$;

create or replace function interno.mensaje_conflicto(p_conflictos jsonb) returns text
language sql immutable as $$
  select case when jsonb_array_length(p_conflictos) = 1
    then format('Este libro ya encontró dueño: «%s» (%s) ya no está disponible.',
                p_conflictos->0->>'titulo', p_conflictos->0->>'codigo')
    else format('%s libros ya encontraron dueño: %s.', jsonb_array_length(p_conflictos),
                (select string_agg(format('«%s» (%s)', x->>'titulo', x->>'codigo'), ', ') from jsonb_array_elements(p_conflictos) x))
  end
$$;

-- Horarios (se omiten en modo prueba).
create or replace function interno.validar_horario_mostrador() returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare t timestamp := interno.ahora_local();
begin
  if (interno.config()).permitir_fuera_de_horario then return; end if;
  if extract(isodow from t) > 5
     or not ((t::time between '08:30' and '12:00') or (t::time between '15:00' and '19:00')) then
    perform interno.regla('El mostrador atiende de lunes a viernes, de 8:30 a 12 y de 15 a 19.');
  end if;
end $$;

create or replace function interno.validar_horario_feria(p_feria int) returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare f public.ferias; t timestamp := interno.ahora_local();
begin
  if (interno.config()).permitir_fuera_de_horario then return; end if;
  select * into f from public.ferias where id = p_feria;
  if t::date <> f.fecha or t::time not between f.hora_inicio and f.hora_fin then
    perform interno.regla(format('La feria funciona el %s de %s a %s.', to_char(f.fecha, 'DD/MM'),
      to_char(f.hora_inicio, 'HH24:MI'), to_char(f.hora_fin, 'HH24:MI')));
  end if;
end $$;

create or replace function interno.puede_operar_feria(p_feria int) returns boolean
language sql stable security definer set search_path = public, interno, pg_temp
as $$
  select interno.rol() = 'bibliotecaria'
      or (interno.rol() = 'caja' and exists (
            select 1 from public.asignaciones a
            where a.usuario_id = auth.uid() and a.tipo = 'feria' and a.feria_id = p_feria))
$$;

create or replace function interno.puede_operar_mostrador() returns boolean
language sql stable security definer set search_path = public, interno, pg_temp
as $$
  select interno.rol() = 'bibliotecaria'
      or (interno.rol() = 'caja' and exists (
            select 1 from public.asignaciones a where a.usuario_id = auth.uid() and a.tipo = 'mostrador'))
$$;

create or replace function interno.historial_pedido(p_pedido int, p_estado public.estado_pedido, p_nota text) returns void
language sql security definer set search_path = public, pg_temp
as $$
  insert into public.historial_pedido (pedido_id, estado, usuario_id, nota) values (p_pedido, p_estado, auth.uid(), p_nota)
$$;

-- ---------------------------------------------------------------------
-- Reparto: recorridos de las próximas dos semanas y asignación con cupo
-- ---------------------------------------------------------------------
create or replace function interno.asegurar_recorridos() returns void
language sql security definer set search_path = public, interno, pg_temp
as $$
  insert into public.recorridos (zona_id, fecha, hora_inicio, hora_fin, cupo_total, cupo_disponible)
  select z.id, d::date, z.hora_inicio, z.hora_fin, c.cupo_recorrido, c.cupo_recorrido
  from public.zonas z
  cross join public.config c
  cross join generate_series(interno.hoy(), interno.hoy() + 14, interval '1 day') d
  where extract(isodow from d) = z.dia_semana
  on conflict (zona_id, fecha) do nothing
$$;

-- Asigna el pedido al próximo recorrido de su zona con cupo, posterior a p_despues_de
-- y cuyo cierre (12 h del día anterior) no haya pasado. Devuelve null si no hay lugar.
create or replace function interno.asignar_recorrido(p_pedido int, p_despues_de date default null) returns int
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_zona smallint; v_rec int; v_ok int; v_intento smallint; i int;
begin
  perform interno.asegurar_recorridos();
  select zona_id, intentos_fallidos + 1 into v_zona, v_intento from public.pedidos where id = p_pedido;
  for i in 1..20 loop
    select r.id into v_rec
    from public.recorridos r
    where r.zona_id = v_zona and r.estado = 'Programado' and r.cupo_disponible > 0
      and (p_despues_de is null or r.fecha > p_despues_de)
      and ((r.fecha - 1) + time '12:00') > interno.ahora_local()
      and not exists (select 1 from public.entregas e where e.recorrido_id = r.id and e.pedido_id = p_pedido)
    order by r.fecha
    limit 1;
    if v_rec is null then return null; end if;
    -- El cupo baja en la misma sentencia que lo verifica: nunca queda negativo.
    update public.recorridos set cupo_disponible = cupo_disponible - 1
    where id = v_rec and cupo_disponible > 0
    returning id into v_ok;
    if v_ok is not null then
      insert into public.entregas (recorrido_id, pedido_id, intento) values (v_ok, p_pedido, v_intento);
      update public.pedidos set recorrido_id = v_ok where id = p_pedido;
      return v_ok;
    end if;
  end loop;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Cancelaciones internas
-- ---------------------------------------------------------------------
-- Pedido reservado sin cobrar: libera los ejemplares y devuelve el crédito usado.
create or replace function interno.cancelar_reserva(p_pedido int, p_motivo text) returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare p public.pedidos; e record;
begin
  select * into p from public.pedidos where id = p_pedido for update;
  if p.estado not in ('Nuevo', 'Reservado') then return; end if;
  for e in select id from public.ejemplares where pedido_id = p_pedido and estado = 'Reservado' order by id for update loop
    perform interno.mover(e.id, 'En venta', p_motivo);
    update public.ejemplares set pedido_id = null, reservado_hasta = null where id = e.id;
  end loop;
  if p.credito_usado > 0 then
    update public.perfiles set credito = credito + p.credito_usado where id = p.comprador_id;
    insert into public.movimientos_credito (perfil_id, importe, motivo, pedido_id)
    values (p.comprador_id, p.credito_usado, 'Se devuelve el crédito de un pedido cancelado', p_pedido);
  end if;
  update public.pedidos set estado = 'Cancelado', cancelado_motivo = p_motivo where id = p_pedido;
  perform interno.historial_pedido(p_pedido, 'Cancelado', p_motivo);
end $$;

-- Pedido cobrado que nunca se retiró (15 días): cancela, los ejemplares vuelven a la venta
-- y lo pagado por los libros queda como crédito (el envío no se devuelve).
create or replace function interno.cancelar_retiro_vencido(p_pedido int) returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare p public.pedidos; e record; v_venta int; v_credito numeric := 0;
begin
  select * into p from public.pedidos where id = p_pedido for update;
  if p.estado <> 'Retiro en biblioteca' then return; end if;
  select id into v_venta from public.ventas where pedido_id = p_pedido;
  for e in select x.id, x.ubicacion_deposito_id from public.ejemplares x
           where x.pedido_id = p_pedido and x.estado = 'Vendido' order by x.id for update loop
    perform interno.mover(e.id, 'En venta', 'Pedido no retirado en 15 días');
    perform interno.trasladar(e.id, e.ubicacion_deposito_id, 'Vuelve al depósito: pedido no retirado', true);
    update public.ejemplares set pedido_id = null where id = e.id;
    update public.venta_items set anulado = true where venta_id = v_venta and ejemplar_id = e.id
      returning v_credito + precio_final into v_credito;
  end loop;
  if v_credito > 0 then
    update public.perfiles set credito = credito + v_credito where id = p.comprador_id;
    insert into public.movimientos_credito (perfil_id, importe, motivo, pedido_id, venta_id)
    values (p.comprador_id, v_credito, 'Pedido no retirado: lo pagado por los libros queda como crédito', p_pedido, v_venta);
  end if;
  update public.pedidos set estado = 'Cancelado', cancelado_motivo = 'Pasaron 15 días sin retirarlo' where id = p_pedido;
  perform interno.historial_pedido(p_pedido, 'Cancelado', 'Pasaron 15 días sin retirarlo en la biblioteca');
end $$;

-- Mantenimiento perezoso: se ejecuta al principio de cada operación y de cada
-- consulta del catálogo. Así no hace falta ninguna tarea programada.
create or replace function interno.mantenimiento() returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare r record; c public.config := interno.config();
begin
  for r in select id from public.pedidos
           where estado in ('Nuevo', 'Reservado') and reservado_hasta < now()
           for update skip locked loop
    perform interno.cancelar_reserva(r.id, format('La reserva venció: pasaron %s horas sin registrar el cobro', c.horas_reserva_web));
  end loop;
  for r in select id from public.pedidos
           where estado = 'Retiro en biblioteca' and retiro_desde < now() - make_interval(days => c.dias_retiro)
           for update skip locked loop
    perform interno.cancelar_retiro_vencido(r.id);
  end loop;
  perform interno.asegurar_recorridos();
end $$;

-- =====================================================================
-- API pública (anónimos y compradores)
-- =====================================================================

-- Catálogo público: solo ejemplares En venta y solo campos públicos.
create or replace function public.catalogo_publico(
  p_busqueda text default null, p_categoria smallint default null,
  p_limite int default 24, p_desde int default 0)
returns table (
  id uuid, codigo text, titulo text, autor text, editorial text, anio smallint,
  categoria_id smallint, categoria text, categoria_color text,
  estado_fisico public.estado_fisico, precio numeric, precio_socio numeric, total bigint)
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_pct numeric := (interno.config()).descuento_socio_pct;
begin
  perform interno.mantenimiento();
  return query
  select e.id, e.codigo, t.titulo, t.autor, coalesce(e.editorial, t.editorial), coalesce(e.anio, t.anio),
         c.id, c.nombre, c.color, e.estado_fisico, e.precio,
         e.precio - round(e.precio * v_pct / 100), count(*) over ()
  from public.ejemplares e
  join public.titulos t on t.id = e.titulo_id
  join public.categorias c on c.id = t.categoria_id
  where e.estado = 'En venta'
    and (p_categoria is null or c.id = p_categoria)
    and (p_busqueda is null or p_busqueda = ''
         or t.titulo ilike '%' || p_busqueda || '%' or t.autor ilike '%' || p_busqueda || '%'
         or e.codigo ilike p_busqueda)
  order by t.titulo, e.precio
  limit least(greatest(p_limite, 1), 100) offset greatest(p_desde, 0);
end $$;

-- Estado público de un ejemplar: disponible o no (sin revelar dónde está ni por qué).
create or replace function public.ejemplar_publico(p_id uuid)
returns table (
  id uuid, codigo text, titulo text, autor text, editorial text, anio smallint,
  categoria text, categoria_color text, estado_fisico public.estado_fisico,
  precio numeric, precio_socio numeric, disponible boolean, otros_disponibles bigint)
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_pct numeric := (interno.config()).descuento_socio_pct;
begin
  perform interno.mantenimiento();
  return query
  select e.id, e.codigo, t.titulo, t.autor, coalesce(e.editorial, t.editorial), coalesce(e.anio, t.anio),
         c.nombre, c.color, e.estado_fisico,
         case when e.estado = 'En venta' then e.precio end,
         case when e.estado = 'En venta' then e.precio - round(e.precio * v_pct / 100) end,
         e.estado = 'En venta',
         (select count(*) from public.ejemplares o where o.titulo_id = e.titulo_id and o.estado = 'En venta' and o.id <> e.id)
  from public.ejemplares e
  join public.titulos t on t.id = e.titulo_id
  join public.categorias c on c.id = t.categoria_id
  where e.id = p_id and e.estado not in ('En clasificación', 'Acervo', 'Descartado');
end $$;

-- Disponibilidad de una lista (para el carrito).
create or replace function public.disponibilidad(p_ids uuid[])
returns table (id uuid, disponible boolean, precio numeric)
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.mantenimiento();
  return query select e.id, e.estado = 'En venta', case when e.estado = 'En venta' then e.precio end
  from public.ejemplares e where e.id = any(p_ids);
end $$;

create or replace function public.ferias_publicas()
returns table (id int, fecha date, lugar text, hora_inicio time, hora_fin time, estado public.estado_feria)
language sql stable security definer set search_path = public, interno, pg_temp
as $$
  select f.id, f.fecha, f.lugar, f.hora_inicio, f.hora_fin, f.estado
  from public.ferias f where f.fecha >= interno.hoy() - 60 order by f.fecha
$$;

-- Próximo recorrido con lugar en una zona (para mostrar «Quedan 3 lugares…»).
create or replace function public.proximo_recorrido(p_zona smallint)
returns table (fecha date, hora_inicio time, hora_fin time, cupo_disponible int, cierre timestamp)
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.asegurar_recorridos();
  return query
  select r.fecha, r.hora_inicio, r.hora_fin, r.cupo_disponible, (r.fecha - 1) + time '12:00'
  from public.recorridos r
  where r.zona_id = p_zona and r.estado = 'Programado' and r.cupo_disponible > 0
    and ((r.fecha - 1) + time '12:00') > interno.ahora_local()
  order by r.fecha limit 1;
end $$;

-- Cotización exacta de un pedido web, calculada por la base.
create or replace function public.cotizar_pedido(p_ejemplares uuid[], p_modalidad public.modalidad_entrega)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare
  c public.config := interno.config();
  v_socio boolean := interno.es_socio_al_dia(auth.uid());
  v_sub numeric; v_desc numeric; v_n int; v_envio numeric := 0; v_cred numeric := 0; v_total numeric;
  v_no jsonb;
begin
  perform interno.mantenimiento();
  select coalesce(sum(precio), 0),
         coalesce(sum(case when v_socio then round(precio * c.descuento_socio_pct / 100) else 0 end), 0),
         count(*)
    into v_sub, v_desc, v_n
  from public.ejemplares where id = any(p_ejemplares) and estado = 'En venta';
  select coalesce(jsonb_agg(e.id), '[]') into v_no from public.ejemplares e
   where e.id = any(p_ejemplares) and e.estado <> 'En venta';
  if p_modalidad = 'envio' and v_n > 0 then
    v_envio := case when v_socio and v_n >= c.envio_gratis_socio_desde then 0 else c.costo_envio end;
  end if;
  if auth.uid() is not null then
    select least(credito, v_sub - v_desc + v_envio) into v_cred from public.perfiles where id = auth.uid();
  end if;
  v_total := v_sub - v_desc + v_envio - coalesce(v_cred, 0);
  return jsonb_build_object('es_socio', v_socio, 'cantidad', v_n, 'subtotal', v_sub, 'descuento_socio', v_desc,
    'envio', v_envio, 'credito', coalesce(v_cred, 0), 'total', v_total, 'no_disponibles', v_no);
end $$;

-- Pedido web: reserva los ejemplares por 48 h. Todo o nada.
create or replace function public.crear_pedido(
  p_ejemplares uuid[], p_modalidad public.modalidad_entrega, p_zona smallint default null,
  p_direccion text default null, p_telefono text default null, p_contacto text default null,
  p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare
  c public.config := interno.config();
  yo public.perfiles;
  v_prev jsonb; v_conf jsonb; v_socio boolean; v_pedido public.pedidos;
  v_sub numeric; v_desc numeric; v_n int; v_envio numeric := 0; v_cred numeric; v_hasta timestamptz;
begin
  perform interno.exigir_rol('comprador');
  v_prev := interno.idem_previo(p_idem, 'crear_pedido');
  if v_prev is not null then return v_prev; end if;
  perform interno.mantenimiento();

  if p_modalidad = 'envio' then
    if p_zona is null or coalesce(trim(p_direccion), '') = '' then
      perform interno.regla('Para el envío necesitamos la zona y la dirección.');
    end if;
  end if;

  v_conf := interno.bloquear_ejemplares(p_ejemplares, 'En venta');
  if jsonb_array_length(v_conf) > 0 then
    perform interno.conflicto(interno.mensaje_conflicto(v_conf), jsonb_build_object('ejemplares', v_conf));
  end if;

  select * into yo from public.perfiles where id = auth.uid() for update;
  v_socio := interno.es_socio_al_dia(yo.id);
  v_n := cardinality(p_ejemplares);
  select sum(precio), sum(case when v_socio then round(precio * c.descuento_socio_pct / 100) else 0 end)
    into v_sub, v_desc from public.ejemplares where id = any(p_ejemplares);
  if p_modalidad = 'envio' then
    v_envio := case when v_socio and v_n >= c.envio_gratis_socio_desde then 0 else c.costo_envio end;
  end if;
  v_cred := least(yo.credito, v_sub - v_desc + v_envio);
  v_hasta := now() + make_interval(hours => c.horas_reserva_web);

  insert into public.pedidos (comprador_id, estado, modalidad, zona_id, contacto_nombre, telefono, direccion, es_socio,
    subtotal, descuento_socio, envio, credito_usado, total, reservado_hasta)
  values (yo.id, 'Nuevo', p_modalidad, case when p_modalidad = 'envio' then p_zona end,
    coalesce(nullif(trim(p_contacto), ''), yo.nombre), coalesce(nullif(trim(p_telefono), ''), yo.telefono),
    case when p_modalidad = 'envio' then trim(p_direccion) end, v_socio,
    v_sub, v_desc, v_envio, v_cred, v_sub - v_desc + v_envio - v_cred, v_hasta)
  returning * into v_pedido;
  perform interno.historial_pedido(v_pedido.id, 'Nuevo', 'Pedido armado en la web');

  insert into public.pedido_items (pedido_id, ejemplar_id, precio, descuento, precio_final)
  select v_pedido.id, e.id, e.precio, d.descuento, e.precio - d.descuento
  from public.ejemplares e
  cross join lateral (select case when v_socio then round(e.precio * c.descuento_socio_pct / 100) else 0 end as descuento) d
  where e.id = any(p_ejemplares);

  update public.ejemplares set pedido_id = v_pedido.id, reservado_hasta = v_hasta where id = any(p_ejemplares);
  perform interno.mover(x, 'Reservado', format('Reserva web, pedido #%s', v_pedido.numero)) from unnest(p_ejemplares) x;

  if v_cred > 0 then
    update public.perfiles set credito = credito - v_cred where id = yo.id;
    insert into public.movimientos_credito (perfil_id, importe, motivo, pedido_id)
    values (yo.id, -v_cred, 'Crédito usado en el pedido', v_pedido.id);
  end if;

  update public.pedidos set estado = 'Reservado' where id = v_pedido.id;
  perform interno.historial_pedido(v_pedido.id, 'Reservado', format('Reservado hasta %s', to_char(v_hasta at time zone c.zona_horaria, 'DD/MM HH24:MI')));

  return interno.idem_guardar(p_idem, 'crear_pedido', jsonb_build_object(
    'pedido_id', v_pedido.id, 'numero', v_pedido.numero, 'total', v_sub - v_desc + v_envio - v_cred,
    'reservado_hasta', v_hasta));
end $$;

create or replace function public.cancelar_mi_pedido(p_pedido int)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare p public.pedidos;
begin
  perform interno.exigir_rol('comprador');
  select * into p from public.pedidos where id = p_pedido and comprador_id = auth.uid() for update;
  if p.id is null then perform interno.regla('No encontramos ese pedido.'); end if;
  if p.estado = 'Cancelado' then return jsonb_build_object('ok', true, 'repetida', true); end if;
  if p.estado <> 'Reservado' then
    perform interno.conflicto('Este pedido ya se cobró: para cancelarlo hablá con la biblioteca.');
  end if;
  perform interno.cancelar_reserva(p_pedido, 'Cancelado por la persona compradora');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.actualizar_mi_perfil(p_nombre text, p_telefono text, p_direccion text, p_zona smallint)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  if auth.uid() is null then perform interno.regla('Tenés que ingresar con tu cuenta.'); end if;
  update public.perfiles
     set nombre = coalesce(nullif(trim(p_nombre), ''), nombre), telefono = nullif(trim(p_telefono), ''),
         direccion = nullif(trim(p_direccion), ''), zona_id = p_zona
   where id = auth.uid();
end $$;

-- =====================================================================
-- Donaciones y depósito (bibliotecaria)
-- =====================================================================
create or replace function public.crear_lote(p_procedencia text, p_anonima boolean, p_observaciones text default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v public.lotes; v_n int;
begin
  perform interno.exigir_rol('bibliotecaria');
  select count(*) + 1 into v_n from public.lotes;
  insert into public.lotes (codigo, procedencia, anonima, observaciones, recibido_por)
  values (format('L-%s-%s', to_char(interno.hoy(), 'YYYY'), lpad(v_n::text, 3, '0')),
          case when p_anonima then null else nullif(trim(p_procedencia), '') end,
          coalesce(p_anonima, false) or coalesce(trim(p_procedencia), '') = '', nullif(trim(p_observaciones), ''), auth.uid())
  returning * into v;
  return to_jsonb(v);
end $$;

create or replace function public.cambiar_estado_lote(p_lote int, p_estado public.estado_lote)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria');
  if p_estado = 'Clasificado' and exists (
      select 1 from public.ejemplares where lote_id = p_lote and estado = 'En clasificación') then
    perform interno.regla('Todavía hay ejemplares de este lote esperando precio o destino.');
  end if;
  update public.lotes set estado = p_estado where id = p_lote;
end $$;

-- Carga de un ejemplar. Regla central: si el título no está en el acervo, el primer
-- ejemplar en condiciones va al Acervo y no se vende. Los siguientes quedan habilitados.
create or replace function public.cargar_ejemplar(
  p_lote int, p_titulo text, p_autor text, p_editorial text, p_anio smallint, p_categoria smallint,
  p_estado_fisico public.estado_fisico, p_ubicacion int default null,
  p_motivo_descarte text default null, p_reciclado boolean default false, p_observaciones text default null,
  p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare
  v_prev jsonb; v_tit public.titulos; v_lote public.lotes; v_ej public.ejemplares;
  v_estado public.estado_ejemplar; v_ubic int; v_destino text; v_sug numeric;
begin
  perform interno.exigir_rol('bibliotecaria');
  v_prev := interno.idem_previo(p_idem, 'cargar_ejemplar');
  if v_prev is not null then return v_prev; end if;

  select * into v_lote from public.lotes where id = p_lote for update;
  if v_lote.id is null then perform interno.regla('Ese lote no existe.'); end if;
  if v_lote.estado = 'Clasificado' then perform interno.regla('El lote ya está clasificado y cerrado.'); end if;
  if coalesce(trim(p_titulo), '') = '' then perform interno.regla('Falta el título.'); end if;

  -- Título: se busca por título+autor normalizados; si no existe se crea.
  insert into public.titulos (titulo, autor, editorial, anio, categoria_id)
  values (trim(p_titulo), coalesce(nullif(trim(p_autor), ''), 'Anónimo'), nullif(trim(p_editorial), ''), p_anio, p_categoria)
  on conflict (clave) do nothing;
  select * into v_tit from public.titulos
   where clave = lower(trim(p_titulo)) || '|' || lower(coalesce(nullif(trim(p_autor), ''), 'Anónimo'))
   for update;  -- serializa dos cargas simultáneas del mismo título

  if p_estado_fisico = 'Muy malo' then
    if coalesce(trim(p_motivo_descarte), '') = '' then
      perform interno.regla('Para descartar un ejemplar en muy mal estado, anotá el motivo.');
    end if;
    v_estado := 'Descartado'; v_destino := 'descartado';
    v_ubic := case when p_reciclado then (select id from public.ubicaciones where tipo = 'reciclado' limit 1) end;
  elsif not v_tit.en_acervo then
    v_estado := 'Acervo'; v_destino := 'acervo';
    v_ubic := (select id from public.ubicaciones where tipo = 'acervo' limit 1);
    update public.titulos set en_acervo = true where id = v_tit.id;
  else
    v_estado := 'En clasificación'; v_destino := 'venta';
    v_ubic := coalesce(p_ubicacion, (select id from public.ubicaciones where tipo = 'estante' order by codigo limit 1));
    v_sug := interno.precio_sugerido(v_tit.categoria_id, p_estado_fisico);
  end if;

  insert into public.ejemplares (titulo_id, lote_id, editorial, anio, estado_fisico, precio_sugerido, precio, estado,
    ubicacion_id, ubicacion_deposito_id, motivo_descarte, destino_reciclado, observaciones)
  values (v_tit.id, p_lote, nullif(trim(p_editorial), ''), p_anio, p_estado_fisico, v_sug, v_sug, v_estado,
    v_ubic, v_ubic, case when v_estado = 'Descartado' then trim(p_motivo_descarte) end,
    v_estado = 'Descartado' and coalesce(p_reciclado, false), nullif(trim(p_observaciones), ''))
  returning * into v_ej;

  insert into public.historial_ejemplar (ejemplar_id, estado_anterior, estado_nuevo, usuario_id, motivo)
  values (v_ej.id, null, v_estado, auth.uid(), case v_destino
    when 'acervo' then 'Primer ejemplar del título: queda en el acervo de la biblioteca'
    when 'descartado' then 'Descartado al clasificar: ' || trim(p_motivo_descarte)
    else 'Ingresó desde el lote ' || v_lote.codigo end);
  if v_ubic is not null then
    insert into public.traslados (ejemplar_id, desde_id, hacia_id, usuario_id, motivo, automatico)
    values (v_ej.id, null, v_ubic, auth.uid(), 'Ingreso por donación (' || v_lote.codigo || ')', true);
  end if;

  if v_lote.estado = 'Recibido' then
    update public.lotes set estado = 'En clasificación' where id = p_lote;
  end if;

  return interno.idem_guardar(p_idem, 'cargar_ejemplar', jsonb_build_object(
    'id', v_ej.id, 'codigo', v_ej.codigo, 'estado', v_estado, 'destino', v_destino,
    'precio_sugerido', v_sug, 'titulo', v_tit.titulo));
end $$;

create or replace function public.publicar_ejemplar(p_ejemplar uuid, p_precio numeric)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare e public.ejemplares;
begin
  perform interno.exigir_rol('bibliotecaria');
  select * into e from public.ejemplares where id = p_ejemplar for update;
  if e.id is null then perform interno.regla('Ese ejemplar no existe.'); end if;
  if e.estado = 'Acervo' then
    perform interno.regla('Este ejemplar es del acervo de la biblioteca: no se pone en venta.');
  end if;
  if e.estado = 'En venta' then return jsonb_build_object('ok', true, 'repetida', true); end if;
  if e.estado <> 'En clasificación' then
    perform interno.conflicto(format('El ejemplar está «%s»: solo se publica uno en clasificación.', e.estado));
  end if;
  if p_precio is null or p_precio <= 0 then perform interno.regla('Poné un precio mayor a cero.'); end if;
  update public.ejemplares set precio = round(p_precio), en_deposito_desde = now() where id = p_ejemplar;
  perform interno.mover(p_ejemplar, 'En venta', format('Publicado a $%s', round(p_precio)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.cambiar_precio(p_ejemplar uuid, p_precio numeric)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare e public.ejemplares;
begin
  perform interno.exigir_rol('bibliotecaria');
  select * into e from public.ejemplares where id = p_ejemplar for update;
  if e.estado not in ('En clasificación', 'En venta') then
    perform interno.conflicto(format('El ejemplar está «%s»: ya no se le cambia el precio.', e.estado));
  end if;
  if p_precio is null or p_precio <= 0 then perform interno.regla('Poné un precio mayor a cero.'); end if;
  update public.ejemplares set precio = round(p_precio) where id = p_ejemplar;
end $$;

create or replace function public.descartar_ejemplar(p_ejemplar uuid, p_motivo text, p_reciclado boolean default false)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare e public.ejemplares;
begin
  perform interno.exigir_rol('bibliotecaria');
  if coalesce(trim(p_motivo), '') = '' then perform interno.regla('Anotá el motivo del descarte.'); end if;
  select * into e from public.ejemplares where id = p_ejemplar for update;
  if e.estado = 'Descartado' then return; end if;
  if e.estado not in ('En clasificación', 'En venta', 'Acervo', 'En devolución') then
    perform interno.conflicto(format('El ejemplar está «%s»: no se puede descartar ahora.', e.estado));
  end if;
  update public.ejemplares set motivo_descarte = trim(p_motivo), destino_reciclado = coalesce(p_reciclado, false) where id = p_ejemplar;
  perform interno.mover(p_ejemplar, 'Descartado', trim(p_motivo));
  perform interno.trasladar(p_ejemplar,
    case when p_reciclado then (select id from public.ubicaciones where tipo = 'reciclado' limit 1) end,
    'Descarte: ' || trim(p_motivo));
end $$;

create or replace function public.trasladar_ejemplar(p_ejemplar uuid, p_ubicacion int, p_motivo text)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare e public.ejemplares; u public.ubicaciones;
begin
  perform interno.exigir_rol('bibliotecaria');
  if coalesce(trim(p_motivo), '') = '' then perform interno.regla('Anotá el motivo del traslado.'); end if;
  select * into e from public.ejemplares where id = p_ejemplar for update;
  select * into u from public.ubicaciones where id = p_ubicacion;
  if u.id is null or u.tipo <> 'estante' then
    perform interno.regla('Los traslados manuales son entre estantes. Para la feria, usá el armado de cajas.');
  end if;
  if e.estado not in ('En clasificación', 'En venta', 'Reservado', 'Vendido') or (e.estado = 'Vendido' and e.ubicacion_id is null) then
    perform interno.conflicto(format('El ejemplar está «%s»: no está en un estante.', e.estado));
  end if;
  perform interno.trasladar(p_ejemplar, p_ubicacion, trim(p_motivo));
  update public.ejemplares set ubicacion_deposito_id = p_ubicacion where id = p_ejemplar;
end $$;

-- =====================================================================
-- Ferias
-- =====================================================================
create or replace function public.crear_feria(p_fecha date, p_lugar text default 'Plazoleta del Reloj Cucú',
  p_hora_inicio time default '10:00', p_hora_fin time default '13:00')
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare f public.ferias;
begin
  perform interno.exigir_rol('bibliotecaria');
  if extract(isodow from p_fecha) <> 7 then perform interno.regla('Las ferias son los domingos.'); end if;
  if p_fecha < interno.hoy() then perform interno.regla('La fecha ya pasó.'); end if;
  if exists (select 1 from public.ferias where date_trunc('month', fecha) = date_trunc('month', p_fecha)) then
    perform interno.regla('Ya hay una feria ese mes: se hace una por mes.');
  end if;
  insert into public.ferias (fecha, lugar, hora_inicio, hora_fin)
  values (p_fecha, coalesce(nullif(trim(p_lugar), ''), 'Plazoleta del Reloj Cucú'), p_hora_inicio, p_hora_fin)
  returning * into f;
  return to_jsonb(f);
end $$;

create or replace function public.crear_caja_feria(p_feria int, p_ubicacion int default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare f public.ferias; c public.config := interno.config(); v_n int; v_ubic int; v_caja public.cajas_feria;
begin
  perform interno.exigir_rol('bibliotecaria');
  select * into f from public.ferias where id = p_feria for update;
  if f.estado = 'Cerrada' then perform interno.regla('La feria ya cerró.'); end if;
  select count(*) into v_n from public.cajas_feria where feria_id = p_feria;
  if v_n >= c.max_cajas_feria then
    perform interno.regla(format('Una feria lleva hasta %s cajas.', c.max_cajas_feria));
  end if;
  v_ubic := coalesce(p_ubicacion, (
    select u.id from public.ubicaciones u
    where u.tipo = 'caja_feria' and u.activa
      and not exists (select 1 from public.cajas_feria k where k.ubicacion_id = u.id and k.activa)
    order by length(u.codigo), u.codigo limit 1));
  if v_ubic is null then perform interno.regla('No quedan cajas físicas libres.'); end if;
  insert into public.cajas_feria (feria_id, numero, ubicacion_id, cupo_total, cupo_disponible)
  values (p_feria, v_n + 1, v_ubic, c.cupo_caja_feria, c.cupo_caja_feria)
  returning * into v_caja;
  return to_jsonb(v_caja);
exception when unique_violation then
  perform interno.conflicto('Esa caja física ya está en uso en otra feria.');
end $$;

-- Sumar un ejemplar a una caja: pasa a En feria y desaparece de la web. El cupo baja en 1.
create or replace function public.agregar_a_caja(p_caja int, p_codigo text, p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_prev jsonb; k public.cajas_feria; f public.ferias; e public.ejemplares; v_tit text;
begin
  perform interno.exigir_rol('bibliotecaria');
  v_prev := interno.idem_previo(p_idem, 'agregar_a_caja');
  if v_prev is not null then return v_prev; end if;
  perform interno.mantenimiento();

  select * into k from public.cajas_feria where id = p_caja for update;
  select * into f from public.ferias where id = k.feria_id;
  if k.id is null or not k.activa or f.estado = 'Cerrada' then perform interno.regla('Esa caja no está activa.'); end if;

  select * into e from public.ejemplares where codigo = upper(trim(p_codigo)) for update;
  if e.id is null then perform interno.regla(format('No hay ningún ejemplar con el código %s.', p_codigo)); end if;
  select titulo into v_tit from public.titulos where id = e.titulo_id;
  if e.estado = 'En feria' and e.caja_feria_id = p_caja then
    return jsonb_build_object('ok', true, 'repetida', true, 'codigo', e.codigo, 'cupo_disponible', k.cupo_disponible);
  end if;
  if e.estado <> 'En venta' then
    perform interno.conflicto(format('«%s» (%s) está «%s»: solo van a la feria libros en venta.', v_tit, e.codigo, e.estado),
      jsonb_build_object('codigo', e.codigo, 'estado', e.estado));
  end if;
  if k.cupo_disponible <= 0 then
    perform interno.conflicto(format('La caja %s está llena (%s de %s).', k.numero, k.cupo_total, k.cupo_total));
  end if;

  update public.cajas_feria set cupo_disponible = cupo_disponible - 1 where id = p_caja;
  update public.ejemplares set caja_feria_id = p_caja where id = e.id;
  perform interno.mover(e.id, 'En feria', format('A la caja %s de la feria del %s', k.numero, to_char(f.fecha, 'DD/MM')));
  perform interno.trasladar(e.id, k.ubicacion_id, format('Armado de caja para la feria del %s', to_char(f.fecha, 'DD/MM')));

  return interno.idem_guardar(p_idem, 'agregar_a_caja', jsonb_build_object(
    'ok', true, 'codigo', e.codigo, 'titulo', v_tit, 'cupo_disponible', k.cupo_disponible - 1));
end $$;

create or replace function public.quitar_de_caja(p_ejemplar uuid)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare e public.ejemplares; k public.cajas_feria;
begin
  perform interno.exigir_rol('bibliotecaria');
  select * into e from public.ejemplares where id = p_ejemplar for update;
  if e.estado <> 'En feria' then return; end if;
  select * into k from public.cajas_feria where id = e.caja_feria_id for update;
  update public.cajas_feria set cupo_disponible = cupo_disponible + 1 where id = k.id;
  update public.ejemplares set caja_feria_id = null where id = e.id;
  perform interno.mover(e.id, 'En venta', 'Se sacó de la caja de feria');
  perform interno.trasladar(e.id, e.ubicacion_deposito_id, 'Vuelve al estante: se sacó de la caja');
end $$;

create or replace function public.asignar_voluntario(p_usuario uuid, p_tipo text, p_feria int default null)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria');
  if (select rol from public.perfiles where id = p_usuario) <> 'caja' then
    perform interno.regla('Solo se asignan cuentas de voluntariado de caja.');
  end if;
  insert into public.asignaciones (usuario_id, tipo, feria_id) values (p_usuario, p_tipo, case when p_tipo = 'feria' then p_feria end)
  on conflict do nothing;
end $$;

create or replace function public.quitar_asignacion(p_asignacion int)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria');
  delete from public.asignaciones where id = p_asignacion;
end $$;

create or replace function public.abrir_feria(p_feria int)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare f public.ferias;
begin
  if not interno.puede_operar_feria(p_feria) then perform interno.exigir_rol('bibliotecaria'); end if;
  select * into f from public.ferias where id = p_feria for update;
  if f.estado = 'Abierta' then return; end if;
  if f.estado = 'Cerrada' then perform interno.regla('Esta feria ya se cerró.'); end if;
  perform interno.validar_horario_feria(p_feria);
  update public.ferias set estado = 'Abierta' where id = p_feria;
end $$;

-- Búsqueda en la feria por código o título (solo lo que está en sus cajas).
create or replace function public.feria_buscar(p_feria int, p_q text)
returns table (id uuid, codigo text, titulo text, autor text, categoria text, categoria_color text,
               precio numeric, caja smallint, estado public.estado_ejemplar)
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  if not interno.puede_operar_feria(p_feria) and interno.rol() <> 'comision' then
    perform interno.exigir_rol('bibliotecaria');
  end if;
  return query
  select e.id, e.codigo, t.titulo, t.autor, c.nombre, c.color, e.precio, k.numero, e.estado
  from public.ejemplares e
  join public.cajas_feria k on k.id = e.caja_feria_id
  join public.titulos t on t.id = e.titulo_id
  join public.categorias c on c.id = t.categoria_id
  where k.feria_id = p_feria and e.estado = 'En feria'
    and (coalesce(trim(p_q), '') = '' or e.codigo ilike '%' || trim(p_q) || '%'
         or t.titulo ilike '%' || trim(p_q) || '%' or t.autor ilike '%' || trim(p_q) || '%')
  order by (upper(e.codigo) = upper(trim(coalesce(p_q, '')))) desc, t.titulo
  limit 30;
end $$;

-- Promoción de feria: se ordenan los libros de la venta por precio (de mayor a menor)
-- y se arman grupos de 3; el más barato de cada grupo completo va sin cargo.
create or replace function interno.promo_feria(p_ids uuid[])
returns table (ejemplar_id uuid, precio numeric, sin_cargo boolean)
language sql stable security definer set search_path = public, pg_temp
as $$
  select id, precio, (row_number() over (order by precio desc, codigo) % 3) = 0
  from public.ejemplares where id = any(p_ids)
$$;

create or replace function public.vender_feria(p_feria int, p_ejemplares uuid[], p_medio public.medio_pago, p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_prev jsonb; f public.ferias; v_conf jsonb; v_venta public.ventas; v_sub numeric; v_promo numeric;
begin
  if not interno.puede_operar_feria(p_feria) then perform interno.exigir_rol('bibliotecaria'); end if;
  v_prev := interno.idem_previo(p_idem, 'vender_feria');
  if v_prev is not null then return v_prev; end if;

  select * into f from public.ferias where id = p_feria for share;
  if f.estado <> 'Abierta' then
    perform interno.regla(case f.estado when 'Cerrada' then 'La feria ya cerró: no se puede vender.'
                                        else 'Primero hay que abrir la feria.' end);
  end if;
  perform interno.validar_horario_feria(p_feria);

  v_conf := interno.bloquear_ejemplares(p_ejemplares, 'En feria');
  if jsonb_array_length(v_conf) > 0 then
    perform interno.conflicto(interno.mensaje_conflicto(v_conf), jsonb_build_object('ejemplares', v_conf));
  end if;
  if exists (select 1 from public.ejemplares e join public.cajas_feria k on k.id = e.caja_feria_id
             where e.id = any(p_ejemplares) and k.feria_id <> p_feria) then
    perform interno.regla('Hay un libro que no es de las cajas de esta feria.');
  end if;

  select sum(precio), sum(case when sin_cargo then precio else 0 end) into v_sub, v_promo
  from interno.promo_feria(p_ejemplares);

  -- En feria nunca se aplica el descuento de socio.
  insert into public.ventas (canal, feria_id, subtotal, descuento_promo, total, medio_pago, vendedor_id)
  values ('feria', p_feria, v_sub, v_promo, v_sub - v_promo, p_medio, auth.uid())
  returning * into v_venta;
  insert into public.venta_items (venta_id, ejemplar_id, precio, descuento, precio_final, promo_sin_cargo)
  select v_venta.id, ejemplar_id, precio, case when sin_cargo then precio else 0 end,
         case when sin_cargo then 0 else precio end, sin_cargo
  from interno.promo_feria(p_ejemplares);

  perform interno.mover(x, 'Vendido', format('Venta de feria #%s', v_venta.numero)) from unnest(p_ejemplares) x;
  perform interno.trasladar(x, null, format('Vendido en la feria (venta #%s)', v_venta.numero), true) from unnest(p_ejemplares) x;

  if v_venta.total > 0 then
    insert into public.movimientos_dinero (canal, tipo, medio, importe, venta_id, feria_id, usuario_id, detalle)
    values ('feria', 'venta', p_medio, v_venta.total, v_venta.id, p_feria, auth.uid(), format('Venta #%s', v_venta.numero));
  end if;

  return interno.idem_guardar(p_idem, 'vender_feria', jsonb_build_object(
    'venta_id', v_venta.id, 'numero', v_venta.numero, 'subtotal', v_sub, 'descuento_promo', v_promo, 'total', v_venta.total));
end $$;

create or replace function public.resumen_caja(p_feria int default null, p_jornada int default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v jsonb;
begin
  if p_feria is not null then
    if not interno.puede_operar_feria(p_feria) and interno.rol() <> 'comision' then perform interno.exigir_rol('bibliotecaria'); end if;
  else
    if not interno.puede_operar_mostrador() and interno.rol() <> 'comision' then perform interno.exigir_rol('bibliotecaria'); end if;
  end if;
  select jsonb_build_object(
    'ventas', (select count(*) from public.ventas where (feria_id = p_feria or jornada_id = p_jornada)),
    'ejemplares', (select count(*) from public.venta_items i join public.ventas v on v.id = i.venta_id
                    where (v.feria_id = p_feria or v.jornada_id = p_jornada)),
    'efectivo', coalesce((select sum(importe) from public.movimientos_dinero
                    where (feria_id = p_feria or jornada_id = p_jornada) and medio = 'efectivo'), 0),
    'transferencias', coalesce((select sum(importe) from public.movimientos_dinero
                    where (feria_id = p_feria or jornada_id = p_jornada) and medio = 'transferencia'), 0),
    'sin_vender', (select count(*) from public.ejemplares e join public.cajas_feria k on k.id = e.caja_feria_id
                    where k.feria_id = p_feria and e.estado = 'En feria'))
  into v;
  return v;
end $$;

-- Cierre de feria: arqueo bloqueado y los no vendidos vuelven al depósito (traslado automático).
create or replace function public.cerrar_feria(p_feria int, p_efectivo_contado numeric, p_transferencias numeric,
  p_motivo text default null, p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_prev jsonb; f public.ferias; a public.arqueos; v_esp numeric; v_trf numeric; v_dif numeric; e record; v_dev int := 0;
begin
  if not interno.puede_operar_feria(p_feria) then perform interno.exigir_rol('bibliotecaria'); end if;
  v_prev := interno.idem_previo(p_idem, 'cerrar_feria');
  if v_prev is not null then return v_prev; end if;

  select * into f from public.ferias where id = p_feria for update;
  if f.estado = 'Cerrada' then
    select * into a from public.arqueos where feria_id = p_feria;
    return jsonb_build_object('arqueo_id', a.id, 'diferencia', a.diferencia, 'repetida', true);
  end if;
  if p_efectivo_contado is null or p_efectivo_contado < 0 or coalesce(p_transferencias, -1) < 0 then
    perform interno.regla('Cargá el efectivo contado y las transferencias (pueden ser cero).');
  end if;

  select coalesce(sum(importe) filter (where medio = 'efectivo'), 0), coalesce(sum(importe) filter (where medio = 'transferencia'), 0)
    into v_esp, v_trf from public.movimientos_dinero where feria_id = p_feria;
  v_dif := (p_efectivo_contado + p_transferencias) - (v_esp + v_trf);
  if v_dif <> 0 and coalesce(trim(p_motivo), '') = '' then
    perform interno.regla(format('Hay una diferencia de $%s: anotá el motivo antes de cerrar.', v_dif));
  end if;

  for e in select x.id, x.ubicacion_deposito_id from public.ejemplares x
           join public.cajas_feria k on k.id = x.caja_feria_id
           where k.feria_id = p_feria and x.estado = 'En feria' order by x.id for update of x loop
    perform interno.mover(e.id, 'En venta', 'Cierre de feria: no se vendió');
    perform interno.trasladar(e.id, e.ubicacion_deposito_id, format('Cierre de la feria del %s: vuelve al depósito', to_char(f.fecha, 'DD/MM')), true);
    update public.ejemplares set caja_feria_id = null where id = e.id;
    v_dev := v_dev + 1;
  end loop;
  -- Ejemplares vendidos dejan de apuntar a la caja; el cupo se libera y la caja física queda libre.
  update public.ejemplares x set caja_feria_id = null
   from public.cajas_feria k where k.id = x.caja_feria_id and k.feria_id = p_feria;
  update public.cajas_feria set cupo_disponible = cupo_total, activa = false where feria_id = p_feria;

  insert into public.arqueos (canal, feria_id, cantidad_ventas, ejemplares_vendidos, efectivo_esperado, efectivo_contado,
    transferencias_registradas, transferencias_informadas, diferencia, motivo_diferencia, ejemplares_devueltos, cerrado_por)
  values ('feria', p_feria,
    (select count(*) from public.ventas where feria_id = p_feria),
    (select count(*) from public.venta_items i join public.ventas v on v.id = i.venta_id where v.feria_id = p_feria),
    v_esp, p_efectivo_contado, v_trf, p_transferencias, v_dif, nullif(trim(p_motivo), ''), v_dev, auth.uid())
  returning * into a;
  update public.ferias set estado = 'Cerrada' where id = p_feria;

  return interno.idem_guardar(p_idem, 'cerrar_feria', jsonb_build_object(
    'arqueo_id', a.id, 'efectivo_esperado', v_esp, 'transferencias_registradas', v_trf,
    'diferencia', v_dif, 'ejemplares_devueltos', v_dev));
end $$;

create or replace function public.nota_rendicion(p_arqueo int, p_nota text)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria');
  update public.arqueos
     set nota_bibliotecaria = concat_ws(E'\n', nota_bibliotecaria, to_char(interno.ahora_local(), 'DD/MM HH24:MI') || ' · ' || trim(p_nota)),
         nota_por = auth.uid(), nota_en = now()
   where id = p_arqueo;
end $$;

-- =====================================================================
-- Mostrador
-- =====================================================================
create or replace function public.abrir_jornada()
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare j public.jornadas_mostrador;
begin
  if not interno.puede_operar_mostrador() then perform interno.exigir_rol('bibliotecaria'); end if;
  insert into public.jornadas_mostrador (fecha, abierta_por) values (interno.hoy(), auth.uid())
  on conflict (fecha) do nothing;
  select * into j from public.jornadas_mostrador where fecha = interno.hoy();
  return to_jsonb(j);
end $$;

create or replace function public.consultar_socio(p_numero text)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare p public.perfiles;
begin
  if not interno.puede_operar_mostrador() then perform interno.exigir_rol('bibliotecaria'); end if;
  select * into p from public.perfiles where numero_socio = trim(p_numero);
  if p.id is null then return jsonb_build_object('encontrado', false); end if;
  return jsonb_build_object('encontrado', true, 'nombre', p.nombre, 'numero', p.numero_socio,
    'al_dia', interno.es_socio_al_dia(p.id), 'cuota_al_dia_hasta', p.cuota_al_dia_hasta);
end $$;

create or replace function public.mostrador_buscar(p_q text)
returns table (id uuid, codigo text, titulo text, autor text, categoria text, categoria_color text,
               precio numeric, ubicacion text, estado public.estado_ejemplar)
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  if not interno.puede_operar_mostrador() then perform interno.exigir_rol('bibliotecaria'); end if;
  perform interno.mantenimiento();
  return query
  select e.id, e.codigo, t.titulo, t.autor, c.nombre, c.color, e.precio, u.codigo, e.estado
  from public.ejemplares e
  join public.titulos t on t.id = e.titulo_id
  join public.categorias c on c.id = t.categoria_id
  left join public.ubicaciones u on u.id = e.ubicacion_id
  where e.estado = 'En venta'
    and (coalesce(trim(p_q), '') = '' or e.codigo ilike '%' || trim(p_q) || '%'
         or t.titulo ilike '%' || trim(p_q) || '%' or t.autor ilike '%' || trim(p_q) || '%')
  order by (upper(e.codigo) = upper(trim(coalesce(p_q, '')))) desc, t.titulo
  limit 30;
end $$;

create or replace function public.vender_mostrador(p_jornada int, p_ejemplares uuid[], p_medio public.medio_pago,
  p_numero_socio text default null, p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_prev jsonb; j public.jornadas_mostrador; v_conf jsonb; v_socio public.perfiles; v_es_socio boolean := false;
        c public.config := interno.config(); v_venta public.ventas; v_sub numeric; v_desc numeric;
begin
  if not interno.puede_operar_mostrador() then perform interno.exigir_rol('bibliotecaria'); end if;
  v_prev := interno.idem_previo(p_idem, 'vender_mostrador');
  if v_prev is not null then return v_prev; end if;
  perform interno.mantenimiento();

  select * into j from public.jornadas_mostrador where id = p_jornada for share;
  if j.id is null or j.estado <> 'Abierta' then perform interno.regla('La jornada de mostrador no está abierta.'); end if;
  perform interno.validar_horario_mostrador();

  if coalesce(trim(p_numero_socio), '') <> '' then
    select * into v_socio from public.perfiles where numero_socio = trim(p_numero_socio);
    if v_socio.id is null then perform interno.regla('No encontramos ese número de socio.'); end if;
    v_es_socio := interno.es_socio_al_dia(v_socio.id);
  end if;

  v_conf := interno.bloquear_ejemplares(p_ejemplares, 'En venta');
  if jsonb_array_length(v_conf) > 0 then
    perform interno.conflicto(interno.mensaje_conflicto(v_conf), jsonb_build_object('ejemplares', v_conf));
  end if;

  select sum(precio), sum(case when v_es_socio then round(precio * c.descuento_socio_pct / 100) else 0 end)
    into v_sub, v_desc from public.ejemplares where id = any(p_ejemplares);

  insert into public.ventas (canal, jornada_id, comprador_id, es_socio, subtotal, descuento_socio, total, medio_pago, vendedor_id)
  values ('mostrador', p_jornada, v_socio.id, v_es_socio, v_sub, v_desc, v_sub - v_desc, p_medio, auth.uid())
  returning * into v_venta;
  insert into public.venta_items (venta_id, ejemplar_id, precio, descuento, precio_final)
  select v_venta.id, e.id, e.precio, d.x, e.precio - d.x
  from public.ejemplares e
  cross join lateral (select case when v_es_socio then round(e.precio * c.descuento_socio_pct / 100) else 0 end as x) d
  where e.id = any(p_ejemplares);

  perform interno.mover(x, 'Vendido', format('Venta de mostrador #%s', v_venta.numero)) from unnest(p_ejemplares) x;
  perform interno.trasladar(x, null, format('Vendido en mostrador (venta #%s)', v_venta.numero), true) from unnest(p_ejemplares) x;

  if v_venta.total > 0 then
    insert into public.movimientos_dinero (canal, tipo, medio, importe, venta_id, jornada_id, usuario_id, detalle)
    values ('mostrador', 'venta', p_medio, v_venta.total, v_venta.id, p_jornada, auth.uid(), format('Venta #%s', v_venta.numero));
  end if;

  return interno.idem_guardar(p_idem, 'vender_mostrador', jsonb_build_object(
    'venta_id', v_venta.id, 'numero', v_venta.numero, 'subtotal', v_sub, 'descuento_socio', v_desc,
    'total', v_venta.total, 'es_socio', v_es_socio));
end $$;

create or replace function public.cerrar_jornada(p_jornada int, p_efectivo_contado numeric, p_transferencias numeric,
  p_motivo text default null, p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_prev jsonb; j public.jornadas_mostrador; a public.arqueos; v_esp numeric; v_trf numeric; v_dif numeric;
begin
  if not interno.puede_operar_mostrador() then perform interno.exigir_rol('bibliotecaria'); end if;
  v_prev := interno.idem_previo(p_idem, 'cerrar_jornada');
  if v_prev is not null then return v_prev; end if;

  select * into j from public.jornadas_mostrador where id = p_jornada for update;
  if j.estado = 'Cerrada' then
    select * into a from public.arqueos where jornada_id = p_jornada;
    return jsonb_build_object('arqueo_id', a.id, 'diferencia', a.diferencia, 'repetida', true);
  end if;
  if p_efectivo_contado is null or p_efectivo_contado < 0 or coalesce(p_transferencias, -1) < 0 then
    perform interno.regla('Cargá el efectivo contado y las transferencias (pueden ser cero).');
  end if;
  select coalesce(sum(importe) filter (where medio = 'efectivo'), 0), coalesce(sum(importe) filter (where medio = 'transferencia'), 0)
    into v_esp, v_trf from public.movimientos_dinero where jornada_id = p_jornada;
  v_dif := (p_efectivo_contado + p_transferencias) - (v_esp + v_trf);
  if v_dif <> 0 and coalesce(trim(p_motivo), '') = '' then
    perform interno.regla(format('Hay una diferencia de $%s: anotá el motivo antes de cerrar.', v_dif));
  end if;
  insert into public.arqueos (canal, jornada_id, cantidad_ventas, ejemplares_vendidos, efectivo_esperado, efectivo_contado,
    transferencias_registradas, transferencias_informadas, diferencia, motivo_diferencia, cerrado_por)
  values ('mostrador', p_jornada,
    (select count(*) from public.ventas where jornada_id = p_jornada),
    (select count(*) from public.venta_items i join public.ventas v on v.id = i.venta_id where v.jornada_id = p_jornada),
    v_esp, p_efectivo_contado, v_trf, p_transferencias, v_dif, nullif(trim(p_motivo), ''), auth.uid())
  returning * into a;
  update public.jornadas_mostrador set estado = 'Cerrada' where id = p_jornada;
  return interno.idem_guardar(p_idem, 'cerrar_jornada', jsonb_build_object(
    'arqueo_id', a.id, 'efectivo_esperado', v_esp, 'transferencias_registradas', v_trf, 'diferencia', v_dif));
end $$;

create or replace function public.ticket_venta(p_venta int)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v public.ventas;
begin
  select * into v from public.ventas where id = p_venta;
  if v.id is null then perform interno.regla('No encontramos esa venta.'); end if;
  if not (interno.rol() in ('bibliotecaria', 'comision') or v.vendedor_id = auth.uid() or v.comprador_id = auth.uid()
          or (v.canal = 'mostrador' and interno.puede_operar_mostrador())
          or (v.canal = 'feria' and interno.puede_operar_feria(v.feria_id))) then
    perform interno.exigir_rol('bibliotecaria');
  end if;
  return to_jsonb(v) || jsonb_build_object(
    'vendedor', (select nombre from public.perfiles where id = v.vendedor_id),
    'items', (select jsonb_agg(jsonb_build_object('codigo', e.codigo, 'titulo', t.titulo, 'autor', t.autor,
                'precio', i.precio, 'descuento', i.descuento, 'precio_final', i.precio_final, 'sin_cargo', i.promo_sin_cargo)
                order by i.precio desc)
              from public.venta_items i join public.ejemplares e on e.id = i.ejemplar_id
              join public.titulos t on t.id = e.titulo_id where i.venta_id = v.id));
end $$;

-- =====================================================================
-- Pedidos web: cobro, preparación y reparto
-- =====================================================================
create or replace function public.registrar_cobro(p_pedido int, p_medio public.medio_pago, p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_prev jsonb; p public.pedidos; v_venta public.ventas; v_rec int; v_conf jsonb; r public.recorridos;
begin
  perform interno.exigir_rol('bibliotecaria');
  v_prev := interno.idem_previo(p_idem, 'registrar_cobro');
  if v_prev is not null then return v_prev; end if;
  perform interno.mantenimiento();

  select * into p from public.pedidos where id = p_pedido for update;
  if p.id is null then perform interno.regla('No encontramos ese pedido.'); end if;
  if p.estado in ('Cobrado', 'Preparado', 'En reparto', 'Entregado', 'Retiro en biblioteca', 'Retirado') then
    return jsonb_build_object('ok', true, 'repetida', true, 'recorrido_id', p.recorrido_id);  -- no se cobra dos veces
  end if;
  if p.estado = 'Cancelado' then
    perform interno.conflicto(format('El pedido #%s ya está cancelado (%s).', p.numero, coalesce(p.cancelado_motivo, 'sin motivo')));
  end if;
  if p.reservado_hasta < now() then
    perform interno.conflicto(format('La reserva del pedido #%s venció: los libros volvieron a la venta.', p.numero));
  end if;

  v_conf := interno.bloquear_ejemplares(array(select ejemplar_id from public.pedido_items where pedido_id = p_pedido), 'Reservado');
  if jsonb_array_length(v_conf) > 0 then
    perform interno.conflicto('Algún libro del pedido ya no está reservado.', jsonb_build_object('ejemplares', v_conf));
  end if;

  insert into public.ventas (canal, pedido_id, comprador_id, es_socio, subtotal, descuento_socio, envio, credito_usado, total, medio_pago, vendedor_id)
  values ('web', p.id, p.comprador_id, p.es_socio, p.subtotal, p.descuento_socio, p.envio, p.credito_usado, p.total, p_medio, auth.uid())
  returning * into v_venta;
  insert into public.venta_items (venta_id, ejemplar_id, precio, descuento, precio_final)
  select v_venta.id, ejemplar_id, precio, descuento, precio_final from public.pedido_items where pedido_id = p_pedido;
  if p.total > 0 then
    insert into public.movimientos_dinero (canal, tipo, medio, importe, venta_id, usuario_id, detalle)
    values ('web', 'venta', p_medio, p.total, v_venta.id, auth.uid(), format('Pedido web #%s', p.numero));
  end if;

  perform interno.mover(ejemplar_id, 'Vendido', format('Pedido web #%s cobrado', p.numero))
    from public.pedido_items where pedido_id = p_pedido;
  update public.ejemplares set reservado_hasta = null where pedido_id = p_pedido;

  update public.pedidos set estado = 'Cobrado', cobrado_en = now(), medio_pago = p_medio where id = p_pedido;
  perform interno.historial_pedido(p_pedido, 'Cobrado', format('Cobro registrado (%s)', p_medio));

  if p.modalidad = 'envio' then
    v_rec := interno.asignar_recorrido(p_pedido);
    if v_rec is not null then
      select * into r from public.recorridos where id = v_rec;
      perform interno.historial_pedido(p_pedido, 'Cobrado', format('Asignado al recorrido del %s', to_char(r.fecha, 'DD/MM')));
    end if;
  end if;

  return interno.idem_guardar(p_idem, 'registrar_cobro', jsonb_build_object(
    'ok', true, 'venta_id', v_venta.id, 'recorrido_id', v_rec, 'recorrido_fecha', r.fecha,
    'sin_recorrido', p.modalidad = 'envio' and v_rec is null));
end $$;

create or replace function public.asignar_recorrido_pendiente(p_pedido int)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare p public.pedidos; v_rec int; v_ult date;
begin
  perform interno.exigir_rol('bibliotecaria');
  select * into p from public.pedidos where id = p_pedido for update;
  if p.modalidad <> 'envio' or p.estado not in ('Cobrado', 'Preparado') then
    perform interno.conflicto('Este pedido no espera reparto.');
  end if;
  if exists (select 1 from public.entregas where pedido_id = p_pedido and resultado = 'Pendiente') then
    return jsonb_build_object('ok', true, 'repetida', true, 'recorrido_id', p.recorrido_id);
  end if;
  select max(r.fecha) into v_ult from public.entregas e join public.recorridos r on r.id = e.recorrido_id where e.pedido_id = p_pedido;
  v_rec := interno.asignar_recorrido(p_pedido, v_ult);
  if v_rec is null then perform interno.conflicto('No hay lugar en los recorridos de esa zona de las próximas dos semanas.'); end if;
  return jsonb_build_object('ok', true, 'recorrido_id', v_rec);
end $$;

create or replace function public.marcar_preparado(p_pedido int)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare p public.pedidos;
begin
  perform interno.exigir_rol('bibliotecaria');
  select * into p from public.pedidos where id = p_pedido for update;
  if p.estado in ('Preparado', 'Retiro en biblioteca') then return; end if;
  if p.estado <> 'Cobrado' then perform interno.conflicto(format('El pedido está «%s»: solo se prepara uno cobrado.', p.estado)); end if;
  if p.modalidad = 'retiro' then
    update public.pedidos set estado = 'Retiro en biblioteca', retiro_desde = now() where id = p_pedido;
    perform interno.historial_pedido(p_pedido, 'Retiro en biblioteca', 'Listo para retirar en la biblioteca');
  else
    update public.pedidos set estado = 'Preparado' where id = p_pedido;
    perform interno.historial_pedido(p_pedido, 'Preparado', 'Paquete armado');
  end if;
end $$;

create or replace function public.marcar_retirado(p_pedido int)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare p public.pedidos;
begin
  perform interno.exigir_rol('bibliotecaria');
  perform interno.mantenimiento();
  select * into p from public.pedidos where id = p_pedido for update;
  if p.estado = 'Retirado' then return; end if;
  if p.estado <> 'Retiro en biblioteca' then
    perform interno.conflicto(format('El pedido está «%s»: no está esperando retiro.', p.estado));
  end if;
  update public.pedidos set estado = 'Retirado', entregado_en = now() where id = p_pedido;
  perform interno.trasladar(ejemplar_id, null, format('Retirado en la biblioteca (pedido #%s)', p.numero), true)
    from public.pedido_items where pedido_id = p_pedido;
  perform interno.historial_pedido(p_pedido, 'Retirado', 'Retirado en la biblioteca');
end $$;

create or replace function public.asignar_repartidor(p_recorrido int, p_usuario uuid)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria');
  if p_usuario is not null and (select rol from public.perfiles where id = p_usuario) <> 'repartidor' then
    perform interno.regla('Esa cuenta no es de reparto.');
  end if;
  update public.recorridos set repartidor_id = p_usuario where id = p_recorrido and estado <> 'Finalizado';
end $$;

create or replace function interno.puede_operar_recorrido(p_recorrido int) returns boolean
language sql stable security definer set search_path = public, interno, pg_temp
as $$
  select interno.rol() = 'bibliotecaria'
      or exists (select 1 from public.recorridos where id = p_recorrido and repartidor_id = auth.uid() and interno.rol() = 'repartidor')
$$;

create or replace function public.hoja_recorrido(p_recorrido int)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare r public.recorridos;
begin
  if not interno.puede_operar_recorrido(p_recorrido) and interno.rol() <> 'comision' then
    perform interno.exigir_rol('bibliotecaria');
  end if;
  select * into r from public.recorridos where id = p_recorrido;
  return to_jsonb(r) || jsonb_build_object(
    'zona', (select nombre from public.zonas where id = r.zona_id),
    'repartidor', (select nombre from public.perfiles where id = r.repartidor_id),
    'entregas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'resultado', e.resultado, 'motivo', e.motivo, 'intento', e.intento, 'marcado_en', e.marcado_en,
        'pedido_id', p.id, 'numero', p.numero, 'estado_pedido', p.estado, 'contacto', p.contacto_nombre,
        'telefono', p.telefono, 'direccion', p.direccion, 'total', p.total, 'cobrado', p.cobrado_en is not null,
        'libros', (select count(*) from public.pedido_items i where i.pedido_id = p.id),
        'titulos', (select string_agg(t.titulo, ' · ' order by t.titulo) from public.pedido_items i
                    join public.ejemplares x on x.id = i.ejemplar_id join public.titulos t on t.id = x.titulo_id where i.pedido_id = p.id))
        order by e.id)
      from public.entregas e join public.pedidos p on p.id = e.pedido_id where e.recorrido_id = r.id), '[]'::jsonb));
end $$;

create or replace function public.iniciar_recorrido(p_recorrido int)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare r public.recorridos; x record;
begin
  if not interno.puede_operar_recorrido(p_recorrido) then perform interno.exigir_rol('bibliotecaria'); end if;
  select * into r from public.recorridos where id = p_recorrido for update;
  if r.estado <> 'Programado' then return; end if;
  update public.recorridos set estado = 'En curso' where id = p_recorrido;
  for x in select p.id from public.entregas e join public.pedidos p on p.id = e.pedido_id
           where e.recorrido_id = p_recorrido and e.resultado = 'Pendiente' and p.estado in ('Cobrado', 'Preparado')
           order by p.id for update of p loop
    update public.pedidos set estado = 'En reparto' where id = x.id;
    perform interno.historial_pedido(x.id, 'En reparto', 'Salió con el recorrido del ' || to_char(r.fecha, 'DD/MM'));
  end loop;
end $$;

-- Marca una entrega. Primera falla: pasa al próximo recorrido de la zona.
-- Segunda falla: Retiro en biblioteca (15 días para retirarlo).
create or replace function public.marcar_entrega(p_entrega int, p_entregada boolean, p_motivo text default null, p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_prev jsonb; e public.entregas; r public.recorridos; p public.pedidos; v_nuevo int; v_fecha date; v_res jsonb;
begin
  select * into e from public.entregas where id = p_entrega for update;
  if e.id is null then perform interno.regla('No encontramos esa entrega.'); end if;
  if not interno.puede_operar_recorrido(e.recorrido_id) then perform interno.exigir_rol('bibliotecaria'); end if;
  v_prev := interno.idem_previo(p_idem, 'marcar_entrega');
  if v_prev is not null then return v_prev; end if;

  if e.resultado <> 'Pendiente' then
    if (e.resultado = 'Entregada') = p_entregada then
      return jsonb_build_object('ok', true, 'repetida', true, 'resultado', e.resultado);
    end if;
    perform interno.conflicto(format('Esta entrega ya figura como «%s».', e.resultado));
  end if;
  if not p_entregada and coalesce(trim(p_motivo), '') = '' then
    perform interno.regla('Contanos por qué no se pudo entregar.');
  end if;

  select * into r from public.recorridos where id = e.recorrido_id for update;
  select * into p from public.pedidos where id = e.pedido_id for update;
  if r.estado = 'Programado' then
    update public.recorridos set estado = 'En curso' where id = r.id;
  end if;

  update public.entregas set resultado = case when p_entregada then 'Entregada' else 'No entregada' end::public.resultado_entrega,
         motivo = case when p_entregada then null else trim(p_motivo) end, marcado_por = auth.uid(), marcado_en = now()
   where id = e.id;

  if p_entregada then
    update public.pedidos set estado = 'Entregado', entregado_en = now() where id = p.id;
    perform interno.trasladar(ejemplar_id, null, format('Entregado a domicilio (pedido #%s)', p.numero), true)
      from public.pedido_items where pedido_id = p.id;
    perform interno.historial_pedido(p.id, 'Entregado', 'Entregado en el recorrido del ' || to_char(r.fecha, 'DD/MM'));
    v_res := jsonb_build_object('ok', true, 'resultado', 'Entregada');
  elsif p.intentos_fallidos = 0 then
    update public.pedidos set intentos_fallidos = 1, estado = 'Preparado', recorrido_id = null where id = p.id;
    perform interno.historial_pedido(p.id, 'Preparado', 'No se pudo entregar: ' || trim(p_motivo));
    v_nuevo := interno.asignar_recorrido(p.id, r.fecha);
    select fecha into v_fecha from public.recorridos where id = v_nuevo;
    if v_nuevo is not null then
      perform interno.historial_pedido(p.id, 'Preparado', 'Reprogramado para el ' || to_char(v_fecha, 'DD/MM'));
    end if;
    v_res := jsonb_build_object('ok', true, 'resultado', 'No entregada', 'reprogramado_para', v_fecha, 'sin_lugar', v_nuevo is null);
  else
    update public.pedidos set intentos_fallidos = 2, estado = 'Retiro en biblioteca', retiro_desde = now(), recorrido_id = null where id = p.id;
    perform interno.historial_pedido(p.id, 'Retiro en biblioteca', 'Segunda entrega fallida: queda para retirar en la biblioteca (15 días)');
    v_res := jsonb_build_object('ok', true, 'resultado', 'No entregada', 'retiro_en_biblioteca', true);
  end if;

  if not exists (select 1 from public.entregas where recorrido_id = r.id and resultado = 'Pendiente') then
    update public.recorridos set estado = 'Finalizado' where id = r.id;
  end if;
  return interno.idem_guardar(p_idem, 'marcar_entrega', v_res);
end $$;

-- =====================================================================
-- Devoluciones
-- =====================================================================
create or replace function public.solicitar_devolucion(p_venta_item int, p_motivo text, p_detalle text default null,
  p_defecto_no_informado boolean default false, p_forma public.forma_reintegro default 'efectivo', p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_prev jsonb; i public.venta_items; v public.ventas; p public.pedidos; e public.ejemplares; v_desde timestamptz;
        c public.config := interno.config(); d public.devoluciones; v_rol public.rol_usuario := interno.rol();
begin
  if auth.uid() is null then perform interno.exigir_rol('comprador'); end if;
  v_prev := interno.idem_previo(p_idem, 'solicitar_devolucion');
  if v_prev is not null then return v_prev; end if;

  select * into i from public.venta_items where id = p_venta_item for update;
  select * into v from public.ventas where id = i.venta_id;
  if i.id is null then perform interno.regla('No encontramos esa compra.'); end if;
  if not (v_rol = 'bibliotecaria' or (v_rol = 'comprador' and v.comprador_id = auth.uid())) then
    perform interno.exigir_rol('bibliotecaria');
  end if;
  if i.anulado then perform interno.conflicto('Este libro ya fue devuelto.'); end if;
  if exists (select 1 from public.devoluciones where venta_item_id = i.id and estado <> 'Rechazada') then
    perform interno.conflicto('Ya hay una devolución en curso para este libro.');
  end if;

  if v.canal = 'web' then
    select * into p from public.pedidos where id = v.pedido_id;
    if p.entregado_en is null then perform interno.regla('El pedido todavía no se entregó.'); end if;
    v_desde := p.entregado_en;
  else
    v_desde := v.created_at;
  end if;
  if now() > v_desde + make_interval(days => c.dias_devolucion) then
    perform interno.regla(format('Pasaron más de %s días corridos desde la entrega (%s): ya no se acepta la devolución.',
      c.dias_devolucion, to_char(v_desde at time zone c.zona_horaria, 'DD/MM')));
  end if;
  if v.canal = 'feria' and not coalesce(p_defecto_no_informado, false) then
    perform interno.regla('En la feria solo se aceptan devoluciones por un defecto que no se informó.');
  end if;
  if p_forma = 'credito' and v.comprador_id is null then
    perform interno.regla('Para dejarlo como crédito la compra tiene que estar a nombre de alguien. Elegí efectivo.');
  end if;

  select * into e from public.ejemplares where id = i.ejemplar_id;
  insert into public.devoluciones (venta_item_id, venta_id, ejemplar_id, canal, comprador_id, motivo, detalle,
    defecto_no_informado, forma_reintegro, solicitada_por)
  values (i.id, v.id, i.ejemplar_id, v.canal, v.comprador_id, p_motivo, nullif(trim(p_detalle), ''),
    coalesce(p_defecto_no_informado, false), p_forma, auth.uid())
  returning * into d;
  return interno.idem_guardar(p_idem, 'solicitar_devolucion', jsonb_build_object('ok', true, 'devolucion_id', d.id));
end $$;

create or replace function public.tomar_devolucion(p_devolucion int)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare d public.devoluciones; e public.ejemplares;
begin
  perform interno.exigir_rol('bibliotecaria');
  select * into d from public.devoluciones where id = p_devolucion for update;
  if d.estado <> 'Solicitada' then return; end if;
  select * into e from public.ejemplares where id = d.ejemplar_id for update;
  if e.estado <> 'Vendido' then perform interno.conflicto(format('El ejemplar figura «%s».', e.estado)); end if;
  perform interno.mover(e.id, 'En devolución', 'Devolución en revisión');
  perform interno.trasladar(e.id, (select id from public.ubicaciones where tipo = 'devoluciones' limit 1), 'Ingresa para revisar la devolución');
  update public.devoluciones set estado = 'En revisión', revisada_por = auth.uid() where id = d.id;
end $$;

create or replace function public.resolver_devolucion(p_devolucion int, p_aprobar boolean,
  p_resultado_ejemplar public.estado_ejemplar default 'En venta', p_falla_biblioteca boolean default false,
  p_nota text default null, p_idem uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
declare v_prev jsonb; d public.devoluciones; i public.venta_items; v public.ventas; p public.pedidos; e public.ejemplares;
        v_envio numeric := 0; v_total numeric; v_jornada int;
begin
  perform interno.exigir_rol('bibliotecaria');
  v_prev := interno.idem_previo(p_idem, 'resolver_devolucion');
  if v_prev is not null then return v_prev; end if;

  select * into d from public.devoluciones where id = p_devolucion for update;
  if d.id is null then perform interno.regla('No encontramos esa devolución.'); end if;
  if d.estado in ('Aprobada', 'Rechazada') then
    if (d.estado = 'Aprobada') = p_aprobar then
      return jsonb_build_object('ok', true, 'repetida', true, 'importe', d.importe_total);  -- no se reintegra dos veces
    end if;
    perform interno.conflicto(format('Esta devolución ya fue %s.', lower(d.estado::text)));
  end if;
  if d.estado = 'Solicitada' then
    perform public.tomar_devolucion(p_devolucion);
  end if;
  if p_aprobar and p_resultado_ejemplar not in ('En venta', 'Descartado') then
    perform interno.regla('Después de la revisión el libro vuelve a la venta o se descarta.');
  end if;
  if p_aprobar and p_resultado_ejemplar = 'Descartado' and coalesce(trim(p_nota), '') = '' then
    perform interno.regla('Anotá por qué se descarta el ejemplar.');
  end if;

  select * into e from public.ejemplares where id = d.ejemplar_id for update;
  select * into i from public.venta_items where id = d.venta_item_id for update;
  select * into v from public.ventas where id = d.venta_id;

  if not p_aprobar then
    perform interno.mover(e.id, 'Vendido', 'Devolución rechazada: el libro vuelve a la persona');
    perform interno.trasladar(e.id, null, 'Se le devuelve a la persona (devolución rechazada)');
    update public.devoluciones set estado = 'Rechazada', nota_revision = nullif(trim(p_nota), ''), revisada_por = auth.uid(), resuelta_en = now()
     where id = d.id;
    return interno.idem_guardar(p_idem, 'resolver_devolucion', jsonb_build_object('ok', true, 'estado', 'Rechazada'));
  end if;

  -- El envío solo se devuelve si la falla es de la biblioteca (una vez por pedido).
  if v.canal = 'web' and coalesce(p_falla_biblioteca, false) then
    select * into p from public.pedidos where id = v.pedido_id for update;
    if p.envio > 0 and not p.envio_reintegrado then
      v_envio := p.envio;
      update public.pedidos set envio_reintegrado = true where id = p.id;
    end if;
  end if;
  v_total := i.precio_final + v_envio;

  if p_resultado_ejemplar = 'En venta' then
    perform interno.mover(e.id, 'En venta', 'Devolución aprobada: vuelve a la venta');
    perform interno.trasladar(e.id, e.ubicacion_deposito_id, 'Vuelve al estante después de la devolución', true);
  else
    update public.ejemplares set motivo_descarte = trim(p_nota) where id = e.id;
    perform interno.mover(e.id, 'Descartado', 'Devolución aprobada, descartado: ' || trim(p_nota));
    perform interno.trasladar(e.id, null, 'Descarte después de la devolución');
  end if;
  update public.ejemplares set pedido_id = null where id = e.id;
  update public.venta_items set anulado = true where id = i.id;

  update public.devoluciones set estado = 'Aprobada', falla_biblioteca = coalesce(p_falla_biblioteca, false),
    resultado_ejemplar = p_resultado_ejemplar, importe_libro = i.precio_final, importe_envio = v_envio, importe_total = v_total,
    nota_revision = nullif(trim(p_nota), ''), revisada_por = auth.uid(), resuelta_en = now()
  where id = d.id;

  if v_total > 0 then
    if d.forma_reintegro = 'efectivo' then
      select id into v_jornada from public.jornadas_mostrador where fecha = interno.hoy() and estado = 'Abierta';
      insert into public.movimientos_dinero (canal, tipo, medio, importe, venta_id, devolucion_id, jornada_id, usuario_id, detalle)
      values (v.canal, 'reintegro', 'efectivo', -v_total, v.id, d.id, v_jornada, auth.uid(), format('Devolución #%s', d.id));
    else
      update public.perfiles set credito = credito + v_total where id = d.comprador_id;
      insert into public.movimientos_credito (perfil_id, importe, motivo, venta_id, devolucion_id)
      values (d.comprador_id, v_total, format('Devolución #%s', d.id), v.id, d.id);
    end if;
  end if;

  return interno.idem_guardar(p_idem, 'resolver_devolucion', jsonb_build_object(
    'ok', true, 'estado', 'Aprobada', 'importe', v_total, 'envio', v_envio, 'forma', d.forma_reintegro));
end $$;

-- =====================================================================
-- Administración
-- =====================================================================
create or replace function public.actualizar_socio(p_perfil uuid, p_numero text, p_cuota_hasta date)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria');
  update public.perfiles set numero_socio = nullif(trim(p_numero), ''), cuota_al_dia_hasta = p_cuota_hasta where id = p_perfil;
end $$;

create or replace function public.configurar_modo_prueba(p_permitir boolean)
returns void
language plpgsql security definer set search_path = public, interno, pg_temp
as $$
begin
  perform interno.exigir_rol('bibliotecaria');
  update public.config set permitir_fuera_de_horario = p_permitir where id;
end $$;
