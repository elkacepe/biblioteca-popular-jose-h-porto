import { useEffect, useRef, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, fecha, hora, plata } from '../../lib/formato.js';
import { promoFeria } from '../../lib/reglas.js';
import { Aviso, Boton, Cargando, useAccion, useDatos } from '../../components/ui.jsx';
import VentaEnCurso from './VentaEnCurso.jsx';

export default function CajaFeria() {
  const { id } = useParams();
  const feriaId = Number(id);
  const [q, setQ] = useState('');
  const [resultados, setResultados] = useState([]);
  const [buscando, setBuscando] = useState(false);
  const [venta, setVenta] = useState([]);
  const [hecha, setHecha] = useState(null);
  const buscador = useRef(null);

  const feria = useDatos(async () => {
    const [f, resumen] = await Promise.all([
      consulta(supabase.from('ferias').select('*').eq('id', feriaId).maybeSingle()),
      rpc('resumen_caja', { p_feria: feriaId }),
    ]);
    return { f, resumen };
  }, [feriaId]);

  async function buscar(texto = q) {
    setBuscando(true);
    try { setResultados(await rpc('feria_buscar', { p_feria: feriaId, p_q: texto })); } catch { /* el error se ve al cobrar */ } finally { setBuscando(false); }
  }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { const t = setTimeout(() => buscar(q), 250); return () => clearTimeout(t); }, [q, feriaId]);

  const abrir = useAccion(() => rpc('abrir_feria', { p_feria: feriaId }));
  const cobrar = useAccion((clave, medio) => rpc('vender_feria', { p_feria: feriaId, p_ejemplares: venta.map((v) => v.id), p_medio: medio, p_idem: clave }));

  const calc = promoFeria(venta);

  function sumar(libro) {
    setHecha(null); cobrar.limpiar();
    setVenta((xs) => (xs.some((x) => x.id === libro.id) ? xs : [...xs, { id: libro.id, codigo: libro.codigo, titulo: libro.titulo, precio: Number(libro.precio), caja: libro.caja }]));
    setQ(''); buscador.current?.focus();
  }

  async function onCobrar(medio) {
    const r = await cobrar.ejecutar(medio);
    if (r) {
      setHecha({ ...r, medio, libros: venta.length });
      window.scrollTo({ top: 0, behavior: 'smooth' });
      setVenta([]);
      feria.recargar();
      buscar('');
    }
  }

  // Conflicto: otro voluntario (o la web) se quedó con un libro. Se saca de la venta y se refresca.
  function actualizarTrasConflicto() {
    const vendidos = (cobrar.error?.detalle?.ejemplares || []).map((e) => e.id);
    setVenta((xs) => xs.filter((x) => !vendidos.includes(x.id)));
    cobrar.limpiar();
    buscar(q);
  }

  if (feria.cargando && !feria.datos) return <Cargando />;
  if (feria.error) return <Aviso error={feria.error} grande />;
  if (!feria.datos?.f) return <Aviso error={{ tipo: 'permiso', message: 'Esta feria no está asignada a tu cuenta.' }} grande />;
  const { f, resumen } = feria.datos;

  return (
    <div className="space-y-4 pb-10 text-carbon">
      <header className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-bold uppercase tracking-widest text-lacre">Feria · {f.estado}</p>
          <h1 className="font-titulo text-2xl font-bold first-letter:uppercase">{diaSemana(f.fecha)} {fecha(f.fecha)} · {hora(f.hora_inicio)} a {hora(f.hora_fin)}</h1>
        </div>
        <div className="text-right">
          <p className="font-titulo text-2xl font-bold tabular-nums">{plata(Number(resumen.efectivo) + Number(resumen.transferencias))}</p>
          <p className="text-sm">{resumen.ventas} ventas · {resumen.sin_vender} en cajas</p>
        </div>
      </header>

      {f.estado === 'Planificada' ? (
        <div className="space-y-3 rounded-xl bg-mostaza-50 p-4 ring-4 ring-mostaza">
          <p className="text-xl font-semibold">La feria todavía no está abierta.</p>
          <Aviso error={abrir.error} grande />
          <Boton tam="xl" variante="exito" className="w-full" cargando={abrir.cargando} onClick={async () => { if ((await abrir.ejecutar()) !== undefined) feria.recargar(); }}>Abrir la feria</Boton>
        </div>
      ) : f.estado === 'Cerrada' ? (
        <div className="rounded-xl bg-carbon p-5 text-xl text-papel">Esta feria ya se cerró. La rendición quedó guardada.</div>
      ) : (
        <>
          {hecha ? (
            <div role="status" className="rounded-xl bg-pino p-5 text-papel">
              <p className="font-titulo text-3xl font-bold">¡Vendido!</p>
              <p className="text-xl">Venta #{hecha.numero} · {hecha.libros} {hecha.libros === 1 ? 'libro' : 'libros'} · <b>{plata(hecha.total)}</b> en {hecha.medio}{hecha.repetida ? ' (ya estaba registrada)' : ''}</p>
              {Number(hecha.descuento_promo) ? <p className="text-lg">Promo 3 libros: −{plata(hecha.descuento_promo)}</p> : null}
            </div>
          ) : null}

          <Aviso error={cobrar.error} grande onActualizar={actualizarTrasConflicto} onCerrar={cobrar.error?.tipo !== 'conflicto' ? cobrar.limpiar : undefined} />

          <div>
            <label htmlFor="buscar" className="mb-1 block text-lg font-bold">Código o título</label>
            <input id="buscar" ref={buscador} value={q} onChange={(e) => setQ(e.target.value)} autoComplete="off" inputMode="search"
              placeholder="PJ-01023 o «Martín Fierro»"
              onKeyDown={(e) => { if (e.key === 'Enter' && resultados.length === 1) sumar(resultados[0]); }}
              className="h-16 w-full rounded-xl border-4 border-carbon bg-white px-4 text-2xl font-semibold placeholder:text-carbon/35 focus:outline-none focus:ring-4 focus:ring-mostaza" />
          </div>

          <ul className="space-y-2" aria-live="polite">
            {resultados.filter((r) => !venta.some((v) => v.id === r.id)).slice(0, 8).map((r) => (
              <li key={r.id}>
                <button onClick={() => sumar(r)} className="flex min-h-[4.5rem] w-full items-center gap-3 rounded-xl bg-white px-4 py-3 text-left ring-2 ring-carbon/30 active:bg-mostaza-50 active:ring-carbon">
                  <span className="h-10 w-2 shrink-0 rounded" style={{ background: r.categoria_color }} aria-hidden />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-xl font-bold">{r.titulo}</span>
                    <span className="block text-base text-carbon/70">{r.autor} · {r.codigo} · caja {r.caja}</span>
                  </span>
                  <span className="text-2xl font-bold tabular-nums">{plata(r.precio)}</span>
                </button>
              </li>
            ))}
            {!buscando && q && !resultados.length ? <li className="rounded-xl bg-white p-4 text-lg">No está en las cajas de esta feria. Puede que ya se haya vendido.</li> : null}
          </ul>

          <VentaEnCurso items={venta} sinCargo={calc.sinCargo} subtotal={calc.subtotal} total={calc.total}
            nota="En la feria no corre el descuento de socio. Cada 3 libros, el más barato va de regalo."
            onQuitar={(idQ) => setVenta((xs) => xs.filter((x) => x.id !== idQ))} onCobrar={onCobrar} cargando={cobrar.cargando} />

          <Link to={`/caja/feria/${feriaId}/cierre`} className="block rounded-xl bg-papel-300 p-4 text-center text-xl font-bold text-carbon ring-2 ring-carbon">
            Terminar la feria: arqueo y rendición
          </Link>
        </>
      )}
    </div>
  );
}
