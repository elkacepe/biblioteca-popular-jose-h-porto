import { useEffect, useState } from 'react';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { fecha, fechaHora, plata } from '../../lib/formato.js';
import { Aviso, Boton, Campo, Cargando, Dato, Entrada, Estado, Lomo, Modal, Selector, Titulo, Vacio, useAccion, useDatos } from '../../components/ui.jsx';

const ESTADOS = ['En clasificación', 'Acervo', 'En venta', 'Reservado', 'En feria', 'Vendido', 'En devolución', 'Descartado'];
const SELECT = `id, codigo, estado, estado_fisico, precio, precio_sugerido, editorial, anio, motivo_descarte, destino_reciclado, en_deposito_desde, created_at, reservado_hasta,
  titulos!inner(titulo, autor, editorial, anio, categorias(nombre, color)),
  ubicacion:ubicaciones!ejemplares_ubicacion_id_fkey(id, codigo), deposito:ubicaciones!ejemplares_ubicacion_deposito_id_fkey(id, codigo),
  lotes(codigo, procedencia, anonima), pedidos!ejemplares_pedido_fk(numero), cajas_feria!ejemplares_caja_fk(numero, ferias(fecha))`;

export function FichaEjemplar({ id, onCerrar, onCambio, soloLectura = false }) {
  const [precio, setPrecio] = useState('');
  const [hacia, setHacia] = useState('');
  const [motivo, setMotivo] = useState('');
  const [motivoDesc, setMotivoDesc] = useState('');
  const [reciclado, setReciclado] = useState(true);
  const [exito, setExito] = useState(null);
  const ficha = useDatos(async () => {
    const [e, hist, tras, ubics] = await Promise.all([
      consulta(supabase.from('ejemplares').select(SELECT).eq('id', id).single()),
      consulta(supabase.from('historial_ejemplar').select('*, perfiles(nombre)').eq('ejemplar_id', id).order('fecha')),
      consulta(supabase.from('traslados').select('*, perfiles(nombre), desde:ubicaciones!traslados_desde_id_fkey(codigo), hacia:ubicaciones!traslados_hacia_id_fkey(codigo)').eq('ejemplar_id', id).order('fecha')),
      consulta(supabase.from('ubicaciones').select('*').eq('tipo', 'estante').order('codigo')),
    ]);
    return { e, hist, tras, ubics };
  }, [id]);
  useEffect(() => { if (ficha.datos) setPrecio(ficha.datos.e.precio ?? ficha.datos.e.precio_sugerido ?? ''); }, [ficha.datos]);

  const hecho = (msg) => async (r) => { if (r !== undefined) { setExito(msg); await ficha.recargar(); onCambio?.(); } };
  const aPrecio = useAccion(() => rpc(ficha.datos.e.estado === 'En clasificación' ? 'publicar_ejemplar' : 'cambiar_precio', { p_ejemplar: id, p_precio: Number(precio) }));
  const aTraslado = useAccion(() => rpc('trasladar_ejemplar', { p_ejemplar: id, p_ubicacion: Number(hacia), p_motivo: motivo }));
  const aDescarte = useAccion(() => rpc('descartar_ejemplar', { p_ejemplar: id, p_motivo: motivoDesc, p_reciclado: reciclado }));
  const error = aPrecio.error || aTraslado.error || aDescarte.error || ficha.error;

  return (
    <Modal abierto titulo="Ficha del ejemplar" onCerrar={onCerrar} ancho="max-w-3xl">
      {!ficha.datos ? <Cargando /> : (() => {
        const { e, hist, tras, ubics } = ficha.datos;
        const enEstante = ['En clasificación', 'En venta', 'Reservado'].includes(e.estado);
        return (
          <div className="space-y-5">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <Lomo nombre={e.titulos.categorias.nombre} color={e.titulos.categorias.color} />
                <p className="mt-2 font-titulo text-2xl font-bold text-tinta">{e.titulos.titulo}</p>
                <p className="text-tinta/80">{e.titulos.autor}</p>
              </div>
              <div className="text-right"><Estado valor={e.estado} className="text-sm" /><p className="mt-1 font-mono text-sm">{e.codigo}</p></div>
            </div>
            <dl className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              <Dato etiqueta="Editorial">{e.editorial || e.titulos.editorial || '—'}</Dato>
              <Dato etiqueta="Año">{e.anio || e.titulos.anio || '—'}</Dato>
              <Dato etiqueta="Estado físico">{e.estado_fisico}</Dato>
              <Dato etiqueta="Precio">{e.precio ? plata(e.precio) : '—'}{e.precio_sugerido && e.precio !== e.precio_sugerido ? <span className="block text-xs text-tinta/60">sugerido {plata(e.precio_sugerido)}</span> : null}</Dato>
              <Dato etiqueta="Ubicación">{e.ubicacion?.codigo || 'Fuera de la biblioteca'}</Dato>
              <Dato etiqueta="Su lugar en depósito">{e.deposito?.codigo || '—'}</Dato>
              <Dato etiqueta="Lote de origen">{e.lotes.codigo} · {e.lotes.anonima ? 'Anónima' : e.lotes.procedencia}</Dato>
              <Dato etiqueta="En depósito desde">{fecha(e.en_deposito_desde, { year: 'numeric' })}</Dato>
            </dl>
            {e.pedidos ? <p className="text-sm">Pedido web #{e.pedidos.numero}{e.reservado_hasta ? ` · reservado hasta ${fechaHora(e.reservado_hasta)}` : ''}</p> : null}
            {e.cajas_feria ? <p className="text-sm">Caja {e.cajas_feria.numero} de la feria del {fecha(e.cajas_feria.ferias.fecha)}</p> : null}
            {e.motivo_descarte ? <p className="text-sm">Descarte: {e.motivo_descarte}{e.destino_reciclado ? ' · a reciclado' : ''}</p> : null}

            <Aviso error={error} exito={exito} onActualizar={ficha.recargar} onCerrar={() => { setExito(null); aPrecio.limpiar(); aTraslado.limpiar(); aDescarte.limpiar(); }} />

            {!soloLectura ? (
              <div className="grid gap-4 md:grid-cols-3">
                {['En clasificación', 'En venta'].includes(e.estado) ? (
                  <div className="rounded-md bg-papel-300/60 p-3">
                    <p className="mb-2 font-semibold">{e.estado === 'En clasificación' ? 'Publicar a la venta' : 'Cambiar precio'}</p>
                    <div className="flex gap-2"><Entrada type="number" step="100" min="100" value={precio} onChange={(x) => setPrecio(x.target.value)} />
                      <Boton cargando={aPrecio.cargando} onClick={() => aPrecio.ejecutar().then(hecho(e.estado === 'En clasificación' ? 'Publicado: ya figura en la web.' : 'Precio actualizado.'))}>OK</Boton></div>
                  </div>
                ) : e.estado === 'Acervo' ? <p className="rounded-md bg-tinta p-3 text-sm text-papel md:col-span-1">Ejemplar del acervo: se queda en la sala de lectura y no se vende.</p> : null}
                {enEstante ? (
                  <div className="rounded-md bg-papel-300/60 p-3">
                    <p className="mb-2 font-semibold">Trasladar</p>
                    <Selector value={hacia} onChange={(x) => setHacia(x.target.value)} className="mb-2">
                      <option value="">¿A qué estante?</option>{ubics.map((u) => <option key={u.id} value={u.id}>{u.codigo}</option>)}
                    </Selector>
                    <Entrada value={motivo} onChange={(x) => setMotivo(x.target.value)} placeholder="Motivo" className="mb-2" />
                    <Boton tam="sm" cargando={aTraslado.cargando} disabled={!hacia || !motivo} onClick={() => aTraslado.ejecutar().then(hecho('Traslado registrado.'))}>Registrar traslado</Boton>
                  </div>
                ) : null}
                {['En clasificación', 'En venta', 'Acervo', 'En devolución'].includes(e.estado) ? (
                  <div className="rounded-md bg-lacre-50 p-3">
                    <p className="mb-2 font-semibold text-lacre-700">Descartar</p>
                    <Entrada value={motivoDesc} onChange={(x) => setMotivoDesc(x.target.value)} placeholder="Motivo" className="mb-2" />
                    <label className="mb-2 flex items-center gap-2 text-sm"><input type="checkbox" checked={reciclado} onChange={(x) => setReciclado(x.target.checked)} className="accent-lacre" /> A reciclado</label>
                    <Boton tam="sm" variante="peligro" cargando={aDescarte.cargando} disabled={!motivoDesc} onClick={() => aDescarte.ejecutar().then(hecho('Ejemplar descartado.'))}>Descartar</Boton>
                  </div>
                ) : null}
              </div>
            ) : null}

            <div className="grid gap-5 md:grid-cols-2">
              <div>
                <p className="mb-2 font-titulo font-bold text-tinta">Estados</p>
                <ol className="space-y-1.5 border-l-2 border-tinta/20 pl-3 text-sm">
                  {hist.map((h) => <li key={h.id}><Estado valor={h.estado_nuevo} /> <span className="text-tinta/60">{fechaHora(h.fecha)}{h.perfiles ? ` · ${h.perfiles.nombre}` : ''}</span>{h.motivo ? <span className="block text-tinta/80">{h.motivo}</span> : null}</li>)}
                </ol>
              </div>
              <div>
                <p className="mb-2 font-titulo font-bold text-tinta">Traslados</p>
                <ol className="space-y-1.5 border-l-2 border-tinta/20 pl-3 text-sm">
                  {tras.map((t) => (
                    <li key={t.id}><b>{t.desde?.codigo || '—'} → {t.hacia?.codigo || 'fuera de la biblioteca'}</b>
                      <span className="block text-tinta/60">{fechaHora(t.fecha)} · {t.perfiles?.nombre || 'sistema'}{t.automatico ? ' · automático' : ''}</span>
                      <span className="block text-tinta/80">{t.motivo}</span></li>
                  ))}
                </ol>
              </div>
            </div>
          </div>
        );
      })()}
    </Modal>
  );
}

export default function Deposito() {
  const [q, setQ] = useState('');
  const [estado, setEstado] = useState('');
  const [ubic, setUbic] = useState('');
  const [abierta, setAbierta] = useState(null);
  const [busqueda, setBusqueda] = useState('');
  useEffect(() => { const t = setTimeout(() => setBusqueda(q.trim()), 300); return () => clearTimeout(t); }, [q]);
  const ubics = useDatos(() => consulta(supabase.from('ubicaciones').select('*').order('tipo').order('codigo')));
  const lista = useDatos(async () => {
    let c = supabase.from('ejemplares').select(SELECT, { count: 'exact' }).order('codigo').limit(60);
    if (busqueda) c = /^pj-?\d*/i.test(busqueda) ? c.ilike('codigo', `%${busqueda}%`) : c.ilike('titulos.titulo', `%${busqueda}%`);
    if (estado) c = c.eq('estado', estado);
    if (ubic) c = c.eq('ubicacion_id', Number(ubic));
    return consulta(c);
  }, [busqueda, estado, ubic]);

  const filas = lista.datos?.data || [];
  return (
    <div>
      <Titulo sub="Cada ejemplar tiene una sola ubicación y un solo estado. Todo cambio queda registrado.">Depósito</Titulo>
      <div className="mb-4 grid gap-3 md:grid-cols-[2fr_1fr_1fr]">
        <Entrada type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Código (PJ-01023) o título" aria-label="Buscar" />
        <Selector value={estado} onChange={(e) => setEstado(e.target.value)} aria-label="Estado"><option value="">Todos los estados</option>{ESTADOS.map((s) => <option key={s}>{s}</option>)}</Selector>
        <Selector value={ubic} onChange={(e) => setUbic(e.target.value)} aria-label="Ubicación"><option value="">Todas las ubicaciones</option>{ubics.datos?.map((u) => <option key={u.id} value={u.id}>{u.codigo}</option>)}</Selector>
      </div>
      <Aviso error={lista.error} />
      {lista.cargando && !lista.datos ? <Cargando /> : !filas.length ? <Vacio titulo="No hay ejemplares con ese filtro" /> : (
        <>
          <p className="mb-2 text-sm text-tinta/70">{lista.datos.count} ejemplares{lista.datos.count > filas.length ? ` (se muestran ${filas.length})` : ''}</p>
          <div className="overflow-x-auto">
            <table className="tabla">
              <thead><tr><th>Código</th><th>Título</th><th>Estado</th><th>Ubicación</th><th className="text-right">Precio</th></tr></thead>
              <tbody>
                {filas.map((e) => (
                  <tr key={e.id} className="cursor-pointer hover:bg-papel-300/50" onClick={() => setAbierta(e.id)}>
                    <td className="font-mono text-xs">{e.codigo}</td>
                    <td><p className="font-semibold text-tinta">{e.titulos.titulo}</p><p className="text-xs text-tinta/60">{e.titulos.autor} · {e.estado_fisico}</p></td>
                    <td><Estado valor={e.estado} /></td>
                    <td>{e.ubicacion?.codigo || '—'}</td>
                    <td className="text-right tabular-nums">{e.precio ? plata(e.precio) : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
      {abierta ? <FichaEjemplar id={abierta} onCerrar={() => setAbierta(null)} onCambio={lista.recargar} /> : null}
    </div>
  );
}
