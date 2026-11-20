import { Link } from 'react-router-dom';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, fecha, hoyISO } from '../../lib/formato.js';
import { Aviso, Cargando, Estado, Selector, Tarjeta, Titulo, cx, useAccion, useDatos } from '../../components/ui.jsx';

function FilaRecorrido({ r, repartidores, onCambio }) {
  const asignar = useAccion((_c, u) => rpc('asignar_repartidor', { p_recorrido: r.id, p_usuario: u || null }));
  const usados = r.cupo_total - r.cupo_disponible;
  const fallidas = r.entregas.filter((e) => e.resultado === 'No entregada').length;
  return (
    <Tarjeta className="p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-titulo text-lg font-bold first-letter:uppercase text-tinta">{diaSemana(r.fecha)} {fecha(r.fecha)} · {r.zonas.nombre}</p>
          <p className={cx('text-sm font-semibold', r.cupo_disponible === 0 ? 'text-lacre' : 'text-tinta/75')}>
            {r.cupo_disponible === 0 ? 'Completo: los pedidos nuevos van al recorrido siguiente' : `Quedan ${r.cupo_disponible} ${r.cupo_disponible === 1 ? 'lugar' : 'lugares'} de ${r.cupo_total}`}
          </p>
        </div>
        <Estado valor={r.estado} />
      </div>
      <div className="my-3 h-2 overflow-hidden rounded bg-papel-300"><div className="h-full bg-tinta" style={{ width: `${(usados / r.cupo_total) * 100}%` }} /></div>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Selector value={r.repartidor_id || ''} onChange={async (e) => { if ((await asignar.ejecutar(e.target.value)) !== undefined) onCambio(); }}
          className="w-auto py-1.5" aria-label="Repartidor" disabled={r.estado === 'Finalizado'}>
          <option value="">Sin repartidor</option>
          {repartidores.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
        </Selector>
        <p className="text-sm text-tinta/70">{r.entregas.length} entregas{fallidas ? ` · ${fallidas} fallidas` : ''}</p>
        {r.entregas.length ? <Link className="font-semibold text-tinta underline" to={`/panel/reparto/${r.id}`}>Ver hoja</Link> : null}
      </div>
      {asignar.error ? <p className="mt-2 text-sm text-lacre">{asignar.error.message}</p> : null}
    </Tarjeta>
  );
}

export default function Reparto() {
  const desde = new Date(Date.now() - 14 * 864e5).toISOString().slice(0, 10);
  const { datos, error, cargando, recargar } = useDatos(async () => {
    await rpc('proximo_recorrido', { p_zona: 1 });   // asegura los recorridos de las próximas dos semanas
    const [recs, reps] = await Promise.all([
      consulta(supabase.from('recorridos').select('*, zonas(nombre), entregas(id, resultado)').gte('fecha', desde).order('fecha').order('zona_id')),
      consulta(supabase.from('perfiles').select('id, nombre').eq('rol', 'repartidor').order('nombre')),
    ]);
    return { recs, reps };
  });
  if (cargando && !datos) return <Cargando />;
  const hoy = hoyISO();
  const proximos = (datos?.recs || []).filter((r) => r.fecha >= hoy);
  const pasados = (datos?.recs || []).filter((r) => r.fecha < hoy && r.entregas.length).reverse();
  return (
    <div className="space-y-6">
      <Titulo sub="Centro, Villa del Lago y Santa Rita los martes; La Cuesta y Playas de Oro los jueves, de 15 a 19. 12 lugares por recorrido; los pedidos cierran a las 12 del día anterior.">Reparto</Titulo>
      <Aviso error={error} />
      <section>
        <h2 className="mb-3 font-titulo text-xl font-bold text-tinta">Próximas dos semanas</h2>
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">{proximos.map((r) => <FilaRecorrido key={r.id} r={r} repartidores={datos.reps} onCambio={recargar} />)}</div>
      </section>
      {pasados.length ? (
        <section>
          <h2 className="mb-3 font-titulo text-xl font-bold text-tinta">Recorridos anteriores</h2>
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">{pasados.map((r) => <FilaRecorrido key={r.id} r={r} repartidores={datos.reps} onCambio={recargar} />)}</div>
        </section>
      ) : null}
    </div>
  );
}
