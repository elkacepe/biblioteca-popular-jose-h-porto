import { useEffect, useRef, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, fecha, hora, plata } from '../../lib/formato.js';
import { Aviso, Boton, Cargando, Entrada, Estado, Lomo, Selector, Tarjeta, Titulo, cx, useAccion, useDatos } from '../../components/ui.jsx';

function ArmarCaja({ caja, feriaCerrada, onCambio }) {
  const [codigo, setCodigo] = useState('');
  const [q, setQ] = useState('');
  const [sugerencias, setSugerencias] = useState([]);
  const [ultimo, setUltimo] = useState(null);
  const input = useRef(null);
  const libros = useDatos(() => consulta(supabase.from('ejemplares').select('id, codigo, precio, titulos(titulo, autor, categorias(nombre, color))')
    .eq('caja_feria_id', caja.id).eq('estado', 'En feria').order('codigo')), [caja.id, caja.cupo_disponible]);
  const agregar = useAccion((clave, cod) => rpc('agregar_a_caja', { p_caja: caja.id, p_codigo: cod, p_idem: clave }));
  const quitar = useAccion((_c, id) => rpc('quitar_de_caja', { p_ejemplar: id }));

  useEffect(() => {
    if (q.trim().length < 3) { setSugerencias([]); return undefined; }
    const t = setTimeout(() => {
      supabase.from('ejemplares').select('id, codigo, precio, titulos!inner(titulo, autor)').eq('estado', 'En venta')
        .ilike('titulos.titulo', `%${q.trim()}%`).limit(8).then(({ data }) => setSugerencias(data || []));
    }, 250);
    return () => clearTimeout(t);
  }, [q]);

  async function sumar(cod) {
    const r = await agregar.ejecutar(cod);
    if (r) { setUltimo(r); setCodigo(''); setQ(''); setSugerencias([]); onCambio(); input.current?.focus(); }
  }
  const usados = caja.cupo_total - caja.cupo_disponible;
  return (
    <Tarjeta className="p-4">
      <div className="mb-3 flex items-center justify-between">
        <p className="font-titulo text-lg font-bold text-tinta">Caja {caja.numero} <span className="text-sm font-normal text-tinta/60">· {caja.ubicaciones?.codigo}</span></p>
        <p className={cx('font-semibold tabular-nums', caja.cupo_disponible === 0 ? 'text-lacre' : 'text-tinta')}>{usados} / {caja.cupo_total}</p>
      </div>
      <div className="mb-3 h-2 overflow-hidden rounded bg-papel-300"><div className="h-full bg-lacre" style={{ width: `${(usados / caja.cupo_total) * 100}%` }} /></div>
      {!feriaCerrada ? (
        <div className="space-y-2">
          <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); if (codigo.trim()) sumar(codigo.trim()); }}>
            <Entrada ref={input} value={codigo} onChange={(e) => setCodigo(e.target.value.toUpperCase())} placeholder="Código PJ-01023" aria-label="Código del ejemplar" />
            <Boton type="submit" cargando={agregar.cargando} disabled={caja.cupo_disponible === 0}>Sumar</Boton>
          </form>
          <div className="relative">
            <Entrada value={q} onChange={(e) => setQ(e.target.value)} placeholder="…o buscá por título (solo libros en venta)" aria-label="Buscar por título" />
            {sugerencias.length ? (
              <ul className="absolute z-10 mt-1 w-full rounded-md bg-papel-100 shadow-lg ring-1 ring-tinta/20">
                {sugerencias.map((s) => (
                  <li key={s.id}><button className="flex w-full justify-between px-3 py-2 text-left hover:bg-papel-300" onClick={() => sumar(s.codigo)}>
                    <span>{s.titulos.titulo} <span className="text-xs text-tinta/60">{s.codigo}</span></span><span className="tabular-nums">{plata(s.precio)}</span></button></li>
                ))}
              </ul>
            ) : null}
          </div>
          {caja.cupo_disponible === 0 ? <p className="text-sm font-semibold text-lacre">La caja está llena: armá otra.</p> : null}
          <Aviso error={agregar.error || quitar.error} onActualizar={() => { agregar.limpiar(); onCambio(); }} onCerrar={() => { agregar.limpiar(); quitar.limpiar(); }} />
          {ultimo ? <p className="text-sm text-pino" role="status">✓ {ultimo.titulo} ({ultimo.codigo}) a la caja · {ultimo.repetida ? 'ya estaba' : `quedan ${ultimo.cupo_disponible} lugares`}. Ya no figura en la web.</p> : null}
        </div>
      ) : null}
      <ul className="mt-3 max-h-72 divide-y divide-dashed divide-tinta/15 overflow-y-auto text-sm">
        {(libros.datos || []).map((l) => (
          <li key={l.id} className="flex items-center justify-between gap-2 py-1.5">
            <span className="min-w-0"><span className="font-mono text-xs text-tinta/60">{l.codigo}</span> {l.titulos.titulo}</span>
            <span className="flex shrink-0 items-center gap-2"><span className="tabular-nums">{plata(l.precio)}</span>
              {!feriaCerrada ? <button className="text-xs text-lacre hover:underline" onClick={async () => { if ((await quitar.ejecutar(l.id)) !== undefined) onCambio(); }}>quitar</button> : null}</span>
          </li>
        ))}
      </ul>
    </Tarjeta>
  );
}

export default function Feria() {
  const { id } = useParams();
  const [nuevoVol, setNuevoVol] = useState('');
  const feria = useDatos(async () => {
    const [f, cajas, asig, voluntarios, resumen, arqueo] = await Promise.all([
      consulta(supabase.from('ferias').select('*').eq('id', id).single()),
      consulta(supabase.from('cajas_feria').select('*, ubicaciones(codigo)').eq('feria_id', id).order('numero')),
      consulta(supabase.from('asignaciones').select('id, usuario_id, perfiles(nombre, email)').eq('feria_id', id)),
      consulta(supabase.from('perfiles').select('id, nombre, email').eq('rol', 'caja').order('nombre')),
      rpc('resumen_caja', { p_feria: Number(id) }),
      consulta(supabase.from('arqueos').select('*').eq('feria_id', id).maybeSingle()),
    ]);
    return { f, cajas, asig, voluntarios, resumen, arqueo };
  }, [id]);
  const nuevaCaja = useAccion(() => rpc('crear_caja_feria', { p_feria: Number(id) }));
  const abrir = useAccion(() => rpc('abrir_feria', { p_feria: Number(id) }));
  const asignar = useAccion(() => rpc('asignar_voluntario', { p_usuario: nuevoVol, p_tipo: 'feria', p_feria: Number(id) }));
  const desasignar = useAccion((_c, a) => rpc('quitar_asignacion', { p_asignacion: a }));

  if (feria.cargando && !feria.datos) return <Cargando />;
  if (feria.error) return <Aviso error={feria.error} />;
  const { f, cajas, asig, voluntarios, resumen, arqueo } = feria.datos;
  const cerrada = f.estado === 'Cerrada';
  const activas = cajas.filter((k) => k.activa || !cerrada);
  const err = nuevaCaja.error || abrir.error || asignar.error || desasignar.error;

  return (
    <div className="space-y-6">
      <Link to="/panel/ferias" className="text-sm text-tinta/70 hover:text-lacre">← Ferias</Link>
      <Titulo sub={`${f.lugar} · de ${hora(f.hora_inicio)} a ${hora(f.hora_fin)}`}
        accion={<div className="flex flex-wrap items-center gap-2"><Estado valor={f.estado} className="text-sm" />
          {f.estado === 'Planificada' ? <Boton variante="exito" cargando={abrir.cargando} onClick={async () => { if ((await abrir.ejecutar()) !== undefined) feria.recargar(); }}>Abrir la feria</Boton> : null}
          {!cerrada ? <Link to={`/caja/feria/${id}`}><Boton variante="secundario">Ir a la caja</Boton></Link> : null}
          {f.estado === 'Abierta' ? <Link to={`/caja/feria/${id}/cierre`}><Boton variante="peligro">Cerrar y rendir</Boton></Link> : null}</div>}>
        <span className="inline-block first-letter:uppercase">{diaSemana(f.fecha)}</span> {fecha(f.fecha, { month: 'long', year: 'numeric' })}
      </Titulo>
      <Aviso error={err} onCerrar={() => [nuevaCaja, abrir, asignar, desasignar].forEach((a) => a.limpiar())} />

      <section className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Tarjeta className="p-4"><p className="font-titulo text-3xl font-bold">{resumen.ventas}</p><p className="text-sm text-tinta/70">ventas</p></Tarjeta>
        <Tarjeta className="p-4"><p className="font-titulo text-3xl font-bold">{resumen.ejemplares}</p><p className="text-sm text-tinta/70">libros vendidos</p></Tarjeta>
        <Tarjeta className="p-4"><p className="font-titulo text-3xl font-bold">{plata(Number(resumen.efectivo) + Number(resumen.transferencias))}</p><p className="text-sm text-tinta/70">recaudado ({plata(resumen.efectivo)} efectivo)</p></Tarjeta>
        <Tarjeta className="p-4"><p className="font-titulo text-3xl font-bold">{cerrada ? arqueo?.ejemplares_devueltos ?? 0 : resumen.sin_vender}</p><p className="text-sm text-tinta/70">{cerrada ? 'volvieron al depósito' : 'en las cajas'}</p></Tarjeta>
      </section>

      {arqueo ? (
        <Tarjeta className="p-4">
          <p className="font-titulo text-lg font-bold text-tinta">Rendición cerrada 🔒</p>
          <p className="text-tinta/80">Esperado {plata(Number(arqueo.efectivo_esperado) + Number(arqueo.transferencias_registradas))} · contado {plata(Number(arqueo.efectivo_contado) + Number(arqueo.transferencias_informadas))} ·
            diferencia <b className={Number(arqueo.diferencia) ? 'text-lacre' : 'text-pino'}>{plata(arqueo.diferencia)}</b>{arqueo.motivo_diferencia ? ` — ${arqueo.motivo_diferencia}` : ''}</p>
          <Link className="text-sm underline" to="/panel/rendiciones">Ver en rendiciones</Link>
        </Tarjeta>
      ) : null}

      <section>
        <h2 className="mb-2 font-titulo text-xl font-bold text-tinta">Voluntariado de caja</h2>
        <div className="flex flex-wrap items-center gap-2">
          {asig.map((a) => (
            <span key={a.id} className="inline-flex items-center gap-2 rounded-full bg-papel-100 px-3 py-1.5 ring-1 ring-tinta/20">
              {a.perfiles?.nombre}
              {!cerrada ? <button aria-label={`Quitar a ${a.perfiles?.nombre}`} className="text-tinta/50 hover:text-lacre" onClick={async () => { if ((await desasignar.ejecutar(a.id)) !== undefined) feria.recargar(); }}>×</button> : null}
            </span>
          ))}
          {!cerrada ? (
            <span className="inline-flex gap-2">
              <Selector value={nuevoVol} onChange={(e) => setNuevoVol(e.target.value)} className="py-1.5" aria-label="Sumar voluntario">
                <option value="">Sumar voluntario/a…</option>
                {voluntarios.filter((v) => !asig.some((a) => a.usuario_id === v.id)).map((v) => <option key={v.id} value={v.id}>{v.nombre}</option>)}
              </Selector>
              <Boton tam="sm" disabled={!nuevoVol} cargando={asignar.cargando} onClick={async () => { if ((await asignar.ejecutar()) !== undefined) { setNuevoVol(''); feria.recargar(); } }}>Asignar</Boton>
            </span>
          ) : null}
        </div>
        <p className="mt-1 text-sm text-tinta/60">Solo las personas asignadas ven y operan la caja de esta feria.</p>
      </section>

      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="font-titulo text-xl font-bold text-tinta">Cajas ({cajas.length} de 8)</h2>
          {!cerrada && cajas.length < 8 ? <Boton tam="sm" cargando={nuevaCaja.cargando} onClick={async () => { if (await nuevaCaja.ejecutar()) feria.recargar(); }}>+ Nueva caja</Boton> : null}
        </div>
        <p className="mb-3 text-sm text-tinta/70">Al sumar un libro a una caja pasa a «En feria» y desaparece de la web. Al cerrar la feria, los que no se vendieron vuelven a su estante.</p>
        <div className="grid gap-4 lg:grid-cols-2">
          {activas.map((k) => <ArmarCaja key={k.id} caja={k} feriaCerrada={cerrada} onCambio={feria.recargar} />)}
        </div>
        {!activas.length ? <p className="text-tinta/70">Todavía no hay cajas. <Lomo nombre="Tip" color="#2F6B5E" /> Armá la primera con «Nueva caja».</p> : null}
      </section>
    </div>
  );
}
