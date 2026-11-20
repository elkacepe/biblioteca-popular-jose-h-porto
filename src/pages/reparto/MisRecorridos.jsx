import { Link } from 'react-router-dom';
import { consulta } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, fecha, hoyISO, hora } from '../../lib/formato.js';
import { Aviso, Cargando, Estado, Vacio, useDatos } from '../../components/ui.jsx';

export default function MisRecorridos() {
  // RLS: el repartidor solo recibe SUS recorridos y sus entregas.
  const { datos, error, cargando } = useDatos(() => consulta(supabase.from('recorridos')
    .select('*, zonas(nombre), entregas(id, resultado)').gte('fecha', hoyISO()).order('fecha')));
  if (cargando) return <Cargando />;
  const conEntregas = (datos || []).filter((r) => r.entregas.length);
  return (
    <div className="space-y-4 text-carbon">
      <h1 className="font-titulo text-3xl font-bold">Mis recorridos</h1>
      <Aviso error={error} grande />
      {!conEntregas.length ? <Vacio titulo="No tenés entregas asignadas" texto="Cuando haya pedidos para tus zonas, aparecen acá." /> : null}
      {conEntregas.map((r) => {
        const pend = r.entregas.filter((e) => e.resultado === 'Pendiente').length;
        return (
          <Link key={r.id} to={`/reparto/${r.id}`} className="block rounded-xl bg-carbon p-5 text-papel active:scale-[.99]">
            <div className="flex items-center justify-between"><p className="text-sm font-bold uppercase tracking-widest text-mostaza">Zona {r.zonas.nombre}</p><Estado valor={r.estado} /></div>
            <p className="mt-1 font-titulo text-3xl font-bold first-letter:uppercase">{r.fecha === hoyISO() ? 'Hoy' : diaSemana(r.fecha)} {fecha(r.fecha)}</p>
            <p className="text-lg text-papel/85">{hora(r.hora_inicio)} a {hora(r.hora_fin)} · {r.entregas.length} entregas · {pend} pendientes</p>
            <p className="mt-3 text-xl font-semibold">Abrir la hoja →</p>
          </Link>
        );
      })}
    </div>
  );
}
