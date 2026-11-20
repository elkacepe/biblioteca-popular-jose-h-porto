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
