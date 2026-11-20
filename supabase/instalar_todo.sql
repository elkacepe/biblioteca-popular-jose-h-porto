-- =====================================================================
-- INSTALACIÓN COMPLETA en un proyecto NUEVO de Supabase (un solo archivo).
-- Generado a partir de supabase/migrations/*.sql + supabase/seed.sql.
-- Pegar entero en SQL Editor → Run. Tarda unos segundos.
-- =====================================================================

-- >>> supabase/migrations/20261120000001_esquema.sql
-- =====================================================================
-- Biblioteca Popular José H. Porto · Esquema
-- Ejemplares únicos que se mueven entre depósito, web, mostrador y feria.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- Esquema interno: funciones auxiliares que NO se exponen por la API.
create schema if not exists interno;
revoke all on schema interno from public;
grant usage on schema interno to postgres;

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.rol_usuario as enum ('comprador', 'caja', 'repartidor', 'bibliotecaria', 'comision');

create type public.estado_lote as enum ('Recibido', 'En clasificación', 'Clasificado');

create type public.estado_fisico as enum ('Muy bueno', 'Bueno', 'Regular', 'Muy malo');

create type public.estado_ejemplar as enum (
  'En clasificación', 'Acervo', 'En venta', 'Reservado', 'En feria',
  'Vendido', 'En devolución', 'Descartado'
);

create type public.tipo_ubicacion as enum ('estante', 'caja_feria', 'acervo', 'devoluciones', 'reciclado');

create type public.canal_venta as enum ('web', 'mostrador', 'feria');

create type public.medio_pago as enum ('efectivo', 'transferencia');

create type public.estado_pedido as enum (
  'Nuevo', 'Reservado', 'Cobrado', 'Preparado', 'En reparto', 'Entregado',
  'Retiro en biblioteca', 'Retirado', 'Cancelado'
);

create type public.modalidad_entrega as enum ('envio', 'retiro');

create type public.estado_feria as enum ('Planificada', 'Abierta', 'Cerrada');

create type public.estado_recorrido as enum ('Programado', 'En curso', 'Finalizado');

create type public.resultado_entrega as enum ('Pendiente', 'Entregada', 'No entregada');

create type public.estado_devolucion as enum ('Solicitada', 'En revisión', 'Aprobada', 'Rechazada');

create type public.forma_reintegro as enum ('efectivo', 'credito');

-- ---------------------------------------------------------------------
-- Configuración y catálogos de prueba
-- ---------------------------------------------------------------------
create table public.config (
  id boolean primary key default true check (id),
  descuento_socio_pct numeric(5,2) not null default 15,
  costo_envio numeric(12,2) not null default 1800,
  envio_gratis_socio_desde int not null default 4,
  horas_reserva_web int not null default 48,
  dias_devolucion int not null default 7,
  dias_retiro int not null default 15,
  cupo_caja_feria int not null default 40,
  max_cajas_feria int not null default 8,
  cupo_recorrido int not null default 12,
  dias_antiguedad_deposito int not null default 180,
  -- Modo prueba: permite operar mostrador y feria fuera de horario.
  permitir_fuera_de_horario boolean not null default true,
  zona_horaria text not null default 'America/Argentina/Cordoba'
);

create table public.categorias (
  id smallserial primary key,
  nombre text not null unique,
  precio_base numeric(12,2) not null check (precio_base > 0),
  color text not null default '#21395B',
  orden smallint not null default 0
);

create table public.zonas (
  id smallserial primary key,
  nombre text not null unique,
  dia_semana smallint not null check (dia_semana between 1 and 7), -- ISO: 1 lunes … 7 domingo
  hora_inicio time not null default '15:00',
  hora_fin time not null default '19:00'
);

create table public.ubicaciones (
  id serial primary key,
  codigo text not null unique,               -- «Estante A3», «Caja de feria 12»
  tipo public.tipo_ubicacion not null,
  activa boolean not null default true
);

-- ---------------------------------------------------------------------
-- Personas
-- ---------------------------------------------------------------------
create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  nombre text not null default '',
  rol public.rol_usuario not null default 'comprador',
  telefono text,
  direccion text,
  zona_id smallint references public.zonas(id),
  numero_socio text unique,                  -- null = no es socio
  cuota_al_dia_hasta date,                   -- socio con cuota al día si >= hoy
  credito numeric(12,2) not null default 0 check (credito >= 0),
  created_at timestamptz not null default now()
);

-- Asignación de voluntarios de caja: a una feria o al mostrador.
create table public.asignaciones (
  id serial primary key,
  usuario_id uuid not null references public.perfiles(id) on delete cascade,
  tipo text not null check (tipo in ('feria', 'mostrador')),
  feria_id int,                              -- FK agregada más abajo
  created_at timestamptz not null default now(),
  check ((tipo = 'feria') = (feria_id is not null))
);
create unique index asignaciones_unica on public.asignaciones (usuario_id, tipo, coalesce(feria_id, 0));

-- ---------------------------------------------------------------------
-- Donaciones, títulos y ejemplares
-- ---------------------------------------------------------------------
create table public.lotes (
  id serial primary key,
  codigo text not null unique,
  procedencia text,                          -- null o vacío = Anónima
  anonima boolean not null default false,
  estado public.estado_lote not null default 'Recibido',
  observaciones text,
  recibido_en timestamptz not null default now(),
  recibido_por uuid references public.perfiles(id),
  check (anonima or coalesce(trim(procedencia), '') <> '')
);

create table public.titulos (
  id serial primary key,
  titulo text not null,
  autor text not null default 'Anónimo',
  editorial text,
  anio smallint,
  categoria_id smallint not null references public.categorias(id),
  clave text generated always as (lower(trim(titulo)) || '|' || lower(trim(autor))) stored unique,
  en_acervo boolean not null default false,  -- la biblioteca ya tiene uno propio
  created_at timestamptz not null default now()
);

create sequence public.ejemplar_codigo_seq start 1001;

create table public.ejemplares (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique default ('PJ-' || lpad(nextval('public.ejemplar_codigo_seq')::text, 5, '0')),
  titulo_id int not null references public.titulos(id),
  lote_id int not null references public.lotes(id),
  editorial text,
  anio smallint,
  estado_fisico public.estado_fisico not null,
  precio_sugerido numeric(12,2),
  precio numeric(12,2) check (precio is null or precio >= 0),
  estado public.estado_ejemplar not null,
  ubicacion_id int references public.ubicaciones(id),           -- dónde está ahora (null = salió de la biblioteca)
  ubicacion_deposito_id int references public.ubicaciones(id),  -- su lugar de depósito
  motivo_descarte text,
  destino_reciclado boolean not null default false,
  observaciones text,
  pedido_id int,                                                -- pedido web que lo reserva o compró
  caja_feria_id int,                                            -- caja de feria donde está
  reservado_hasta timestamptz,
  en_deposito_desde timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (estado <> 'En venta' or precio is not null),
  check (estado <> 'Descartado' or coalesce(trim(motivo_descarte), '') <> ''),
  check (estado <> 'Reservado' or (pedido_id is not null and reservado_hasta is not null)),
  check (estado <> 'En feria' or caja_feria_id is not null),
  check (estado_fisico <> 'Muy malo' or estado = 'Descartado')
);
create index ejemplares_estado_idx on public.ejemplares (estado);
create index ejemplares_titulo_idx on public.ejemplares (titulo_id);
create index ejemplares_caja_idx on public.ejemplares (caja_feria_id);
create index ejemplares_pedido_idx on public.ejemplares (pedido_id);

create table public.historial_ejemplar (
  id bigserial primary key,
  ejemplar_id uuid not null references public.ejemplares(id) on delete cascade,
  estado_anterior public.estado_ejemplar,
  estado_nuevo public.estado_ejemplar not null,
  usuario_id uuid references public.perfiles(id),
  motivo text,
  fecha timestamptz not null default now()
);
create index historial_ejemplar_idx on public.historial_ejemplar (ejemplar_id, fecha);

create table public.traslados (
  id bigserial primary key,
  ejemplar_id uuid not null references public.ejemplares(id) on delete cascade,
  desde_id int references public.ubicaciones(id),
  hacia_id int references public.ubicaciones(id),
  usuario_id uuid references public.perfiles(id),
  motivo text not null,
  automatico boolean not null default false,
  fecha timestamptz not null default now()
);
create index traslados_ejemplar_idx on public.traslados (ejemplar_id, fecha);

-- ---------------------------------------------------------------------
-- Ferias y mostrador
-- ---------------------------------------------------------------------
create table public.ferias (
  id serial primary key,
  fecha date not null,
  lugar text not null default 'Plazoleta del Reloj Cucú',
  hora_inicio time not null default '10:00',
  hora_fin time not null default '13:00',
  estado public.estado_feria not null default 'Planificada',
  created_at timestamptz not null default now(),
  check (hora_fin > hora_inicio)
);
create unique index ferias_una_por_mes on public.ferias (date_trunc('month', fecha::timestamp));

alter table public.asignaciones
  add constraint asignaciones_feria_fk foreign key (feria_id) references public.ferias(id) on delete cascade;

create table public.cajas_feria (
  id serial primary key,
  feria_id int not null references public.ferias(id) on delete cascade,
  numero smallint not null,
  ubicacion_id int not null references public.ubicaciones(id),
  cupo_total int not null default 40,
  cupo_disponible int not null default 40,
  activa boolean not null default true,       -- false al cerrar la feria: la caja física queda libre
  unique (feria_id, numero),
  check (cupo_disponible between 0 and cupo_total)
);
-- Una caja física no puede estar en dos ferias abiertas a la vez.
create unique index cajas_ubicacion_activa on public.cajas_feria (ubicacion_id) where activa;

alter table public.ejemplares
  add constraint ejemplares_caja_fk foreign key (caja_feria_id) references public.cajas_feria(id);

create table public.jornadas_mostrador (
  id serial primary key,
  fecha date not null unique,
  estado text not null default 'Abierta' check (estado in ('Abierta', 'Cerrada')),
  abierta_por uuid references public.perfiles(id),
  abierta_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Pedidos web y reparto
-- ---------------------------------------------------------------------
create sequence public.pedido_numero_seq start 501;

create table public.recorridos (
  id serial primary key,
  zona_id smallint not null references public.zonas(id),
  fecha date not null,
  hora_inicio time not null,
  hora_fin time not null,
  cupo_total int not null default 12,
  cupo_disponible int not null default 12,
  repartidor_id uuid references public.perfiles(id),
  estado public.estado_recorrido not null default 'Programado',
  unique (zona_id, fecha),
  check (cupo_disponible between 0 and cupo_total)
);

create table public.pedidos (
  id serial primary key,
  numero int not null unique default nextval('public.pedido_numero_seq'),
  comprador_id uuid not null references public.perfiles(id),
  estado public.estado_pedido not null default 'Nuevo',
  modalidad public.modalidad_entrega not null,
  zona_id smallint references public.zonas(id),
  contacto_nombre text not null,
  telefono text,
  direccion text,
  es_socio boolean not null default false,
  subtotal numeric(12,2) not null default 0,
  descuento_socio numeric(12,2) not null default 0,
  envio numeric(12,2) not null default 0,
  credito_usado numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,       -- a cobrar (subtotal - descuento + envío - crédito)
  reservado_hasta timestamptz,
  recorrido_id int references public.recorridos(id),
  intentos_fallidos smallint not null default 0 check (intentos_fallidos between 0 and 2),
  cobrado_en timestamptz,
  medio_pago public.medio_pago,
  entregado_en timestamptz,
  retiro_desde timestamptz,
  envio_reintegrado boolean not null default false,
  cancelado_motivo text,
  created_at timestamptz not null default now(),
  check (modalidad = 'retiro' or (zona_id is not null and coalesce(trim(direccion), '') <> ''))
);
create index pedidos_comprador_idx on public.pedidos (comprador_id);
create index pedidos_estado_idx on public.pedidos (estado);

alter table public.ejemplares
  add constraint ejemplares_pedido_fk foreign key (pedido_id) references public.pedidos(id);

create table public.pedido_items (
  pedido_id int not null references public.pedidos(id) on delete cascade,
  ejemplar_id uuid not null references public.ejemplares(id),
  precio numeric(12,2) not null,
  descuento numeric(12,2) not null default 0,
  precio_final numeric(12,2) not null,
  primary key (pedido_id, ejemplar_id)
);

create table public.historial_pedido (
  id bigserial primary key,
  pedido_id int not null references public.pedidos(id) on delete cascade,
  estado public.estado_pedido not null,
  usuario_id uuid references public.perfiles(id),
  nota text,
  fecha timestamptz not null default now()
);

create table public.entregas (
  id serial primary key,
  recorrido_id int not null references public.recorridos(id),
  pedido_id int not null references public.pedidos(id) on delete cascade,
  intento smallint not null default 1,
  resultado public.resultado_entrega not null default 'Pendiente',
  motivo text,
  marcado_por uuid references public.perfiles(id),
  marcado_en timestamptz,
  unique (recorrido_id, pedido_id),
  check (resultado <> 'No entregada' or coalesce(trim(motivo), '') <> '')
);

-- ---------------------------------------------------------------------
-- Ventas, dinero y cierres
-- ---------------------------------------------------------------------
create sequence public.venta_numero_seq start 1;

create table public.ventas (
  id serial primary key,
  numero int not null unique default nextval('public.venta_numero_seq'),
  canal public.canal_venta not null,
  feria_id int references public.ferias(id),
  jornada_id int references public.jornadas_mostrador(id),
  pedido_id int unique references public.pedidos(id),
  comprador_id uuid references public.perfiles(id),
  es_socio boolean not null default false,
  subtotal numeric(12,2) not null,
  descuento_socio numeric(12,2) not null default 0,
  descuento_promo numeric(12,2) not null default 0,
  envio numeric(12,2) not null default 0,
  credito_usado numeric(12,2) not null default 0,
  total numeric(12,2) not null,                 -- dinero efectivamente cobrado
  medio_pago public.medio_pago not null,
  vendedor_id uuid references public.perfiles(id),
  created_at timestamptz not null default now(),
  check (canal <> 'feria' or (feria_id is not null and descuento_socio = 0)),
  check (canal <> 'mostrador' or jornada_id is not null),
  check (canal <> 'web' or pedido_id is not null)
);
create index ventas_canal_fecha_idx on public.ventas (canal, created_at);

create table public.venta_items (
  id serial primary key,
  venta_id int not null references public.ventas(id) on delete cascade,
  ejemplar_id uuid not null references public.ejemplares(id),
  precio numeric(12,2) not null,
  descuento numeric(12,2) not null default 0,   -- socio o promoción
  precio_final numeric(12,2) not null,
  promo_sin_cargo boolean not null default false,
  anulado boolean not null default false,       -- devuelto o cancelado
  unique (venta_id, ejemplar_id)
);
create index venta_items_ejemplar_idx on public.venta_items (ejemplar_id);

-- Libro mayor de dinero real (efectivo y transferencias). Los informes salen de acá.
create table public.movimientos_dinero (
  id bigserial primary key,
  fecha timestamptz not null default now(),
  canal public.canal_venta not null,
  tipo text not null check (tipo in ('venta', 'reintegro')),
  medio public.medio_pago not null,
  importe numeric(12,2) not null,               -- positivo entra, negativo sale
  venta_id int references public.ventas(id),
  devolucion_id int,
  feria_id int references public.ferias(id),
  jornada_id int references public.jornadas_mostrador(id),
  usuario_id uuid references public.perfiles(id),
  detalle text
);
create index movimientos_fecha_idx on public.movimientos_dinero (fecha);

create table public.movimientos_credito (
  id bigserial primary key,
  perfil_id uuid not null references public.perfiles(id) on delete cascade,
  importe numeric(12,2) not null,
  motivo text not null,
  pedido_id int references public.pedidos(id),
  venta_id int references public.ventas(id),
  devolucion_id int,
  fecha timestamptz not null default now()
);

create table public.arqueos (
  id serial primary key,
  canal public.canal_venta not null check (canal in ('feria', 'mostrador')),
  feria_id int unique references public.ferias(id),
  jornada_id int unique references public.jornadas_mostrador(id),
  cantidad_ventas int not null,
  ejemplares_vendidos int not null,
  efectivo_esperado numeric(12,2) not null,
  efectivo_contado numeric(12,2) not null,
  transferencias_registradas numeric(12,2) not null,
  transferencias_informadas numeric(12,2) not null,
  diferencia numeric(12,2) not null,            -- (contado + transferencias informadas) - (esperado + registradas)
  motivo_diferencia text,
  ejemplares_devueltos int not null default 0,
  cerrado_por uuid references public.perfiles(id),
  cerrado_en timestamptz not null default now(),
  bloqueado boolean not null default true,
  nota_bibliotecaria text,
  nota_por uuid references public.perfiles(id),
  nota_en timestamptz,
  check ((canal = 'feria') = (feria_id is not null)),
  check ((canal = 'mostrador') = (jornada_id is not null)),
  check (diferencia = 0 or coalesce(trim(motivo_diferencia), '') <> '')
);

-- ---------------------------------------------------------------------
-- Devoluciones
-- ---------------------------------------------------------------------
create table public.devoluciones (
  id serial primary key,
  venta_item_id int not null references public.venta_items(id),
  venta_id int not null references public.ventas(id),
  ejemplar_id uuid not null references public.ejemplares(id),
  canal public.canal_venta not null,
  comprador_id uuid references public.perfiles(id),
  motivo text not null check (motivo in (
    'Defecto no informado', 'Páginas faltantes o dañadas', 'No era el libro pedido',
    'Llegó dañado en el envío', 'Ya lo tenía', 'Cambié de idea', 'Otro')),
  detalle text,
  defecto_no_informado boolean not null default false,
  forma_reintegro public.forma_reintegro not null,
  estado public.estado_devolucion not null default 'Solicitada',
  falla_biblioteca boolean not null default false,
  resultado_ejemplar public.estado_ejemplar check (resultado_ejemplar in ('En venta', 'Descartado')),
  importe_libro numeric(12,2),
  importe_envio numeric(12,2),
  importe_total numeric(12,2),
  nota_revision text,
  solicitada_por uuid references public.perfiles(id),
  revisada_por uuid references public.perfiles(id),
  created_at timestamptz not null default now(),
  resuelta_en timestamptz
);
-- Una sola devolución viva o aprobada por ítem vendido.
create unique index devoluciones_item_vivo on public.devoluciones (venta_item_id) where estado <> 'Rechazada';

alter table public.movimientos_dinero
  add constraint movimientos_devolucion_fk foreign key (devolucion_id) references public.devoluciones(id);
alter table public.movimientos_credito
  add constraint movcred_devolucion_fk foreign key (devolucion_id) references public.devoluciones(id);

-- ---------------------------------------------------------------------
-- Idempotencia: repetir la misma confirmación devuelve el mismo resultado.
-- ---------------------------------------------------------------------
create table public.operaciones (
  clave uuid primary key,
  funcion text not null,
  usuario_id uuid,
  resultado jsonb not null,
  created_at timestamptz not null default now()
);

-- >>> supabase/migrations/20261120000002_reglas.sql
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

-- >>> supabase/migrations/20261120000003_seguridad.sql
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

-- >>> supabase/migrations/20261120000004_datos_base.sql
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

-- >>> supabase/migrations/20261120000005_demo.sql
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

-- >>> supabase/migrations/20261120000006_informes.sql
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

-- >>> supabase/seed.sql
-- =====================================================================
-- Cuentas de prueba (Supabase Auth) + datos de demostración.
-- Ejecutar DESPUÉS de las migraciones (SQL Editor del proyecto o `supabase db reset`).
-- Todas las cuentas usan la contraseña: Porto2026!
-- Las cuentas quedan con el correo confirmado: no se envía ningún mail.
-- =====================================================================

do $$
declare
  v_email text;
  v_id uuid;
  v_cuentas text[] := array[
    'marta@porto.test', 'comision@porto.test', 'norma@porto.test', 'ruben@porto.test', 'julia@porto.test',
    'hugo@porto.test', 'carla@porto.test', 'elena@porto.test', 'tomas@porto.test', 'lucia@porto.test',
    'raul@porto.test', 'sofia@porto.test', 'andres@porto.test', 'beatriz@porto.test', 'ines@porto.test', 'diego@porto.test'];
begin
  foreach v_email in array v_cuentas loop
    select id into v_id from auth.users where email = v_email;
    if v_id is null then
      v_id := gen_random_uuid();
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token)
      values (
        '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
        extensions.crypt('Porto2026!', extensions.gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}', jsonb_build_object('nombre', split_part(v_email, '@', 1)),
        now(), now(), '', '', '', '');
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), v_id, v_id::text,
        jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now());
    end if;
  end loop;
end $$;

-- El trigger de alta creó los perfiles como «comprador»; la demo asigna los roles del personal.
select interno.cargar_demo();
