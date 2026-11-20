import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { fecha, fechaHora, plata } from '../../lib/formato.js';
import { DESCUENTO_SOCIO } from '../../lib/reglas.js';
import { Aviso, Boton, Cargando, Entrada, Titulo, cx, useAccion, useDatos } from '../../components/ui.jsx';
import VentaEnCurso from '../caja/VentaEnCurso.jsx';

export default function Mostrador({ campo = false }) {
  const base = campo ? '/caja/mostrador' : '/panel/mostrador';
  const [q, setQ] = useState('');
  const [resultados, setResultados] = useState([]);
  const [venta, setVenta] = useState([]);
  const [numSocio, setNumSocio] = useState('');
  const [socio, setSocio] = useState(null);
  const [hecha, setHecha] = useState(null);
  const buscador = useRef(null);

  const jornada = useDatos(async () => {
    const j = await rpc('abrir_jornada');
    const ventas = await consulta(supabase.from('ventas').select('id, numero, total, medio_pago, created_at, es_socio, venta_items(id)').eq('jornada_id', j.id).order('created_at', { ascending: false }));
    return { j, ventas };
  });

  async function buscar(texto) {
    try { setResultados(await rpc('mostrador_buscar', { p_q: texto })); } catch { setResultados([]); }
  }
  useEffect(() => { const t = setTimeout(() => buscar(q), 250); return () => clearTimeout(t); }, [q]);

  useEffect(() => {
    if (!numSocio.trim()) { setSocio(null); return undefined; }
    const t = setTimeout(() => rpc('consultar_socio', { p_numero: numSocio.trim() }).then(setSocio).catch(() => setSocio(null)), 350);
    return () => clearTimeout(t);
  }, [numSocio]);

  const cobrar = useAccion((clave, medio) => rpc('vender_mostrador', {
    p_jornada: jornada.datos.j.id, p_ejemplares: venta.map((v) => v.id), p_medio: medio,
    p_numero_socio: socio?.encontrado ? numSocio.trim() : null, p_idem: clave,
  }));

  const subtotal = venta.reduce((s, x) => s + x.precio, 0);
  const descSocio = socio?.al_dia ? venta.reduce((s, x) => s + Math.round(x.precio * DESCUENTO_SOCIO), 0) : 0;

  function sumar(l) {
    setHecha(null); cobrar.limpiar();
    setVenta((xs) => (xs.some((x) => x.id === l.id) ? xs : [...xs, { id: l.id, codigo: l.codigo, titulo: l.titulo, precio: Number(l.precio) }]));
    setQ(''); buscador.current?.focus();
  }
  async function onCobrar(medio) {
    const r = await cobrar.ejecutar(medio);
    if (r) { window.scrollTo({ top: 0, behavior: 'smooth' }); setHecha(r); setVenta([]); setNumSocio(''); jornada.recargar(); buscar(''); }
  }
  function actualizarTrasConflicto() {
    const ids = (cobrar.error?.detalle?.ejemplares || []).map((e) => e.id);
    setVenta((xs) => xs.filter((x) => !ids.includes(x.id)));
    cobrar.limpiar(); buscar(q);
  }

  if (jornada.cargando && !jornada.datos) return <Cargando />;
  if (jornada.error) return <Aviso error={jornada.error} grande={campo} />;
  const { j, ventas } = jornada.datos;
  const totalDia = ventas.reduce((s, v) => s + Number(v.total), 0);

  return (
    <div className={cx('space-y-4', campo && 'text-carbon')}>
      {campo ? <h1 className="font-titulo text-3xl font-bold">Mostrador · {fecha(j.fecha)}</h1>
        : <Titulo sub="Venta en la biblioteca, con ticket imprimible. El descuento de socio se aplica con el número de socio.">Mostrador · {fecha(j.fecha, { weekday: 'long' })}</Titulo>}

      {j.estado === 'Cerrada' ? (
        <div className="rounded-xl bg-carbon p-5 text-xl text-papel">La jornada de hoy ya se cerró. Mañana se abre una nueva.</div>
      ) : (
        <div className="grid gap-5 lg:grid-cols-[1fr_440px]">
          <div className="space-y-3">
            {hecha ? (
              <div role="status" className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-pino p-4 text-papel">
                <div>
                  <p className="font-titulo text-2xl font-bold">Venta #{hecha.numero} · {plata(hecha.total)}</p>
                  {hecha.es_socio ? <p>Con descuento de socio: −{plata(hecha.descuento_socio)}</p> : null}
                </div>
                <a href={`/ticket/${hecha.venta_id}`} target="_blank" rel="noreferrer"><Boton variante="secundario" className="bg-papel">Imprimir ticket</Boton></a>
              </div>
            ) : null}
            <Aviso error={cobrar.error} grande={campo} onActualizar={actualizarTrasConflicto} onCerrar={cobrar.error?.tipo !== 'conflicto' ? cobrar.limpiar : undefined} />
            <Entrada ref={buscador} value={q} onChange={(e) => setQ(e.target.value)} placeholder="Código o título de un libro en venta"
              className="h-14 text-xl" aria-label="Buscar libro" onKeyDown={(e) => { if (e.key === 'Enter' && resultados.length === 1) sumar(resultados[0]); }} />
            <ul className="space-y-2">
              {resultados.filter((r) => !venta.some((v) => v.id === r.id)).slice(0, 10).map((r) => (
                <li key={r.id}>
                  <button onClick={() => sumar(r)} className="flex min-h-16 w-full items-center gap-3 rounded-lg bg-white px-4 py-2 text-left ring-1 ring-tinta/20 hover:ring-tinta">
                    <span className="h-9 w-1.5 rounded" style={{ background: r.categoria_color }} aria-hidden />
                    <span className="min-w-0 flex-1"><span className="block truncate text-lg font-bold">{r.titulo}</span>
                      <span className="block text-sm text-tinta/70">{r.autor} · {r.codigo} · {r.ubicacion}</span></span>
                    <span className="text-lg font-bold tabular-nums">{plata(r.precio)}</span>
                  </button>
                </li>
              ))}
            </ul>
          </div>
          <div className="space-y-3">
            <div className="rounded-xl bg-white p-4 ring-2 ring-tinta/20">
              <label className="block text-lg font-bold" htmlFor="socio">N.º de socio (opcional)</label>
              <Entrada id="socio" value={numSocio} onChange={(e) => setNumSocio(e.target.value)} inputMode="numeric" placeholder="Ej.: 1047" className="mt-1 text-lg" />
              {socio ? (
                <p className={cx('mt-2 font-semibold', socio.encontrado && socio.al_dia ? 'text-pino' : 'text-lacre')}>
                  {!socio.encontrado ? 'No encontramos ese número.' : socio.al_dia ? `${socio.nombre}: cuota al día, 15 % de descuento.` : `${socio.nombre}: la cuota no está al día, va sin descuento.`}
                </p>
              ) : null}
            </div>
            <VentaEnCurso items={venta} subtotal={subtotal} descuentoSocio={descSocio} total={subtotal - descSocio}
              onQuitar={(id) => setVenta((xs) => xs.filter((x) => x.id !== id))} onCobrar={onCobrar} cargando={cobrar.cargando} />
            <div className="rounded-xl bg-papel-100 p-4 ring-1 ring-tinta/15">
              <div className="flex items-center justify-between"><p className="font-titulo text-lg font-bold">Hoy: {ventas.length} ventas · {plata(totalDia)}</p>
                <Link to={`${base}/cierre/${j.id}`}><Boton tam="sm" variante="peligro">Cerrar jornada</Boton></Link></div>
              <ul className="mt-2 max-h-56 overflow-y-auto text-sm">
                {ventas.map((v) => (
                  <li key={v.id} className="flex justify-between border-b border-dashed border-tinta/15 py-1.5">
                    <span>#{v.numero} · {fechaHora(v.created_at).split(',').pop()} · {v.venta_items.length} lib. · {v.medio_pago}{v.es_socio ? ' · socio' : ''}</span>
                    <span className="flex gap-3"><span className="tabular-nums">{plata(v.total)}</span><a className="underline" href={`/ticket/${v.id}`} target="_blank" rel="noreferrer">ticket</a></span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
