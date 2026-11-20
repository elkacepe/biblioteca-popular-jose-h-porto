import { useEffect, useMemo, useRef, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { fecha, plata } from '../../lib/formato.js';
import { precioSugerido } from '../../lib/reglas.js';
import { Aviso, Boton, Campo, Cargando, Entrada, Estado, Lomo, Selector, Tarjeta, Titulo, cx, useAccion, useDatos } from '../../components/ui.jsx';

const VACIO = { titulo: '', autor: '', editorial: '', anio: '', categoria: '', estado: 'Bueno', ubicacion: '', motivo: '', reciclado: true, obs: '' };

function FilaPublicar({ e, onListo }) {
  const [precio, setPrecio] = useState(e.precio ?? e.precio_sugerido ?? '');
  const acc = useAccion(() => rpc('publicar_ejemplar', { p_ejemplar: e.id, p_precio: Number(precio) }));
  return (
    <div className="flex items-center gap-2">
      <span className="text-sm text-tinta/60">$</span>
      <div className="w-28"><Entrada type="number" min="100" step="100" value={precio} onChange={(x) => setPrecio(x.target.value)} className="py-1.5" aria-label="Precio" /></div>
      <Boton tam="sm" variante="exito" cargando={acc.cargando} onClick={async () => { if (await acc.ejecutar()) onListo(); }}>Publicar</Boton>
      {acc.error ? <span className="text-sm text-lacre">{acc.error.message}</span> : null}
    </div>
  );
}

export default function Lote() {
  const { id } = useParams();
  const [f, setF] = useState(VACIO);
  const [resultado, setResultado] = useState(null);
  const [titulos, setTitulos] = useState([]);
  const tituloRef = useRef(null);
  const set = (k) => (e) => setF((x) => ({ ...x, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value }));

  const base = useDatos(async () => {
    const [cats, ubics] = await Promise.all([
      consulta(supabase.from('categorias').select('*').order('orden')),
      consulta(supabase.from('ubicaciones').select('*').eq('tipo', 'estante').order('codigo')),
    ]);
    return { cats, ubics };
  });
  const lote = useDatos(() => consulta(supabase.from('lotes').select(`*, ejemplares(id, codigo, estado, estado_fisico, precio, precio_sugerido, motivo_descarte,
      titulos(titulo, autor, categorias(nombre, color)), ubicaciones!ejemplares_ubicacion_id_fkey(codigo))`).eq('id', id).single()), [id]);

  // Sugerencias de títulos ya conocidos (para no duplicar y saber si están en el acervo).
  useEffect(() => {
    const q = f.titulo.trim();
    if (q.length < 3) { setTitulos([]); return undefined; }
    const t = setTimeout(() => {
      supabase.from('titulos').select('id, titulo, autor, editorial, anio, categoria_id, en_acervo').ilike('titulo', `%${q}%`).limit(8)
        .then(({ data }) => setTitulos(data || []));
    }, 250);
    return () => clearTimeout(t);
  }, [f.titulo]);

  const coincidencia = useMemo(() => titulos.find((t) =>
    t.titulo.trim().toLowerCase() === f.titulo.trim().toLowerCase()
    && t.autor.trim().toLowerCase() === (f.autor.trim() || 'Anónimo').toLowerCase()), [titulos, f.titulo, f.autor]);

  const cat = base.datos?.cats.find((c) => String(c.id) === String(f.categoria || coincidencia?.categoria_id));
  const sugerido = cat ? precioSugerido(Number(cat.precio_base), f.estado) : null;
  const destino = f.estado === 'Muy malo' ? 'descarte' : !f.titulo.trim() ? null : coincidencia?.en_acervo ? 'venta' : 'acervo';

  const cargar = useAccion((clave) => rpc('cargar_ejemplar', {
    p_lote: Number(id), p_titulo: f.titulo, p_autor: f.autor, p_editorial: f.editorial || null,
    p_anio: f.anio ? Number(f.anio) : null, p_categoria: Number(f.categoria || coincidencia?.categoria_id),
    p_estado_fisico: f.estado, p_ubicacion: f.ubicacion ? Number(f.ubicacion) : null,
    p_motivo_descarte: f.estado === 'Muy malo' ? f.motivo : null, p_reciclado: f.reciclado, p_observaciones: f.obs || null, p_idem: clave,
  }));
  const estadoLote = useAccion((_c, estado) => rpc('cambiar_estado_lote', { p_lote: Number(id), p_estado: estado }));

  async function enviar(e) {
    e.preventDefault();
    const r = await cargar.ejecutar();
    if (r) {
      setResultado(r);
      setF((x) => ({ ...VACIO, categoria: x.categoria, ubicacion: x.ubicacion, estado: x.estado === 'Muy malo' ? 'Bueno' : x.estado }));
      lote.recargar();
      tituloRef.current?.focus();
    }
  }

  if (lote.cargando && !lote.datos) return <Cargando />;
  if (lote.error) return <Aviso error={lote.error} />;
  const l = lote.datos;
  const pendientes = l.ejemplares.filter((e) => e.estado === 'En clasificación');

  return (
    <div className="space-y-6">
      <Link to="/panel/donaciones" className="text-sm text-tinta/70 hover:text-lacre">← Donaciones</Link>
      <Titulo sub={`${l.codigo} · recibido el ${fecha(l.recibido_en, { year: 'numeric' })} · ${l.ejemplares.length} ejemplares`}
        accion={<div className="flex items-center gap-2"><Estado valor={l.estado} />
          {l.estado !== 'Clasificado' ? <Boton tam="sm" variante="secundario" cargando={estadoLote.cargando}
            onClick={async () => { if ((await estadoLote.ejecutar('Clasificado')) !== undefined) lote.recargar(); }}>Marcar clasificado</Boton> : null}</div>}>
        {l.anonima ? 'Donación anónima' : l.procedencia}
      </Titulo>
      <Aviso error={estadoLote.error} onCerrar={estadoLote.limpiar} />

      {l.estado !== 'Clasificado' ? (
        <Tarjeta className="p-5">
          <h2 className="mb-4 font-titulo text-xl font-bold text-tinta">Cargar un ejemplar</h2>
          <form onSubmit={enviar} className="grid gap-4 md:grid-cols-6">
            <Campo etiqueta="Título" className="md:col-span-3">
              <Entrada ref={tituloRef} value={f.titulo} onChange={set('titulo')} required list="titulos-conocidos" autoFocus />
              <datalist id="titulos-conocidos">{titulos.map((t) => <option key={t.id} value={t.titulo}>{t.autor}</option>)}</datalist>
            </Campo>
            <Campo etiqueta="Autor" className="md:col-span-3">
              <Entrada value={f.autor} onChange={set('autor')} placeholder="Si no figura, queda «Anónimo»"
                onFocus={() => { if (!f.autor && titulos.length === 1) setF((x) => ({ ...x, autor: titulos[0].autor, categoria: String(titulos[0].categoria_id), editorial: titulos[0].editorial || '', anio: titulos[0].anio || '' })); }} />
            </Campo>
            <Campo etiqueta="Editorial" className="md:col-span-2"><Entrada value={f.editorial} onChange={set('editorial')} /></Campo>
            <Campo etiqueta="Año" className="md:col-span-1"><Entrada type="number" value={f.anio} onChange={set('anio')} min="1500" max="2100" /></Campo>
            <Campo etiqueta="Categoría" className="md:col-span-3">
              <Selector value={f.categoria || (coincidencia ? String(coincidencia.categoria_id) : '')} onChange={set('categoria')} required>
                <option value="">Elegí…</option>
                {base.datos?.cats.map((c) => <option key={c.id} value={c.id}>{c.nombre} ({plata(c.precio_base)})</option>)}
              </Selector>
            </Campo>
            <fieldset className="md:col-span-4">
              <legend className="mb-1 text-sm font-semibold text-tinta">Estado físico</legend>
              <div className="grid grid-cols-4 gap-2">
                {['Muy bueno', 'Bueno', 'Regular', 'Muy malo'].map((e) => (
                  <button type="button" key={e} onClick={() => setF((x) => ({ ...x, estado: e }))} aria-pressed={f.estado === e}
                    className={cx('rounded-md px-2 py-2.5 text-sm font-semibold ring-2', f.estado === e ? (e === 'Muy malo' ? 'bg-lacre text-papel ring-lacre' : 'bg-tinta text-papel ring-tinta') : 'bg-papel ring-tinta/20')}>
                    {e}<span className="block text-xs font-normal opacity-75">{{ 'Muy bueno': '100 %', Bueno: '80 %', Regular: '50 %', 'Muy malo': 'descartar' }[e]}</span>
                  </button>
                ))}
              </div>
            </fieldset>
            <Campo etiqueta="Ubicación" className="md:col-span-2">
              <Selector value={f.ubicacion} onChange={set('ubicacion')}>
                <option value="">Estante A1 (por defecto)</option>
                {base.datos?.ubics.map((u) => <option key={u.id} value={u.id}>{u.codigo}</option>)}
              </Selector>
            </Campo>
            {f.estado === 'Muy malo' ? (
              <>
                <Campo etiqueta="Motivo del descarte" className="md:col-span-4"><Entrada value={f.motivo} onChange={set('motivo')} required placeholder="Humedad, hojas sueltas, lomo partido…" /></Campo>
                <label className="flex items-center gap-2 md:col-span-2 md:pt-6"><input type="checkbox" className="h-5 w-5 accent-tinta" checked={f.reciclado} onChange={set('reciclado')} /> Va a reciclado</label>
              </>
            ) : null}

            <div className={cx('rounded-md p-3 md:col-span-6', destino === 'acervo' ? 'bg-tinta text-papel' : destino === 'venta' ? 'bg-pino-50 text-pino' : destino === 'descarte' ? 'bg-lacre-50 text-lacre-700' : 'bg-papel-300 text-tinta')}>
              {destino === 'acervo' ? <><b>Va al acervo.</b> Este título no está en la biblioteca: el primer ejemplar se queda en la sala y no se vende.</>
                : destino === 'venta' ? <><b>Queda para la venta.</b> La biblioteca ya tiene este título. Precio sugerido: <b>{sugerido ? plata(sugerido) : '—'}</b> (lo podés cambiar antes de publicar).</>
                : destino === 'descarte' ? <><b>Se descarta</b>{f.reciclado ? ' y va a reciclado' : ''}. No cuenta para el acervo.</>
                : 'Escribí el título para ver a dónde va.'}
            </div>
            <div className="md:col-span-6"><Aviso error={cargar.error} /></div>
            <div className="md:col-span-6"><Boton type="submit" tam="lg" cargando={cargar.cargando}>Cargar ejemplar</Boton></div>
          </form>
          {resultado ? (
            <p className="mt-4 rounded bg-papel-300 px-3 py-2 text-sm" role="status">
              Cargado <b>{resultado.codigo}</b> · «{resultado.titulo}» →{' '}
              <b>{resultado.destino === 'acervo' ? 'Acervo (no se vende)' : resultado.destino === 'descartado' ? 'Descartado' : `En clasificación, sugerido ${plata(resultado.precio_sugerido)}`}</b>
            </p>
          ) : null}
        </Tarjeta>
      ) : null}

      <section>
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <h2 className="font-titulo text-xl font-bold text-tinta">Ejemplares del lote</h2>
          {pendientes.length ? <p className="text-sm text-tinta/70">{pendientes.length} esperando precio para publicarse</p> : null}
        </div>
        <div className="overflow-x-auto">
          <table className="tabla">
            <thead><tr><th>Código</th><th>Título</th><th>Estado físico</th><th>Ubicación</th><th>Estado</th><th>Precio</th></tr></thead>
            <tbody>
              {l.ejemplares.sort((a, b) => a.codigo.localeCompare(b.codigo)).map((e) => (
                <tr key={e.id}>
                  <td className="font-mono text-xs">{e.codigo}</td>
                  <td><p className="font-semibold">{e.titulos.titulo}</p><p className="text-xs text-tinta/60">{e.titulos.autor}</p>
                    <Lomo nombre={e.titulos.categorias.nombre} color={e.titulos.categorias.color} className="mt-1" /></td>
                  <td>{e.estado_fisico}</td>
                  <td>{e.ubicaciones?.codigo || '—'}</td>
                  <td><Estado valor={e.estado} />{e.motivo_descarte ? <p className="mt-1 text-xs text-tinta/60">{e.motivo_descarte}</p> : null}</td>
                  <td>{e.estado === 'En clasificación' ? <FilaPublicar e={e} onListo={lote.recargar} /> : e.estado === 'Acervo' ? <span className="text-xs text-tinta/60">no se vende</span> : e.precio ? plata(e.precio) : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
