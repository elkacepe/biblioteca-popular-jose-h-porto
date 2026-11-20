import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { rpc, consulta } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { fecha, hora, plata } from '../../lib/formato.js';
import { useBolsa } from '../../context/Bolsa.jsx';
import { Aviso, Boton, Cargando, Entrada, Lomo, Vacio, cx } from '../../components/ui.jsx';

const POR_PAGINA = 24;

export function TarjetaLibro({ libro }) {
  const bolsa = useBolsa();
  const enBolsa = bolsa.tiene(libro.id);
  return (
    <article className="group relative flex overflow-hidden rounded-md bg-papel-100 shadow-papel ring-1 ring-tinta/10">
      <div className="w-2.5 shrink-0" style={{ background: libro.categoria_color }} aria-hidden />
      <div className="flex min-w-0 flex-1 flex-col p-4">
        <div className="mb-2 flex items-start justify-between gap-2">
          <Lomo nombre={libro.categoria} color={libro.categoria_color} />
          <span className="text-xs text-tinta/60">{libro.estado_fisico}</span>
        </div>
        <Link to={`/libro/${libro.id}`} className="font-titulo text-lg font-bold leading-snug text-tinta hover:text-lacre">
          {libro.titulo}
        </Link>
        <p className="text-sm text-tinta/80">{libro.autor}</p>
        <p className="mt-0.5 text-xs text-tinta/55">{[libro.editorial, libro.anio].filter(Boolean).join(' · ')} · {libro.codigo}</p>
        <div className="mt-auto flex items-end justify-between gap-2 pt-4">
          <div>
            <p className="font-titulo text-2xl font-bold tabular-nums text-tinta">{plata(libro.precio)}</p>
            <p className="text-xs text-pino">Socios: {plata(libro.precio_socio)}</p>
          </div>
          <Boton tam="sm" variante={enBolsa ? 'secundario' : 'primario'} onClick={() => (enBolsa ? bolsa.quitar(libro.id) : bolsa.agregar(libro))}
            aria-pressed={enBolsa}>
            {enBolsa ? '✓ En la bolsa' : 'A la bolsa'}
          </Boton>
        </div>
      </div>
    </article>
  );
}

export function ProximaFeria() {
  const [feria, setFeria] = useState(null);
  useEffect(() => {
    rpc('ferias_publicas').then((fs) => setFeria(fs.find((f) => f.estado !== 'Cerrada') || null)).catch(() => {});
  }, []);
  if (!feria) return null;
  return (
    <Link to="/ferias" className="flex items-center gap-4 rounded-md bg-lacre p-4 text-papel shadow-papel hover:brightness-110">
      <div className="rounded bg-papel px-3 py-1 text-center text-lacre">
        <p className="text-xs font-bold uppercase">{fecha(feria.fecha, { month: 'short', day: undefined })}</p>
        <p className="font-titulo text-3xl font-bold leading-none">{new Date(feria.fecha + 'T12:00:00').getDate()}</p>
      </div>
      <div>
        <p className="font-titulo text-xl font-bold">{feria.estado === 'Abierta' ? '¡La feria está abierta!' : 'Próxima feria solidaria'}</p>
        <p className="text-papel/90">Domingo de {hora(feria.hora_inicio)} a {hora(feria.hora_fin)} · {feria.lugar}. Llevando 3, el más barato va de regalo.</p>
      </div>
    </Link>
  );
}

export default function Catalogo() {
  const [categorias, setCategorias] = useState([]);
  const [cat, setCat] = useState(null);
  const [q, setQ] = useState('');
  const [busqueda, setBusqueda] = useState('');
  const [libros, setLibros] = useState([]);
  const [total, setTotal] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => { consulta(supabase.from('categorias').select('*').order('orden')).then(setCategorias).catch(() => {}); }, []);
  useEffect(() => { const t = setTimeout(() => setBusqueda(q.trim()), 300); return () => clearTimeout(t); }, [q]);

  async function cargar(desde = 0) {
    setCargando(true); setError(null);
    try {
      const filas = await rpc('catalogo_publico', { p_busqueda: busqueda || null, p_categoria: cat, p_limite: POR_PAGINA, p_desde: desde });
      setLibros((xs) => (desde === 0 ? filas : [...xs, ...filas]));
      setTotal(filas[0]?.total ?? (desde === 0 ? 0 : total));
    } catch (e) { setError(e); } finally { setCargando(false); }
  }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { cargar(0); }, [busqueda, cat]);

  return (
    <div className="space-y-6">
      <section className="grid gap-5 md:grid-cols-[1.3fr_1fr] md:items-center">
        <div>
          <p className="sello text-lacre">Feria permanente</p>
          <h1 className="mt-3 font-titulo text-4xl font-bold leading-[1.05] text-tinta sm:text-5xl">Libros que vuelven a circular</h1>
          <p className="mt-3 max-w-xl text-lg text-tinta/85">
            Son los repetidos de las donaciones que recibe la biblioteca. Cada ejemplar es único: si te gusta, reservalo,
            que cuando se va, se va. Lo que juntamos paga parte de lo que cuesta abrir la puerta todos los días.
          </p>
        </div>
        <ProximaFeria />
      </section>

      <section className="sticky top-[104px] z-20 -mx-4 space-y-3 bg-papel/95 px-4 py-3 backdrop-blur">
        <Entrada type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscá por título, autor o código (PJ-01023)"
          aria-label="Buscar libros" className="text-lg" />
        <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1" role="group" aria-label="Filtrar por categoría">
          <button onClick={() => setCat(null)} className={cx('shrink-0 rounded-[3px] px-3 py-1.5 text-xs font-bold uppercase tracking-wider',
            cat === null ? 'bg-carbon text-papel' : 'bg-papel-100 text-tinta ring-1 ring-tinta/25')}>Todas</button>
          {categorias.map((c) => (
            <button key={c.id} onClick={() => setCat(cat === c.id ? null : c.id)} aria-pressed={cat === c.id}
              className={cx('shrink-0 transition', cat !== null && cat !== c.id && 'opacity-45')}>
              <Lomo nombre={c.nombre} color={c.color} className={cat === c.id ? 'ring-2 ring-mostaza ring-offset-2 ring-offset-papel' : ''} />
            </button>
          ))}
        </div>
      </section>

      <Aviso error={error} />
      {!cargando || libros.length ? (
        <p className="text-sm text-tinta/70">{total ? `${total} ${total === 1 ? 'libro disponible' : 'libros disponibles'}` : ''}</p>
      ) : null}
      {libros.length ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {libros.map((l) => <TarjetaLibro key={l.id} libro={l} />)}
        </div>
      ) : !cargando ? (
        <Vacio titulo="No encontramos ese libro en los estantes" texto="Quizás ya encontró dueño o se fue a la feria. Probá con otra búsqueda o pasá por la próxima feria." />
      ) : null}
      {cargando ? <Cargando /> : libros.length < total ? (
        <div className="text-center"><Boton variante="secundario" onClick={() => cargar(libros.length)}>Ver más libros</Boton></div>
      ) : null}
    </div>
  );
}
