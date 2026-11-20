-- =====================================================================
-- Seguridad: alta de perfiles, permisos y RLS
-- =====================================================================

-- Alta: toda cuenta nueva nace como «comprador». El rol nunca se toma de lo
-- que manda el formulario (raw_user_meta_data solo aporta el nombre).
create or replace function interno.tg_nuevo_usuario() returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  insert into public.perfiles (id, email, nombre, rol)
  values (new.id, coalesce(new.email, ''), coalesce(nullif(trim(new.raw_user_meta_data->>'nombre'), ''), split_part(coalesce(new.email, ''), '@', 1)), 'comprador')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert on auth.users
for each row execute function interno.tg_nuevo_usuario();

-- Rol del usuario actual, para usar en políticas (security definer evita recursión de RLS).
create or replace function public.mi_rol() returns public.rol_usuario
language sql stable security definer set search_path = public, pg_temp
as $$ select rol from public.perfiles where id = auth.uid() $$;

create or replace function interno.es_staff() returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$ select coalesce((select rol in ('bibliotecaria', 'comision') from public.perfiles where id = auth.uid()), false) $$;

create or replace function interno.mis_ferias() returns setof int
language sql stable security definer set search_path = public, pg_temp
as $$
  select feria_id from public.asignaciones a join public.perfiles p on p.id = a.usuario_id
  where a.usuario_id = auth.uid() and a.tipo = 'feria' and p.rol = 'caja'
$$;

create or replace function interno.atiendo_mostrador() returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (select 1 from public.asignaciones a join public.perfiles p on p.id = a.usuario_id
                 where a.usuario_id = auth.uid() and a.tipo = 'mostrador' and p.rol = 'caja')
$$;

create or replace function interno.mis_recorridos() returns setof int
language sql stable security definer set search_path = public, pg_temp
as $$
  select r.id from public.recorridos r join public.perfiles p on p.id = r.repartidor_id
  where r.repartidor_id = auth.uid() and p.rol = 'repartidor'
$$;

create or replace function interno.mis_pedidos_reparto() returns setof int
language sql stable security definer set search_path = public, pg_temp
as $$ select e.pedido_id from public.entregas e where e.recorrido_id in (select interno.mis_recorridos()) $$;

-- ---------------------------------------------------------------------
-- Permisos base: nadie escribe tablas directamente. Toda escritura pasa por
-- funciones (security definer) que validan rol y estado.
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
grant select on public.categorias, public.zonas to anon;
revoke select on public.operaciones from authenticated;

-- Funciones: se revoca todo y se habilita una por una.
revoke execute on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema interno from public, anon, authenticated;
grant usage on schema interno to anon, authenticated; -- necesario para que las políticas evalúen helpers
grant execute on function interno.es_staff(), interno.mis_ferias(), interno.atiendo_mostrador(),
  interno.mis_recorridos(), interno.mis_pedidos_reparto() to authenticated;

grant execute on function
  public.catalogo_publico(text, smallint, int, int), public.ejemplar_publico(uuid), public.disponibilidad(uuid[]),
  public.ferias_publicas(), public.proximo_recorrido(smallint)
to anon, authenticated;

grant execute on function
  public.mi_rol(), public.cotizar_pedido(uuid[], public.modalidad_entrega),
  public.crear_pedido(uuid[], public.modalidad_entrega, smallint, text, text, text, uuid),
  public.cancelar_mi_pedido(int), public.actualizar_mi_perfil(text, text, text, smallint),
  public.solicitar_devolucion(int, text, text, boolean, public.forma_reintegro, uuid),
  public.crear_lote(text, boolean, text), public.cambiar_estado_lote(int, public.estado_lote),
  public.cargar_ejemplar(int, text, text, text, smallint, smallint, public.estado_fisico, int, text, boolean, text, uuid),
  public.publicar_ejemplar(uuid, numeric), public.cambiar_precio(uuid, numeric),
  public.descartar_ejemplar(uuid, text, boolean), public.trasladar_ejemplar(uuid, int, text),
  public.crear_feria(date, text, time, time), public.crear_caja_feria(int, int), public.agregar_a_caja(int, text, uuid),
  public.quitar_de_caja(uuid), public.asignar_voluntario(uuid, text, int), public.quitar_asignacion(int),
  public.abrir_feria(int), public.feria_buscar(int, text), public.vender_feria(int, uuid[], public.medio_pago, uuid),
  public.resumen_caja(int, int), public.cerrar_feria(int, numeric, numeric, text, uuid), public.nota_rendicion(int, text),
  public.abrir_jornada(), public.consultar_socio(text), public.mostrador_buscar(text),
  public.vender_mostrador(int, uuid[], public.medio_pago, text, uuid), public.cerrar_jornada(int, numeric, numeric, text, uuid),
  public.ticket_venta(int), public.registrar_cobro(int, public.medio_pago, uuid), public.asignar_recorrido_pendiente(int),
  public.marcar_preparado(int), public.marcar_retirado(int), public.asignar_repartidor(int, uuid),
  public.hoja_recorrido(int), public.iniciar_recorrido(int), public.marcar_entrega(int, boolean, text, uuid),
  public.tomar_devolucion(int), public.resolver_devolucion(int, boolean, public.estado_ejemplar, boolean, text, uuid),
  public.actualizar_socio(uuid, text, date), public.configurar_modo_prueba(boolean)
to authenticated;

-- ---------------------------------------------------------------------
-- RLS en todas las tablas
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Catálogos de referencia: lectura libre.
create policy categorias_lectura on public.categorias for select to anon, authenticated using (true);
create policy zonas_lectura on public.zonas for select to anon, authenticated using (true);
create policy config_lectura on public.config for select to authenticated using (true);
create policy ubicaciones_lectura on public.ubicaciones for select to authenticated
  using (interno.es_staff() or public.mi_rol() = 'caja');

-- Perfiles: cada quien ve el suyo; la biblioteca y la comisión ven todos.
create policy perfiles_propio on public.perfiles for select to authenticated
  using (id = auth.uid() or interno.es_staff());

create policy asignaciones_lectura on public.asignaciones for select to authenticated
  using (usuario_id = auth.uid() or interno.es_staff());

-- Donaciones y depósito: solo bibliotecaria y comisión.
create policy lotes_staff on public.lotes for select to authenticated using (interno.es_staff());
create policy titulos_lectura on public.titulos for select to authenticated
  using (interno.es_staff() or public.mi_rol() in ('caja', 'comprador', 'repartidor'));
create policy historial_ej_staff on public.historial_ejemplar for select to authenticated using (interno.es_staff());
create policy traslados_staff on public.traslados for select to authenticated using (interno.es_staff());

-- Ejemplares: staff ve todo; caja ve lo de las cajas de SU feria (y lo que está en venta si atiende el mostrador);
-- el comprador ve los de sus pedidos y compras.
create policy ejemplares_staff on public.ejemplares for select to authenticated using (interno.es_staff());
create policy ejemplares_caja on public.ejemplares for select to authenticated using (
  public.mi_rol() = 'caja' and (
    caja_feria_id in (select k.id from public.cajas_feria k where k.feria_id in (select interno.mis_ferias()))
    or (estado = 'En venta' and interno.atiendo_mostrador())));
create policy ejemplares_comprador on public.ejemplares for select to authenticated using (
  public.mi_rol() = 'comprador' and (
    id in (select i.ejemplar_id from public.pedido_items i join public.pedidos p on p.id = i.pedido_id where p.comprador_id = auth.uid())
    or id in (select i.ejemplar_id from public.venta_items i join public.ventas v on v.id = i.venta_id where v.comprador_id = auth.uid())));

-- Ferias: lectura para staff y para la caja asignada.
create policy ferias_lectura on public.ferias for select to authenticated
  using (interno.es_staff() or id in (select interno.mis_ferias()));
create policy cajas_lectura on public.cajas_feria for select to authenticated
  using (interno.es_staff() or feria_id in (select interno.mis_ferias()));
create policy jornadas_lectura on public.jornadas_mostrador for select to authenticated
  using (interno.es_staff() or interno.atiendo_mostrador());

-- Pedidos.
create policy pedidos_lectura on public.pedidos for select to authenticated using (
  interno.es_staff() or comprador_id = auth.uid() or id in (select interno.mis_pedidos_reparto()));
create policy pedido_items_lectura on public.pedido_items for select to authenticated using (
  interno.es_staff()
  or pedido_id in (select p.id from public.pedidos p where p.comprador_id = auth.uid())
  or pedido_id in (select interno.mis_pedidos_reparto()));
create policy historial_pedido_lectura on public.historial_pedido for select to authenticated using (
  interno.es_staff() or pedido_id in (select p.id from public.pedidos p where p.comprador_id = auth.uid()));

-- Reparto: cada repartidor ve SOLO sus recorridos y entregas.
create policy recorridos_lectura on public.recorridos for select to authenticated
  using (interno.es_staff() or id in (select interno.mis_recorridos()));
create policy entregas_lectura on public.entregas for select to authenticated using (
  interno.es_staff() or recorrido_id in (select interno.mis_recorridos())
  or pedido_id in (select p.id from public.pedidos p where p.comprador_id = auth.uid()));

-- Ventas y dinero.
create policy ventas_lectura on public.ventas for select to authenticated using (
  interno.es_staff() or comprador_id = auth.uid()
  or (public.mi_rol() = 'caja' and (feria_id in (select interno.mis_ferias()) or (canal = 'mostrador' and interno.atiendo_mostrador()))));
create policy venta_items_lectura on public.venta_items for select to authenticated using (
  venta_id in (select v.id from public.ventas v));  -- hereda la política de ventas
create policy movimientos_staff on public.movimientos_dinero for select to authenticated using (interno.es_staff());
create policy movcred_lectura on public.movimientos_credito for select to authenticated
  using (interno.es_staff() or perfil_id = auth.uid());
create policy arqueos_lectura on public.arqueos for select to authenticated using (
  interno.es_staff() or feria_id in (select interno.mis_ferias()) or (jornada_id is not null and interno.atiendo_mostrador()));

create policy devoluciones_lectura on public.devoluciones for select to authenticated
  using (interno.es_staff() or comprador_id = auth.uid());

-- operaciones: sin políticas (inaccesible desde la API).
