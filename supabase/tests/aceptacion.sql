-- =====================================================================
-- Pruebas de los criterios de aceptación (Postgres local con el stub de auth).
-- Uso: supabase/tests/run_local.sh && psql ... -f supabase/tests/aceptacion.sql
-- Cada bloque se ejecuta en una transacción que se deshace al final.
-- =====================================================================
\set ON_ERROR_STOP 1
\pset footer off

create schema if not exists prueba;
create or replace function prueba.como(p_email text) returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claim.sub', (select id::text from public.perfiles where email = p_email), true);
  perform set_config('role', 'authenticated', true);
end $$;
create or replace function prueba.anonimo() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'anon', true);
end $$;
create or replace function prueba.admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
create or replace function prueba.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'FALLÓ: %', p_msg; end if;
  raise notice 'ok  %', p_msg;
end $$;
-- Ejecuta y devuelve el mensaje de error (o null si no falló).
create or replace function prueba.error_de(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end $$;
grant usage on schema prueba to anon, authenticated;
grant execute on all functions in schema prueba to anon, authenticated;

-- ---------------------------------------------------------------------
\echo '== 1. Un ejemplar reservado / en feria / vendido deja de figurar en los demás canales'
begin;
do $$
declare v_ej uuid; v_res jsonb; v_err text; v_feria_ej uuid; v_j jsonb;
begin
  perform prueba.admin();
  select id into v_ej from ejemplares where estado = 'En venta' order by codigo limit 1;
  select e.id into v_feria_ej from ejemplares e where estado = 'En feria' limit 1;

  perform prueba.anonimo();
  perform prueba.ok(exists (select 1 from catalogo_publico(null, null, 100, 0) c where c.id = v_ej), 'el libro en venta figura en la web');
  perform prueba.ok(not exists (select 1 from catalogo_publico(null, null, 100, 0) c where c.id = v_feria_ej)
    and not exists (select 1 from catalogo_publico(null, null, 1000, 0) c where c.id = v_feria_ej), 'un libro En feria no figura en la web');

  perform prueba.como('elena@porto.test');
  v_res := crear_pedido(array[v_ej], 'retiro', null, null, null, null, gen_random_uuid());
  perform prueba.ok((select estado from ejemplares where id = v_ej) = 'Reservado', 'al pedir por la web el ejemplar queda Reservado');

  perform prueba.anonimo();
  perform prueba.ok(not exists (select 1 from catalogo_publico(null, null, 100, 0) c where c.id = v_ej), 'el reservado ya no figura en la web');

  perform prueba.como('julia@porto.test');
  v_j := abrir_jornada();
  perform prueba.ok(not exists (select 1 from mostrador_buscar('') m where m.id = v_ej), 'el reservado no aparece en el mostrador');
  v_err := prueba.error_de(format('select vender_mostrador(%s, array[%L]::uuid[], ''efectivo'')', v_j->>'id', v_ej));
  perform prueba.ok(v_err like 'Este libro ya encontró dueño%', 'vender en mostrador un reservado da un mensaje claro: ' || v_err);

  perform prueba.como('marta@porto.test');
  v_err := prueba.error_de(format('select agregar_a_caja((select id from cajas_feria where activa limit 1), %L)',
                                  (select codigo from ejemplares where id = v_ej)));
  perform prueba.ok(v_err like '%solo van a la feria libros en venta%', 'un reservado no puede ir a una caja de feria');
end $$;
rollback;

\echo '== 1b. Dos ventas simultáneas del mismo ejemplar: una sola venta (ver prueba de concurrencia en run_concurrencia.sh)'

-- ---------------------------------------------------------------------
\echo '== 2. Reserva web sin cobro a las 48 h se cancela sola'
begin;
do $$
declare v_ped int; v_ids uuid[];
begin
  perform prueba.admin();
  select id into v_ped from pedidos where estado = 'Reservado' and reservado_hasta < now();
  perform prueba.ok(v_ped is not null, 'la demo trae una reserva vencida (Lucía, hace 49 h)');
  v_ids := array(select ejemplar_id from pedido_items where pedido_id = v_ped);
  perform prueba.anonimo();
  perform count(*) from catalogo_publico();   -- cualquier consulta dispara el mantenimiento
  perform prueba.admin();
  perform prueba.ok((select estado from pedidos where id = v_ped) = 'Cancelado', 'el pedido vencido quedó Cancelado');
  perform prueba.ok((select bool_and(estado = 'En venta' and pedido_id is null) from ejemplares where id = any(v_ids)),
    'sus ejemplares volvieron a En venta');
  perform prueba.como('marta@porto.test');
  perform prueba.ok(prueba.error_de(format('select registrar_cobro(%s, ''efectivo'')', v_ped)) like '%ya está cancelado%',
    'registrar el cobro de una reserva vencida se rechaza');
end $$;
rollback;

-- ---------------------------------------------------------------------
\echo '== 3. El primer ejemplar de un título ausente del acervo va al acervo y no se vende'
begin;
do $$
declare v_lote jsonb; a jsonb; b jsonb; c jsonb; v_err text;
begin
  perform prueba.como('marta@porto.test');
  v_lote := crear_lote('Prueba de aceptación', false);
  a := cargar_ejemplar((v_lote->>'id')::int, 'Viaje al centro de la Tierra', 'Julio Verne', 'Acme', 1864::smallint,
        (select id from categorias where nombre = 'Juvenil'), 'Bueno');
  b := cargar_ejemplar((v_lote->>'id')::int, 'viaje al centro de la tierra ', 'julio verne', 'Acme', 1864::smallint,
        (select id from categorias where nombre = 'Juvenil'), 'Muy bueno');
  c := cargar_ejemplar((v_lote->>'id')::int, 'Viaje al centro de la Tierra', 'Julio Verne', null, null,
        (select id from categorias where nombre = 'Juvenil'), 'Muy malo', null, 'Lomo partido y moho', true);
  perform prueba.ok(a->>'estado' = 'Acervo', 'primer ejemplar → Acervo');
  perform prueba.ok(b->>'estado' = 'En clasificación' and (b->>'precio_sugerido')::numeric = 3000, 'segundo ejemplar → habilitado para la venta, sugerido $3.000');
  perform prueba.ok(c->>'estado' = 'Descartado', 'ejemplar en muy mal estado → Descartado con motivo');
  v_err := prueba.error_de(format('select publicar_ejemplar(%L, 3000)', a->>'id'));
  perform prueba.ok(v_err like '%acervo%no se pone en venta%', 'publicar el del acervo se rechaza: ' || v_err);
  perform publicar_ejemplar((b->>'id')::uuid, 2800);
  perform prueba.ok((select estado = 'En venta' and precio = 2800 from ejemplares where id = (b->>'id')::uuid), 'el segundo se publica con precio editado');
  perform prueba.ok((select count(*) from traslados where ejemplar_id = (b->>'id')::uuid) = 1, 'el ingreso quedó registrado como traslado');
end $$;
rollback;

-- ---------------------------------------------------------------------
\echo '== 4. Precio sugerido = categoría × estado; sin descuento de socio en feria'
begin;
do $$
declare v_feria int; v_ids uuid[]; v_res jsonb; v_cot jsonb; v_ej uuid;
begin
  perform prueba.admin();
  perform prueba.ok(interno.precio_sugerido((select id from categorias where nombre = 'Novela'), 'Bueno') = 3200, 'Novela Bueno = $3.200');
  perform prueba.ok(interno.precio_sugerido((select id from categorias where nombre = 'Poesía'), 'Regular') = 1800, 'Poesía Regular = $1.750 → $1.800');
  perform prueba.ok(interno.precio_sugerido((select id from categorias where nombre = 'Colección de tapa dura'), 'Muy bueno') = 6000, 'Tapa dura Muy bueno = $6.000');
  perform prueba.ok(interno.precio_sugerido((select id from categorias where nombre = 'Manual escolar'), 'Regular') = 800, 'Manual Regular = $750 → $800');

  select id into v_feria from ferias where estado = 'Planificada';
  v_ids := array(select e.id from ejemplares e join cajas_feria k on k.id = e.caja_feria_id where k.feria_id = v_feria order by e.precio desc limit 2);
  perform prueba.como('norma@porto.test');
  perform abrir_feria(v_feria);
  v_res := vender_feria(v_feria, v_ids, 'efectivo', gen_random_uuid());
  perform prueba.ok((v_res->>'total')::numeric = (select sum(precio) from ejemplares where id = any(v_ids)),
    'en feria 2 libros se cobran completos (sin descuento de socio ni promo)');
  perform prueba.ok(not exists (select 1 from ventas where id = (v_res->>'venta_id')::int and descuento_socio <> 0), 'venta de feria sin descuento de socio');

  -- Web: Elena es socia con cuota al día → 15 %.
  perform prueba.admin();
  select id into v_ej from ejemplares where estado = 'En venta' and precio = 3200 limit 1;
  perform prueba.como('elena@porto.test');
  v_cot := cotizar_pedido(array[v_ej], 'retiro');
  perform prueba.ok((v_cot->>'descuento_socio')::numeric = 480 and (v_cot->>'total')::numeric = 2720, 'socia al día en la web: $3.200 − 15 % = $2.720');
  perform prueba.como('tomas@porto.test');
  v_cot := cotizar_pedido(array[v_ej], 'retiro');
  perform prueba.ok((v_cot->>'descuento_socio')::numeric = 0, 'socio con cuota vencida: sin descuento');
end $$;
rollback;

-- ---------------------------------------------------------------------
\echo '== 5. Promoción de feria: el más barato de cada grupo de 3 va sin cargo'
begin;
do $$
declare v_feria int; v_caja int; v_all uuid[]; v_ids uuid[]; v_res jsonb;
begin
  perform prueba.admin();
  select id into v_feria from ferias where estado = 'Planificada';
  select id into v_caja from cajas_feria where feria_id = v_feria order by numero limit 1;
  update ferias set estado = 'Abierta' where id = v_feria;
  -- 7 ejemplares de la caja 1 con precios conocidos: 6000, 5000, 4000, 3000, 2500, 2000, 1500.
  v_all := array(select id from ejemplares where caja_feria_id = v_caja order by codigo limit 7);
  update ejemplares set precio = (array[6000, 5000, 4000, 3000, 2500, 2000, 1500])[x.n]
  from (select id, row_number() over (order by codigo) n from ejemplares where id = any(v_all)) x where x.id = ejemplares.id;
  perform prueba.como('ruben@porto.test');
  -- 2 libros: no forman grupo.
  v_ids := v_all[1:2];
  v_res := vender_feria(v_feria, v_ids, 'efectivo');
  perform prueba.ok((v_res->>'descuento_promo')::numeric = 0 and (v_res->>'total')::numeric = 11000, 'dos libros ($11.000) no forman grupo: sin bonificación');
  -- 5 libros: 4000, 3000, 2500, 2000, 1500 → grupo [4000, 3000, 2500] → $2.500 sin cargo; quedan 2 sueltos.
  v_ids := v_all[3:7];
  v_res := vender_feria(v_feria, v_ids, 'transferencia');
  perform prueba.ok((v_res->>'descuento_promo')::numeric = 2500 and (v_res->>'total')::numeric = 10500,
    '5 libros ($13.000): bonifica $2.500 (el más barato del grupo completo) → $10.500');
  perform prueba.admin();
  perform prueba.ok((select count(*) from venta_items where venta_id = (v_res->>'venta_id')::int and promo_sin_cargo) = 1, 'un solo ítem sin cargo');
end $$;
rollback;

begin;
do $$
declare v_ids uuid[]; v_promo numeric;
begin
  perform prueba.admin();
  -- 6 ejemplares cualquiera con precios fijados: 6000, 5000, 4000, 3000, 2500, 2000 → sin cargo 4000 y 2000.
  v_ids := array(select id from ejemplares where estado = 'En venta' order by codigo limit 6);
  update ejemplares set precio = (array[6000, 5000, 4000, 3000, 2500, 2000])[x.n]
  from (select id, row_number() over (order by codigo) n from ejemplares where id = any(v_ids)) x where x.id = ejemplares.id;
  select sum(case when sin_cargo then precio else 0 end) into v_promo from interno.promo_feria(v_ids);
  perform prueba.ok(v_promo = 6000, '6 libros → dos grupos: bonifica $4.000 + $2.000');
end $$;
rollback;

-- ---------------------------------------------------------------------
\echo '== 6. Un recorrido no acepta más entregas que su cupo; sin lugar pasa al siguiente'
begin;
do $$
declare v_rec int; v_sig int; v_ped int; v_res jsonb; k int; v_ids uuid[]; v_fecha date; v_zona smallint;
begin
  perform prueba.admin();
  select id into v_zona from zonas where nombre = 'Centro';
  -- El primer recorrido de Centro que todavía acepta pedidos.
  select r.id, r.fecha into v_rec, v_fecha from recorridos r
   where r.zona_id = v_zona and r.estado = 'Programado' and (r.fecha - 1) + time '12:00' > interno.ahora_local()
   order by fecha limit 1;
  perform prueba.ok((select cupo_disponible from recorridos where id = v_rec) between 0 and 12, 'cupo inicial dentro de rango');
  update recorridos set cupo_disponible = 1 where id = v_rec;   -- queda un solo lugar
  for k in 1..2 loop
    perform prueba.admin();
    v_ids := interno.demo_tomar(1);
    perform prueba.como('lucia@porto.test');
    v_res := crear_pedido(v_ids, 'envio', v_zona, 'San Martín 870', null, null, gen_random_uuid());
    perform prueba.como('marta@porto.test');
    v_res := registrar_cobro((v_res->>'pedido_id')::int, 'efectivo', gen_random_uuid());
    if k = 1 then
      perform prueba.ok((v_res->>'recorrido_id')::int = v_rec, 'el pedido 1 toma el último lugar del recorrido del ' || v_fecha);
    else
      perform prueba.ok((v_res->>'recorrido_id')::int <> v_rec and (v_res->>'recorrido_fecha')::date > v_fecha,
        'el pedido 2 pasa al siguiente recorrido de Centro: ' || (v_res->>'recorrido_fecha'));
    end if;
  end loop;
  perform prueba.admin();
  perform prueba.ok((select cupo_disponible from recorridos where id = v_rec) = 0, 'el recorrido quedó en cero, nunca negativo');
  perform prueba.ok(prueba.error_de(format('update recorridos set cupo_disponible = -1 where id = %s', v_rec)) like '%check%',
    'la base rechaza un cupo negativo');
end $$;
rollback;

-- ---------------------------------------------------------------------
\echo '== 7. Dos entregas fallidas → Retiro en biblioteca; 15 días sin retirar → Cancelado'
begin;
do $$
declare v_ent int; v_ped int; v_res jsonb; v_ent2 int; v_ids uuid[];
begin
  perform prueba.admin();
  update recorridos r set cupo_disponible = cupo_total where estado = 'Programado';
  select e.id, e.pedido_id into v_ent, v_ped from entregas e join recorridos r on r.id = e.recorrido_id
   join zonas z on z.id = r.zona_id where z.nombre = 'Centro' and e.resultado = 'Pendiente' and e.intento = 1 limit 1;
  perform prueba.como('hugo@porto.test');
  v_res := marcar_entrega(v_ent, false, 'No había nadie', gen_random_uuid());
  perform prueba.ok(v_res->>'reprogramado_para' is not null, 'primera falla: se reprograma para ' || (v_res->>'reprogramado_para'));
  perform prueba.admin();
  perform prueba.ok((select estado = 'Preparado' and intentos_fallidos = 1 from pedidos where id = v_ped), 'pedido Preparado con 1 intento fallido');
  select id into v_ent2 from entregas where pedido_id = v_ped and resultado = 'Pendiente';
  -- El repartidor del siguiente recorrido marca la segunda falla.
  update recorridos set repartidor_id = (select id from perfiles where email = 'hugo@porto.test')
   where id = (select recorrido_id from entregas where id = v_ent2);
  perform prueba.como('hugo@porto.test');
  v_res := marcar_entrega(v_ent2, false, 'No había nadie otra vez');
  perform prueba.admin();
  perform prueba.ok((select estado from pedidos where id = v_ped) = 'Retiro en biblioteca', 'segunda falla → Retiro en biblioteca');
  -- Repetir la misma confirmación no cambia nada.
  perform prueba.como('hugo@porto.test');
  v_res := marcar_entrega(v_ent2, false, 'No había nadie otra vez');
  perform prueba.ok((v_res->>'repetida')::boolean, 'confirmar dos veces no duplica efectos');
  -- 15 días sin retirar.
  perform prueba.admin();
  v_ids := array(select ejemplar_id from pedido_items where pedido_id = v_ped);
  update pedidos set retiro_desde = now() - interval '16 days' where id = v_ped;
  perform interno.mantenimiento();
  perform prueba.ok((select estado from pedidos where id = v_ped) = 'Cancelado', 'a los 15 días sin retirar se cancela');
  perform prueba.ok((select bool_and(estado = 'En venta') from ejemplares where id = any(v_ids)), 'y los ejemplares vuelven a En venta');
end $$;
rollback;

-- ---------------------------------------------------------------------
\echo '== 8. Devolución aprobada dentro de 7 días: reintegro y ejemplar En venta o Descartado'
begin;
do $$
declare v_dev int; v_cred numeric; v_res jsonb; v_ej uuid; v_item int; v_err text; v_mov numeric;
begin
  perform prueba.admin();
  select d.id, d.ejemplar_id into v_dev, v_ej from devoluciones d where estado = 'Solicitada' limit 1;
  select credito into v_cred from perfiles p join devoluciones d on d.comprador_id = p.id where d.id = v_dev;
  perform prueba.como('marta@porto.test');
  perform tomar_devolucion(v_dev);
  perform prueba.admin();
  perform prueba.ok((select estado from ejemplares where id = v_ej) = 'En devolución', 'en revisión el ejemplar queda En devolución');
  perform prueba.como('marta@porto.test');
  v_res := resolver_devolucion(v_dev, true, 'En venta', false, null, gen_random_uuid());
  v_res := resolver_devolucion(v_dev, true, 'En venta', false, null, gen_random_uuid());   -- repetida
  perform prueba.admin();
  perform prueba.ok((select credito from perfiles p join devoluciones d on d.comprador_id = p.id where d.id = v_dev)
     = v_cred + (select importe_total from devoluciones where id = v_dev), 'el importe vuelve como crédito una sola vez');
  perform prueba.ok((select importe_envio from devoluciones where id = v_dev) = 0, 'el envío no se devuelve si la falla no es de la biblioteca');
  perform prueba.ok((select estado from ejemplares where id = v_ej) = 'En venta', 'el ejemplar vuelve a En venta');

  -- Fuera de término (8 días) se rechaza.
  select vi.id into v_item from venta_items vi join ventas v on v.id = vi.venta_id
   where v.canal = 'mostrador' and not vi.anulado order by v.created_at limit 1;
  update ventas set created_at = now() - interval '8 days' where id = (select venta_id from venta_items where id = v_item);
  perform prueba.como('marta@porto.test');
  v_err := prueba.error_de(format('select solicitar_devolucion(%s, ''Cambié de idea'')', v_item));
  perform prueba.ok(v_err like 'Pasaron más de 7 días%', 'fuera de los 7 días: ' || v_err);

  -- Mostrador reciente, efectivo, descartado.
  perform prueba.admin();
  update ventas set created_at = now() - interval '2 days' where id = (select venta_id from venta_items where id = v_item);
  select precio_final into v_mov from venta_items where id = v_item;
  perform prueba.como('marta@porto.test');
  v_res := solicitar_devolucion(v_item, 'Páginas faltantes o dañadas', 'Faltan hojas', true, 'efectivo');
  v_dev := (v_res->>'devolucion_id')::int;
  v_res := resolver_devolucion(v_dev, true, 'Descartado', true, 'Faltan hojas');
  perform prueba.admin();
  perform prueba.ok((select estado from ejemplares e join venta_items i on i.ejemplar_id = e.id where i.id = v_item) = 'Descartado', 'aprobada y descartada');
  perform prueba.ok(exists (select 1 from movimientos_dinero where tipo = 'reintegro' and importe = -v_mov
                            and devolucion_id = v_dev), 'reintegro en efectivo registrado en el libro de dinero');

  -- Feria sin defecto no informado: no se acepta.
  select vi.id into v_item from venta_items vi join ventas v on v.id = vi.venta_id where v.canal = 'feria' limit 1;
  update ventas set created_at = now() - interval '1 day' where id = (select venta_id from venta_items where id = v_item);
  perform prueba.como('marta@porto.test');
  v_err := prueba.error_de(format('select solicitar_devolucion(%s, ''Cambié de idea'')', v_item));
  perform prueba.ok(v_err like 'En la feria solo%', 'feria sin defecto no informado: ' || v_err);
end $$;
rollback;

-- ---------------------------------------------------------------------
\echo '== 9. Cierre de feria: sobrantes al depósito, rendición bloqueada con diferencia'
begin;
do $$
declare v_feria int; v_res jsonb; v_ids uuid[]; v_sobr uuid[]; v_err text; v_arq int; v_venta jsonb;
begin
  perform prueba.admin();
  select id into v_feria from ferias where estado = 'Planificada';
  v_ids := array(select e.id from ejemplares e join cajas_feria k on k.id = e.caja_feria_id where k.feria_id = v_feria limit 3);
  perform prueba.como('norma@porto.test');
  perform abrir_feria(v_feria);
  v_venta := vender_feria(v_feria, v_ids, 'efectivo');
  perform prueba.admin();
  v_sobr := array(select e.id from ejemplares e join cajas_feria k on k.id = e.caja_feria_id where k.feria_id = v_feria and e.estado = 'En feria');
  perform prueba.como('norma@porto.test');
  v_err := prueba.error_de(format('select cerrar_feria(%s, 0, 0)', v_feria));
  perform prueba.ok(v_err like 'Hay una diferencia%', 'sin motivo no se cierra con diferencia');
  v_res := cerrar_feria(v_feria, (v_venta->>'total')::numeric - 200, 0, 'Se dio mal un vuelto', gen_random_uuid());
  perform prueba.ok((v_res->>'diferencia')::numeric = -200, 'diferencia registrada: −$200');
  perform prueba.admin();
  perform prueba.ok((select bool_and(e.estado = 'En venta' and e.ubicacion_id = e.ubicacion_deposito_id and e.caja_feria_id is null)
                     from ejemplares e where e.id = any(v_sobr)), cardinality(v_sobr) || ' sobrantes volvieron a En venta y a su estante');
  perform prueba.ok((select count(*) from traslados where ejemplar_id = any(v_sobr) and automatico and motivo like 'Cierre de la feria%') = cardinality(v_sobr),
    'cada regreso quedó como traslado automático');
  perform prueba.ok((select bool_and(cupo_disponible = cupo_total and not activa) from cajas_feria where feria_id = v_feria), 'el cupo de las cajas se liberó');
  select id into v_arq from arqueos where feria_id = v_feria;
  v_err := prueba.error_de(format('update arqueos set efectivo_contado = 999 where id = %s', v_arq));
  perform prueba.ok(v_err like 'La rendición está cerrada%', 'la rendición queda bloqueada');
  perform prueba.como('norma@porto.test');
  v_err := prueba.error_de(format('select nota_rendicion(%s, ''hola'')', v_arq));
  perform prueba.ok(v_err like '%permiso%', 'la voluntaria no puede agregar notas');
  perform prueba.como('marta@porto.test');
  perform nota_rendicion(v_arq, 'Revisado con la comisión');
  perform prueba.admin();
  perform prueba.ok((select nota_bibliotecaria like '%Revisado%' from arqueos where id = v_arq), 'la bibliotecaria sí agrega la nota');
  perform prueba.como('norma@porto.test');
  v_res := cerrar_feria(v_feria, 1, 1, 'otra vez');
  perform prueba.ok((v_res->>'repetida')::boolean and (v_res->>'diferencia')::numeric = -200, 'cerrar dos veces no cambia la rendición');
  v_err := prueba.error_de(format('select vender_feria(%s, array[%L]::uuid[], ''efectivo'')', v_feria, v_sobr[1]));
  perform prueba.ok(v_err like '%cerró%', 'con la feria cerrada no se vende');
end $$;
rollback;

-- ---------------------------------------------------------------------
\echo '== 10. RLS: cada voluntario ve solo su recorrido o su caja'
begin;
do $$
declare v_carla_rec int; v_n int; v_err text;
begin
  perform prueba.como('hugo@porto.test');
  perform prueba.ok((select count(*) from recorridos) > 0 and not exists (select 1 from recorridos r join perfiles p on p.id = r.repartidor_id where p.email <> 'hugo@porto.test'),
    'Hugo solo ve sus recorridos');
  perform prueba.admin();
  select id into v_carla_rec from recorridos r where repartidor_id = (select id from perfiles where email = 'carla@porto.test') limit 1;
  perform prueba.como('hugo@porto.test');
  perform prueba.ok(not exists (select 1 from recorridos where id = v_carla_rec), 'cambiar el id no muestra el recorrido de Carla');
  perform prueba.ok(not exists (select 1 from entregas where recorrido_id = v_carla_rec), 'ni sus entregas');
  v_err := prueba.error_de(format('select hoja_recorrido(%s)', v_carla_rec));
  perform prueba.ok(v_err like '%permiso%', 'ni su hoja por la función: ' || v_err);
  perform prueba.ok(not exists (select 1 from pedidos p where p.id not in (select pedido_id from entregas)), 'Hugo solo ve pedidos de sus entregas');
  perform prueba.ok((select count(*) from ventas) = 0 and (select count(*) from movimientos_dinero) = 0, 'Hugo no ve ventas ni dinero');

  perform prueba.como('norma@porto.test');
  perform prueba.ok((select count(distinct feria_id) from cajas_feria) = (select count(*) from asignaciones where tipo = 'feria'),
    'Norma solo ve las cajas de sus ferias');
  perform prueba.ok(not exists (select 1 from ejemplares where caja_feria_id is null), 'Norma solo ve ejemplares de sus cajas');
  perform prueba.ok((select count(*) from pedidos) = 0, 'Norma no ve pedidos web');
  v_err := prueba.error_de('select vender_mostrador((select id from jornadas_mostrador limit 1), array[]::uuid[], ''efectivo'')');
  perform prueba.ok(v_err like '%permiso%', 'Norma no opera el mostrador (no está asignada)');

  perform prueba.como('julia@porto.test');
  perform prueba.ok((select count(*) from cajas_feria) = 0, 'Julia (mostrador) no ve cajas de feria');

  perform prueba.como('lucia@porto.test');
  perform prueba.ok(not exists (select 1 from pedidos p join perfiles u on u.id = p.comprador_id where u.email <> 'lucia@porto.test'), 'una compradora solo ve sus pedidos');
  perform prueba.ok((select count(*) from perfiles) = 1, 'y solo su perfil');
  v_err := prueba.error_de('update perfiles set rol = ''bibliotecaria'' where id = auth.uid()');
  perform prueba.ok(v_err like '%permission denied%', 'no puede cambiarse el rol: ' || v_err);
  perform prueba.ok((select count(*) from lotes) = 0, 'no ve las donaciones');

  perform prueba.anonimo();
  v_err := prueba.error_de('select * from ejemplares');
  perform prueba.ok(v_err like '%permission denied%', 'un anónimo no lee la tabla privada de ejemplares');
  v_err := prueba.error_de('select crear_pedido(array[]::uuid[], ''retiro'')');
  perform prueba.ok(v_err like '%permission denied%', 'ni ejecuta funciones de compra');

  perform prueba.como('comision@porto.test');
  v_err := prueba.error_de('select crear_lote(''x'', false)');
  perform prueba.ok(v_err like '%permiso%', 'la comisión consulta pero no edita');
  perform prueba.ok((select count(*) from movimientos_dinero) > 0, 'la comisión ve los movimientos');
end $$;
rollback;

-- ---------------------------------------------------------------------
\echo '== 11. Informes = movimientos y respetan filtros'
begin;
do $$
declare v_total numeric; v_inf numeric; v_feria numeric; v_hoy date; v_mov30 numeric;
begin
  perform prueba.admin();
  v_hoy := interno.hoy();
  select coalesce(sum(importe), 0) into v_mov30 from movimientos_dinero
   where (fecha at time zone 'America/Argentina/Cordoba')::date between v_hoy - 30 and v_hoy;
  perform prueba.como('comision@porto.test');
  select sum(importe) into v_total from movimientos_dinero;
  select sum(neto) into v_inf from informe_recaudacion(null, null, null);
  perform prueba.ok(v_total = v_inf, format('recaudación total del informe ($%s) = suma de movimientos ($%s)', v_inf, v_total));
  select sum(neto) into v_feria from informe_recaudacion(null, null, 'feria');
  perform prueba.ok(v_feria = (select sum(importe) from movimientos_dinero where canal = 'feria'), 'filtro por canal feria coincide');
  perform prueba.ok((select coalesce(sum(neto), 0) from informe_recaudacion(v_hoy - 30, v_hoy, null)) = v_mov30,
       'filtro por fechas coincide ($' || v_mov30 || ')');
  perform prueba.ok((select sum(cantidad) from informe_mas_vendidos(null, null, null, 'titulo'))
       = (select count(*) from venta_items where not anulado), 'títulos más vendidos cuenta todos los ítems no anulados');
  perform prueba.ok((select count(*) from informe_antiguedad(180)) > 0, 'hay ejemplares con más de 180 días en depósito');
  perform prueba.ok((select count(*) from informe_entregas_fallidas(null, null)) >= 3, 'entregas fallidas listadas');
end $$;
rollback;

\echo '== Todas las pruebas pasaron =='
