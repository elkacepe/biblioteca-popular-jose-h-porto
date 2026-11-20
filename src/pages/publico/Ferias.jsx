import { rpc } from '../../lib/api.js';
import { diaSemana, fecha, hora } from '../../lib/formato.js';
import { Aviso, Cargando, Estado, Tarjeta, Titulo, Vacio, useDatos } from '../../components/ui.jsx';

export default function FeriasPublicas() {
  const { datos, error, cargando } = useDatos(() => rpc('ferias_publicas'));
  const proximas = (datos || []).filter((f) => f.estado !== 'Cerrada');
  const pasadas = (datos || []).filter((f) => f.estado === 'Cerrada').reverse();
  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <Titulo sub="Un domingo por mes, de 10 a 13, en la plazoleta del Reloj Cucú.">Feria solidaria del libro</Titulo>
      <Tarjeta className="grid gap-4 p-5 sm:grid-cols-3">
        <div><p className="font-titulo text-lg font-bold text-lacre">3 libros</p><p className="text-tinta/80">Llevando 3 en la misma compra, el más barato va de regalo. Con 6, van dos.</p></div>
        <div><p className="font-titulo text-lg font-bold text-lacre">Solo en la feria</p><p className="text-tinta/80">Lo que está en las cajas de la feria no figura en la web ese día.</p></div>
        <div><p className="font-titulo text-lg font-bold text-lacre">Sin descuento de socio</p><p className="text-tinta/80">En la feria rige la promo de 3 libros; el 15 % de socio vale en la web y el mostrador.</p></div>
      </Tarjeta>
      <Aviso error={error} />
      {cargando ? <Cargando /> : null}
      {!cargando && !proximas.length ? <Vacio titulo="Todavía no hay fecha para la próxima feria" texto="Pasá por la biblioteca o seguinos: la anunciamos con tiempo." /> : null}
      {proximas.map((f) => (
        <Tarjeta key={f.id} className="flex items-center gap-5 p-5">
          <div className="rounded-md bg-lacre px-4 py-2 text-center text-papel">
            <p className="text-xs font-bold uppercase">{fecha(f.fecha, { day: undefined, month: 'short' })}</p>
            <p className="font-titulo text-4xl font-bold leading-none">{new Date(f.fecha + 'T12:00:00').getDate()}</p>
          </div>
          <div className="flex-1">
            <p className="font-titulo text-xl font-bold first-letter:uppercase text-tinta">{diaSemana(f.fecha)} {fecha(f.fecha, { month: 'long' })}</p>
            <p className="text-tinta/80">De {hora(f.hora_inicio)} a {hora(f.hora_fin)} · {f.lugar}</p>
          </div>
          <Estado valor={f.estado === 'Abierta' ? 'Abierta' : 'Planificada'} />
        </Tarjeta>
      ))}
      {pasadas.length ? (
        <div>
          <p className="mb-2 font-titulo font-bold text-tinta/70">Ferias anteriores</p>
          <ul className="space-y-1 text-tinta/70">{pasadas.map((f) => <li key={f.id}>{fecha(f.fecha, { month: 'long', year: 'numeric' })} · {f.lugar}</li>)}</ul>
        </div>
      ) : null}
    </div>
  );
}
