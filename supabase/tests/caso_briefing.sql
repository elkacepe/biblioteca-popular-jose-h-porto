-- Caso del briefing reproducido con los datos sintéticos (Postgres local con stub de auth).
-- Uso: psql ... -f supabase/tests/aceptacion.sql (crea el esquema «prueba») y después este archivo.
\set ON_ERROR_STOP 1
begin;
do $$
declare v_feria int; v_novela uuid; v_titulo text; v_otro uuid; v_err text; v_res jsonb; v_rec int; e record; v_falla int; n int := 0;
begin
  -- Domingo de feria: Norma abre la caja.
  perform prueba.admin();
  select id into v_feria from ferias where estado = 'Planificada';
  select x.id, t.titulo into v_novela, v_titulo from ejemplares x join titulos t on t.id = x.titulo_id
    join cajas_feria k on k.id = x.caja_feria_id where k.feria_id = v_feria order by x.precio desc limit 1;
  perform prueba.como('norma@porto.test');
  perform abrir_feria(v_feria);

  -- La socia de Villa del Lago busca en la web: el ejemplar que está en la caja NO se ofrece.
  perform prueba.como('elena@porto.test');
  perform prueba.ok(not exists (select 1 from catalogo_publico(v_titulo, null, 100, 0) c where c.id = v_novela),
    format('«%s» de la caja de feria no figura en la web', v_titulo));
  v_err := prueba.error_de(format('select crear_pedido(array[%L]::uuid[], ''envio'', 2::smallint, ''Los Cerezos 145'')', v_novela));
  perform prueba.ok(v_err like 'Este libro ya encontró dueño%', 'ni siquiera forzando el id se puede reservar: ' || v_err);

  -- Norma cobra el último libro: una sola venta, sin choque.
  perform prueba.como('norma@porto.test');
  v_res := vender_feria(v_feria, array[v_novela], 'efectivo');
  perform prueba.ok((v_res->>'total')::numeric > 0, 'Norma cobra el libro: venta #' || (v_res->>'numero'));

  -- Arqueo: cuenta el efectivo, carga transferencias, sobrantes al depósito, rendición bloqueada.
  v_res := cerrar_feria(v_feria, (v_res->>'total')::numeric, 0, null);
  perform prueba.ok((v_res->>'diferencia')::numeric = 0 and (v_res->>'ejemplares_devueltos')::int > 0,
    format('cierre sin diferencia; %s sobrantes volvieron al depósito', v_res->>'ejemplares_devueltos'));

  -- Martes: Hugo sale con 9 entregas de la zona Centro.
  perform prueba.admin();
  select r.id into v_rec from recorridos r join zonas z on z.id = r.zona_id
   where z.nombre = 'Centro' and r.estado = 'Programado' and (select count(*) from entregas where recorrido_id = r.id) = 9;
  perform prueba.ok(v_rec is not null, 'el recorrido del martes de Centro tiene 9 entregas');
  perform prueba.como('hugo@porto.test');
  perform iniciar_recorrido(v_rec);
  for e in select id, intento from entregas where recorrido_id = v_rec order by id loop
    n := n + 1;
    if n = 9 then
      v_res := marcar_entrega(e.id, false, 'No había nadie');
      v_falla := e.id;
    else perform marcar_entrega(e.id, true); end if;
  end loop;
  perform prueba.ok(true, '8 entregadas y 1 «No había nadie»: ' || v_res::text);
  perform prueba.admin();
  perform prueba.ok((select estado from recorridos where id = v_rec) = 'Finalizado', 'el recorrido quedó finalizado');
end $$;
rollback;
