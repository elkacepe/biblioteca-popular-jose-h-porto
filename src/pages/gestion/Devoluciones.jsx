import { useState } from 'react';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { fecha, fechaHora, plata } from '../../lib/formato.js';
import { MOTIVOS_DEVOLUCION } from '../../lib/reglas.js';
import { AreaTexto, Aviso, Boton, Campo, Cargando, Entrada, Estado, Modal, Pestanas, Selector, Tarjeta, Titulo, Vacio, useAccion, useDatos } from '../../components/ui.jsx';

function Resolver({ d, onCambio }) {
  const [nota, setNota] = useState('');
  const [falla, setFalla] = useState(false);
  const tomar = useAccion(() => rpc('tomar_devolucion', { p_devolucion: d.id }));
  const resolver = useAccion((clave, aprobar, resultado) => rpc('resolver_devolucion', {
    p_devolucion: d.id, p_aprobar: aprobar, p_resultado_ejemplar: resultado, p_falla_biblioteca: falla, p_nota: nota, p_idem: clave,
  }));
  const fin = (msg) => (r) => { if (r !== undefined) onCambio(typeof msg === 'function' ? msg(r) : msg); };
  const err = tomar.error || resolver.error;
  if (!['Solicitada', 'En revisión'].includes(d.estado)) return null;
  return (
    <div className="mt-3 space-y-3 border-t border-dashed border-tinta/20 pt-3">
      <Aviso error={err} onActualizar={() => onCambio()} onCerrar={() => { tomar.limpiar(); resolver.limpiar(); }} />
      {d.estado === 'Solicitada' ? (
        <Boton tam="sm" cargando={tomar.cargando} onClick={() => tomar.ejecutar().then(fin(`Devolución #${d.id}: el libro pasó a revisión.`))}>Recibí el libro: revisar</Boton>
      ) : null}
      <Campo etiqueta="Nota de la revisión"><AreaTexto rows={2} value={nota} onChange={(e) => setNota(e.target.value)} placeholder="Estado en que llegó, qué se decidió…" /></Campo>
      {d.canal === 'web' ? (
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" className="h-5 w-5 accent-tinta" checked={falla} onChange={(e) => setFalla(e.target.checked)} />
          La falla fue de la biblioteca (se devuelve también el envío)</label>
      ) : null}
      <div className="flex flex-wrap gap-2">
        <Boton tam="sm" variante="exito" cargando={resolver.cargando} onClick={() => resolver.ejecutar(true, 'En venta').then(fin((r) => `Aprobada: se reintegran ${plata(r.importe)} en ${r.forma === 'credito' ? 'crédito' : 'efectivo'} y el libro vuelve a la venta.`))}>Aprobar · vuelve a la venta</Boton>
        <Boton tam="sm" variante="aviso" cargando={resolver.cargando} disabled={!nota.trim()} onClick={() => resolver.ejecutar(true, 'Descartado').then(fin((r) => `Aprobada: se reintegran ${plata(r.importe)} y el ejemplar se descarta.`))}>Aprobar · descartar</Boton>
        <Boton tam="sm" variante="peligro" cargando={resolver.cargando} onClick={() => resolver.ejecutar(false, null).then(fin('Rechazada: el libro vuelve a la persona.'))}>Rechazar</Boton>
      </div>
      <p className="text-xs text-tinta/60">Para descartar, anotá el motivo en la nota.</p>
    </div>
  );
}

function NuevaDevolucion({ onCerrar, onListo }) {
  const [codigo, setCodigo] = useState('');
  const [item, setItem] = useState(null);
  const [buscado, setBuscado] = useState(false);
  const [motivo, setMotivo] = useState('Defecto no informado');
  const [detalle, setDetalle] = useState('');
  const [forma, setForma] = useState('efectivo');
  const [defecto, setDefecto] = useState(true);
  const enviar = useAccion((clave) => rpc('solicitar_devolucion', { p_venta_item: item.id, p_motivo: motivo, p_detalle: detalle, p_defecto_no_informado: defecto, p_forma: forma, p_idem: clave }));
  async function buscar() {
    const { data } = await supabase.from('venta_items').select('id, precio_final, anulado, ventas(numero, canal, created_at, comprador_id), ejemplares!inner(codigo, titulos(titulo))')
      .eq('ejemplares.codigo', codigo.trim().toUpperCase()).eq('anulado', false).order('id', { ascending: false }).limit(1);
    setItem(data?.[0] || null); setBuscado(true);
  }
  return (
    <Modal abierto titulo="Registrar una devolución" onCerrar={onCerrar}>
      <div className="space-y-4">
        <div className="flex gap-2"><Entrada value={codigo} onChange={(e) => setCodigo(e.target.value)} placeholder="Código del ejemplar (PJ-01023)" /><Boton onClick={buscar}>Buscar</Boton></div>
        {buscado && !item ? <p className="text-lacre">No encontramos una venta vigente con ese código.</p> : null}
        {item ? (
          <>
            <p className="rounded bg-papel-300 p-3">«{item.ejemplares.titulos.titulo}» · venta #{item.ventas.numero} ({item.ventas.canal}) del {fecha(item.ventas.created_at)} · {plata(item.precio_final)}</p>
            {item.ventas.canal === 'feria' ? <p className="text-sm text-carbon">En feria solo se acepta por un defecto que no se informó.</p> : null}
            <Campo etiqueta="Motivo"><Selector value={motivo} onChange={(e) => setMotivo(e.target.value)}>{MOTIVOS_DEVOLUCION.map((m) => <option key={m}>{m}</option>)}</Selector></Campo>
            <label className="flex items-center gap-2"><input type="checkbox" className="h-5 w-5 accent-tinta" checked={defecto} onChange={(e) => setDefecto(e.target.checked)} /> Tiene un defecto que no se informó</label>
            <Campo etiqueta="Detalle"><AreaTexto rows={2} value={detalle} onChange={(e) => setDetalle(e.target.value)} /></Campo>
            <Campo etiqueta="Reintegro (lo elige la persona)">
              <Selector value={forma} onChange={(e) => setForma(e.target.value)}>
                <option value="efectivo">Efectivo</option>
                <option value="credito" disabled={!item.ventas.comprador_id}>Crédito para la próxima compra{!item.ventas.comprador_id ? ' (requiere cuenta)' : ''}</option>
              </Selector>
            </Campo>
            <Aviso error={enviar.error} />
            <Boton className="w-full" tam="lg" cargando={enviar.cargando} onClick={async () => { if (await enviar.ejecutar()) onListo(); }}>Registrar solicitud</Boton>
          </>
        ) : null}
      </div>
    </Modal>
  );
}

export default function Devoluciones() {
  const [tab, setTab] = useState('abiertas');
  const [nueva, setNueva] = useState(false);
  const [aviso, setAviso] = useState(null);
  const { datos, error, cargando, recargar } = useDatos(() => consulta(supabase.from('devoluciones')
    .select('*, perfiles!devoluciones_comprador_id_fkey(nombre), ejemplares(codigo, estado, titulos(titulo)), ventas(numero, created_at), venta_items(precio_final)')
    .order('created_at', { ascending: false })));
  const abiertas = (datos || []).filter((d) => ['Solicitada', 'En revisión'].includes(d.estado));
  const lista = tab === 'abiertas' ? abiertas : (datos || []).filter((d) => !['Solicitada', 'En revisión'].includes(d.estado));
  const cambio = (m) => { if (m) setAviso(m); recargar(); };
  return (
    <div>
      <Titulo sub="7 días corridos desde la entrega en web y mostrador; en feria, solo por defectos no informados."
        accion={<Boton onClick={() => setNueva(true)}>+ Registrar devolución</Boton>}>Devoluciones</Titulo>
      <Pestanas valor={tab} onCambio={setTab} opciones={[{ valor: 'abiertas', etiqueta: 'Por resolver', n: abiertas.length }, { valor: 'cerradas', etiqueta: 'Resueltas' }]} />
      <div className="mb-3 space-y-2"><Aviso error={error} /><Aviso exito={aviso} onCerrar={() => setAviso(null)} /></div>
      {cargando && !datos ? <Cargando /> : !lista.length ? <Vacio titulo="No hay devoluciones acá" /> : (
        <div className="grid gap-3 lg:grid-cols-2">
          {lista.map((d) => (
            <Tarjeta key={d.id} className="p-4">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <p className="font-titulo text-lg font-bold text-tinta">#{d.id} · «{d.ejemplares.titulos.titulo}»</p>
                  <p className="text-sm text-tinta/70">{d.ejemplares.codigo} · venta {d.canal} #{d.ventas.numero} del {fecha(d.ventas.created_at)} · {d.perfiles?.nombre || 'sin cuenta'}</p>
                </div>
                <Estado valor={d.estado} />
              </div>
              <p className="mt-2"><b>{d.motivo}</b>{d.detalle ? ` — ${d.detalle}` : ''}</p>
              <p className="text-sm text-tinta/70">Pidió reintegro en {d.forma_reintegro === 'credito' ? 'crédito' : 'efectivo'} · {plata(d.venta_items.precio_final)} · solicitada {fechaHora(d.created_at)}</p>
              {d.estado === 'Aprobada' ? <p className="mt-1 text-sm text-pino">Reintegrado {plata(d.importe_total)}{Number(d.importe_envio) ? ` (incluye envío ${plata(d.importe_envio)})` : ''} · ejemplar {d.resultado_ejemplar === 'En venta' ? 'de vuelta a la venta' : 'descartado'}</p> : null}
              {d.nota_revision ? <p className="mt-1 text-sm italic text-tinta/70">{d.nota_revision}</p> : null}
              <Resolver d={d} onCambio={cambio} />
            </Tarjeta>
          ))}
        </div>
      )}
      {nueva ? <NuevaDevolucion onCerrar={() => setNueva(false)} onListo={() => { setNueva(false); cambio('Solicitud registrada. Revisala acá abajo.'); }} /> : null}
    </div>
  );
}
