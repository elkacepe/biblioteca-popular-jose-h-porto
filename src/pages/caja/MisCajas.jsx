import { Link } from 'react-router-dom';
import { consulta } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, fecha, hora } from '../../lib/formato.js';
import { useAuth } from '../../context/Auth.jsx';
import { Aviso, Cargando, Estado, Vacio, useDatos } from '../../components/ui.jsx';

export default function MisCajas() {
  const { perfil, rol } = useAuth();
  const { datos, error, cargando } = useDatos(async () => {
    // RLS: cada voluntario solo recibe las ferias que tiene asignadas.
    const [ferias, mostrador] = await Promise.all([
      consulta(supabase.from('ferias').select('*').neq('estado', 'Cerrada').order('fecha')),
      rol === 'bibliotecaria' ? Promise.resolve([{ id: 0 }])
        : consulta(supabase.from('asignaciones').select('id').eq('usuario_id', perfil.id).eq('tipo', 'mostrador')),
    ]);
    return { ferias, mostrador: mostrador.length > 0 };
  }, [perfil?.id]);

  if (cargando) return <Cargando />;
  return (
    <div className="space-y-4">
      <h1 className="font-titulo text-3xl font-bold text-carbon">Hola, {perfil?.nombre?.split(' ')[0]}</h1>
      <Aviso error={error} />
      {datos?.ferias.map((f) => (
        <Link key={f.id} to={`/caja/feria/${f.id}`} className="block rounded-xl bg-carbon p-5 text-papel active:scale-[.99]">
          <div className="flex items-center justify-between">
            <p className="text-sm font-bold uppercase tracking-widest text-mostaza">Feria</p>
            <Estado valor={f.estado} />
          </div>
          <p className="mt-1 font-titulo text-3xl font-bold first-letter:uppercase">{diaSemana(f.fecha)} {fecha(f.fecha)}</p>
          <p className="text-lg text-papel/85">{f.lugar} · {hora(f.hora_inicio)} a {hora(f.hora_fin)}</p>
          <p className="mt-3 text-xl font-semibold">Abrir la caja →</p>
        </Link>
      ))}
      {datos?.mostrador ? (
        <Link to="/caja/mostrador" className="block rounded-xl bg-tinta p-5 text-papel active:scale-[.99]">
          <p className="text-sm font-bold uppercase tracking-widest text-mostaza">Mostrador</p>
          <p className="mt-1 font-titulo text-3xl font-bold">Venta en la biblioteca</p>
          <p className="text-lg text-papel/85">Lunes a viernes, 8:30 a 12 y 15 a 19</p>
          <p className="mt-3 text-xl font-semibold">Abrir el mostrador →</p>
        </Link>
      ) : null}
      {!datos?.ferias.length && !datos?.mostrador ? (
        <Vacio titulo="No tenés ninguna caja asignada" texto="Cuando la bibliotecaria te asigne a una feria o al mostrador, va a aparecer acá." />
      ) : null}
    </div>
  );
}
