import { Link } from 'react-router-dom';
import { rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, fecha, hoyISO, plata } from '../../lib/formato.js';
import { useAuth } from '../../context/Auth.jsx';
import { Aviso, Cargando, Estado, Tarjeta, Titulo, useDatos } from '../../components/ui.jsx';

const ESTADOS = ['En clasificación', 'Acervo', 'En venta', 'Reservado', 'En feria', 'Vendido', 'En devolución', 'Descartado'];

async function contar(tabla, filtro) {
  let q = supabase.from(tabla).select('*', { count: 'exact', head: true });
  q = filtro(q);
  const { count, error } = await q;
  if (error) throw error;
  return count || 0;
}

function Contador({ n, texto, to, tono = 'tinta' }) {
  const color = { tinta: 'text-tinta', lacre: 'text-lacre', pino: 'text-pino', mostaza: 'text-carbon' }[tono];
  const cont = (
    <Tarjeta className="h-full p-4 transition hover:ring-2 hover:ring-tinta/40">
      <p className={`font-titulo text-4xl font-bold tabular-nums ${color}`}>{n}</p>
      <p className="text-sm text-tinta/80">{texto}</p>
    </Tarjeta>
  );
  return to ? <Link to={to}>{cont}</Link> : cont;
}

export default function Inicio() {
  const { rol, perfil } = useAuth();
  const biblio = rol === 'bibliotecaria';
  const { datos, error, cargando } = useDatos(async () => {
    await rpc('disponibilidad', { p_ids: [] });          // aplica vencimientos pendientes
    const mes = hoyISO().slice(0, 7);
    const [porEstado, reservados, cobrados, retiro, devs, ferias, recaudacion] = await Promise.all([
      Promise.all(ESTADOS.map((e) => contar('ejemplares', (q) => q.eq('estado', e)))),
      contar('pedidos', (q) => q.eq('estado', 'Reservado')),
      contar('pedidos', (q) => q.in('estado', ['Cobrado'])),
      contar('pedidos', (q) => q.eq('estado', 'Retiro en biblioteca')),
      contar('devoluciones', (q) => q.in('estado', ['Solicitada', 'En revisión'])),
      supabase.from('ferias').select('*').neq('estado', 'Cerrada').order('fecha').limit(1),
      rpc('informe_recaudacion', { p_desde: `${mes}-01`, p_hasta: null, p_canal: null }),
    ]);
    const porCanal = { web: 0, mostrador: 0, feria: 0 };
    recaudacion.forEach((r) => { porCanal[r.canal] += Number(r.neto); });
    return { porEstado, reservados, cobrados, retiro, devs, feria: ferias.data?.[0], porCanal };
  });

  if (cargando) return <Cargando />;
  if (error) return <Aviso error={error} />;
  const d = datos;
  const total = d.porCanal.web + d.porCanal.mostrador + d.porCanal.feria;
  return (
    <div className="space-y-8">
      <Titulo sub={`${diaSemana(hoyISO())} ${fecha(hoyISO(), { month: 'long' })}`}>Buen día, {perfil?.nombre?.split(' ')[0]}</Titulo>

      {biblio ? (
        <section className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <Contador n={d.reservados} texto="reservas web esperando cobro (48 h)" to="/panel/pedidos" tono="mostaza" />
          <Contador n={d.cobrados} texto="pedidos cobrados para preparar" to="/panel/pedidos" />
          <Contador n={d.retiro} texto="esperando retiro en la biblioteca" to="/panel/pedidos" tono="lacre" />
          <Contador n={d.devs} texto="devoluciones por revisar" to="/panel/devoluciones" tono="lacre" />
        </section>
      ) : null}

      <section>
        <h2 className="mb-3 font-titulo text-xl font-bold text-tinta">Recaudación del mes</h2>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <Contador n={plata(total)} texto="total neto (ventas − reintegros)" tono="pino" to="/panel/informes" />
          <Contador n={plata(d.porCanal.feria)} texto="feria" />
          <Contador n={plata(d.porCanal.mostrador)} texto="mostrador" />
          <Contador n={plata(d.porCanal.web)} texto="web" />
        </div>
      </section>

      <section className="grid gap-6 md:grid-cols-[2fr_1fr]">
        <div>
          <h2 className="mb-3 font-titulo text-xl font-bold text-tinta">Ejemplares por estado</h2>
          <Tarjeta className="divide-y divide-dashed divide-tinta/20">
            {ESTADOS.map((e, i) => (
              <div key={e} className="flex items-center justify-between px-4 py-2.5">
                <Estado valor={e} />
                <span className="font-titulo text-lg font-bold tabular-nums text-tinta">{d.porEstado[i]}</span>
              </div>
            ))}
          </Tarjeta>
        </div>
        <div>
          <h2 className="mb-3 font-titulo text-xl font-bold text-tinta">Próxima feria</h2>
          {d.feria ? (
            <Link to={biblio ? `/panel/ferias/${d.feria.id}` : '/panel/rendiciones'}>
              <Tarjeta className="p-4 hover:ring-2 hover:ring-tinta/40">
                <p className="font-titulo text-2xl font-bold first-letter:uppercase text-lacre">{diaSemana(d.feria.fecha)} {fecha(d.feria.fecha)}</p>
                <p className="text-tinta/80">{d.feria.lugar}</p>
                <Estado valor={d.feria.estado} className="mt-2" />
              </Tarjeta>
            </Link>
          ) : <p className="text-tinta/70">No hay ninguna feria programada.</p>}
        </div>
      </section>
    </div>
  );
}
