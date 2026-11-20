import { useState } from 'react';
import { Link } from 'react-router-dom';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, faltan, fecha, fechaHora, plata } from '../../lib/formato.js';
import { MOTIVOS_DEVOLUCION } from '../../lib/reglas.js';
import { useAuth } from '../../context/Auth.jsx';
import { AreaTexto, Aviso, Boton, Campo, Cargando, Estado, Modal, Selector, Tarjeta, Titulo, Vacio, useAccion, useDatos } from '../../components/ui.jsx';

const DIAS_DEVOLUCION = 7;

function SolicitarDevolucion({ item, onCerrar, onListo }) {
  const [motivo, setMotivo] = useState(MOTIVOS_DEVOLUCION[1]);
  const [detalle, setDetalle] = useState('');
  const [forma, setForma] = useState('credito');
  const acc = useAccion((clave) => rpc('solicitar_devolucion', {
    p_venta_item: item.venta_item_id, p_motivo: motivo, p_detalle: detalle,
    p_defecto_no_informado: ['Defecto no informado', 'Páginas faltantes o dañadas'].includes(motivo), p_forma: forma, p_idem: clave,
  }));
  return (
    <Modal abierto titulo="Devolver un libro" onCerrar={onCerrar}>
      <p className="mb-4 text-tinta/80">«{item.titulo}». Tenés {DIAS_DEVOLUCION} días corridos desde que lo recibiste. El costo del envío no se devuelve, salvo que la falla sea nuestra.</p>
      <div className="space-y-4">
        <Campo etiqueta="Motivo"><Selector value={motivo} onChange={(e) => setMotivo(e.target.value)}>{MOTIVOS_DEVOLUCION.map((m) => <option key={m}>{m}</option>)}</Selector></Campo>
        <Campo etiqueta="Contanos un poco más (opcional)"><AreaTexto value={detalle} onChange={(e) => setDetalle(e.target.value)} /></Campo>
        <fieldset>
          <legend className="mb-1 text-sm font-semibold text-tinta">¿Cómo querés el reintegro?</legend>
          <div className="grid grid-cols-2 gap-2">
            {[['credito', 'Crédito para la próxima compra'], ['efectivo', 'Efectivo en la biblioteca']].map(([v, t]) => (
              <label key={v} className={`cursor-pointer rounded-md p-3 ring-2 ${forma === v ? 'bg-tinta text-papel ring-tinta' : 'bg-papel-100 ring-tinta/20'}`}>
                <input type="radio" name="forma" value={v} checked={forma === v} onChange={() => setForma(v)} className="sr-only" />{t}
              </label>
            ))}
          </div>
        </fieldset>
        <Aviso error={acc.error} />
        <Boton className="w-full" tam="lg" cargando={acc.cargando} onClick={async () => { if (await acc.ejecutar()) onListo(); }}>Enviar solicitud</Boton>
      </div>
    </Modal>
  );
}

export default function MisPedidos() {
  const { perfil, recargarPerfil } = useAuth();
  const [devolver, setDevolver] = useState(null);
  const [aviso, setAviso] = useState(null);
  const { datos, error, cargando, recargar } = useDatos(async () => {
    await rpc('disponibilidad', { p_ids: [] }).catch(() => {});   // dispara el vencimiento de reservas
    const [pedidos, ventas, devs] = await Promise.all([
      consulta(supabase.from('pedidos').select(`*, zonas!pedidos_zona_id_fkey(nombre), recorridos!pedidos_recorrido_id_fkey(fecha),
        pedido_items(precio, precio_final, ejemplar_id, ejemplares(codigo, titulos(titulo, autor))),
        historial_pedido(estado, nota, fecha)`).order('created_at', { ascending: false })),
      consulta(supabase.from('ventas').select('id, canal, created_at, pedido_id, venta_items(id, ejemplar_id, precio_final, anulado, ejemplares(codigo, titulos(titulo)))').order('created_at', { ascending: false })),
      consulta(supabase.from('devoluciones').select('*').order('created_at', { ascending: false })),
    ]);
    return { pedidos, ventas, devs };
  });
  const cancelar = useAccion((_c, id) => rpc('cancelar_mi_pedido', { p_pedido: id }));

  if (cargando && !datos) return <Cargando />;
  const { pedidos = [], ventas = [], devs = [] } = datos || {};
  const devDe = (itemId) => devs.find((d) => d.venta_item_id === itemId && d.estado !== 'Rechazada') || devs.find((d) => d.venta_item_id === itemId);
  const mostrador = ventas.filter((v) => v.canal !== 'web');

  return (
    <div className="mx-auto max-w-3xl space-y-5">
      <Titulo sub={perfil?.numero_socio ? `Socio/a n.º ${perfil.numero_socio}` : null}
        accion={Number(perfil?.credito) > 0 ? <p className="rounded-md bg-pino px-3 py-2 font-semibold text-papel">Crédito a favor: {plata(perfil.credito)}</p> : null}>
        Mis pedidos
      </Titulo>
      <Aviso error={error || cancelar.error} exito={aviso} onCerrar={() => { setAviso(null); cancelar.limpiar(); }} onActualizar={recargar} />
      {!pedidos.length && !mostrador.length ? (
        <Vacio titulo="Todavía no hiciste ningún pedido"><Link to="/"><Boton>Ver libros disponibles</Boton></Link></Vacio>
      ) : null}
      {pedidos.map((p) => {
        const venta = ventas.find((v) => v.pedido_id === p.id);
        const plazoDev = p.entregado_en && (Date.now() - new Date(p.entregado_en)) < DIAS_DEVOLUCION * 864e5;
        return (
          <Tarjeta key={p.id} className="p-5">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p className="font-titulo text-xl font-bold text-tinta">Pedido #{p.numero}</p>
                <p className="text-sm text-tinta/70">{fechaHora(p.created_at)} · {p.modalidad === 'envio' ? `Envío a ${p.zonas?.nombre}` : 'Retiro en la biblioteca'}</p>
              </div>
              <Estado valor={p.estado} />
            </div>
            {p.estado === 'Reservado' ? (
              <p className="mt-3 rounded bg-mostaza-50 px-3 py-2 text-sm">Te lo guardamos hasta el <b>{fechaHora(p.reservado_hasta)}</b> (faltan {faltan(p.reservado_hasta)}). Coordiná el pago con la biblioteca.</p>
            ) : null}
            {p.recorridos?.fecha && ['Cobrado', 'Preparado', 'En reparto'].includes(p.estado) ? (
              <p className="mt-3 rounded bg-tinta-50 px-3 py-2 text-sm">Sale en el recorrido del <b>{diaSemana(p.recorridos.fecha)} {fecha(p.recorridos.fecha)}</b>, de 15 a 19.</p>
            ) : null}
            {p.estado === 'Retiro en biblioteca' ? (
              <p className="mt-3 rounded bg-lacre-50 px-3 py-2 text-sm text-lacre-700">Está listo para retirar en la biblioteca, de lunes a viernes de 8:30 a 12 y de 15 a 19. Lo guardamos 15 días.</p>
            ) : null}
            <ul className="mt-3 divide-y divide-dashed divide-tinta/20">
              {p.pedido_items.map((it) => {
                const vi = venta?.venta_items.find((x) => x.ejemplar_id === it.ejemplar_id);
                const dev = vi ? devDe(vi.id) : null;
                return (
                  <li key={it.ejemplar_id} className="flex items-center justify-between gap-3 py-2">
                    <div>
                      <p className="font-semibold text-tinta">{it.ejemplares?.titulos?.titulo}</p>
                      <p className="text-xs text-tinta/60">{it.ejemplares?.titulos?.autor} · {it.ejemplares?.codigo}</p>
                      {dev ? <p className="mt-1 text-sm">Devolución: <Estado valor={dev.estado} />{dev.importe_total ? ` · ${plata(dev.importe_total)} (${dev.forma_reintegro === 'credito' ? 'crédito' : 'efectivo'})` : ''}</p> : null}
                    </div>
                    <div className="text-right">
                      <p className="tabular-nums">{plata(it.precio_final)}</p>
                      {plazoDev && vi && !vi.anulado && !dev ? (
                        <button className="text-sm font-semibold text-lacre hover:underline"
                          onClick={() => setDevolver({ venta_item_id: vi.id, titulo: it.ejemplares?.titulos?.titulo })}>Devolver</button>
                      ) : null}
                    </div>
                  </li>
                );
              })}
            </ul>
            <div className="mt-2 flex flex-wrap items-center justify-between gap-2 border-t border-tinta/15 pt-3">
              <p className="text-sm text-tinta/70">
                {Number(p.descuento_socio) > 0 ? `Socio −${plata(p.descuento_socio)} · ` : ''}
                {p.modalidad === 'envio' ? `Envío ${Number(p.envio) ? plata(p.envio) : 'sin cargo'} · ` : ''}
                {Number(p.credito_usado) > 0 ? `Crédito −${plata(p.credito_usado)} · ` : ''}
                <b className="text-tinta">Total {plata(p.total)}</b>
              </p>
              {p.estado === 'Reservado' ? (
                <Boton tam="sm" variante="fantasma" cargando={cancelar.cargando}
                  onClick={async () => { if (await cancelar.ejecutar(p.id)) { setAviso('Pedido cancelado: los libros volvieron a los estantes.'); recargar(); recargarPerfil(); } }}>
                  Cancelar pedido
                </Boton>
              ) : null}
            </div>
            <details className="mt-2 text-sm text-tinta/70">
              <summary className="cursor-pointer">Historial</summary>
              <ol className="mt-2 space-y-1 border-l-2 border-tinta/20 pl-3">
                {[...p.historial_pedido].sort((a, b) => new Date(a.fecha) - new Date(b.fecha)).map((h, i) => (
                  <li key={i}><b>{h.estado}</b> · {fechaHora(h.fecha)}{h.nota ? ` — ${h.nota}` : ''}</li>
                ))}
              </ol>
            </details>
          </Tarjeta>
        );
      })}
      {mostrador.length ? (
        <div>
          <p className="mb-2 font-titulo text-lg font-bold text-tinta">Compras en el mostrador a tu nombre</p>
          {mostrador.map((v) => (
            <Tarjeta key={v.id} className="mb-2 p-4">
              <p className="text-sm text-tinta/70">{fechaHora(v.created_at)} · <Link className="underline" to={`/ticket/${v.id}`}>ver ticket</Link></p>
              {v.venta_items.map((vi) => {
                const dev = devDe(vi.id);
                const enPlazo = Date.now() - new Date(v.created_at) < DIAS_DEVOLUCION * 864e5;
                return (
                  <div key={vi.id} className="flex items-center justify-between py-1">
                    <span>{vi.ejemplares?.titulos?.titulo} {dev ? <Estado valor={dev.estado} /> : null}</span>
                    {enPlazo && !vi.anulado && !dev ? <button className="text-sm font-semibold text-lacre" onClick={() => setDevolver({ venta_item_id: vi.id, titulo: vi.ejemplares?.titulos?.titulo })}>Devolver</button> : <span className="tabular-nums">{plata(vi.precio_final)}</span>}
                  </div>
                );
              })}
            </Tarjeta>
          ))}
        </div>
      ) : null}
      {devolver ? (
        <SolicitarDevolucion item={devolver} onCerrar={() => setDevolver(null)}
          onListo={() => { setDevolver(null); setAviso('Recibimos tu pedido de devolución. Traé el libro a la biblioteca para revisarlo.'); recargar(); }} />
      ) : null}
    </div>
  );
}
