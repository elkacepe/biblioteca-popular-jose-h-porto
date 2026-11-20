import { Link, useParams } from 'react-router-dom';
import { rpc } from '../../lib/api.js';
import { plata } from '../../lib/formato.js';
import { textos, WHATSAPP_BIBLIOTECA } from '../../lib/whatsapp.js';
import { useBolsa } from '../../context/Bolsa.jsx';
import { Aviso, Boton, BotonWhatsApp, Cargando, Dato, Lomo, Vacio, useDatos } from '../../components/ui.jsx';

export default function Libro() {
  const { id } = useParams();
  const bolsa = useBolsa();
  const { datos, error, cargando } = useDatos(async () => (await rpc('ejemplar_publico', { p_id: id }))[0] || null, [id]);
  if (cargando) return <Cargando />;
  if (error) return <Aviso error={error} />;
  if (!datos) return <Vacio titulo="No encontramos este libro">Volver al <Link className="underline" to="/">catálogo</Link></Vacio>;
  const l = datos;
  return (
    <div className="mx-auto max-w-3xl">
      <Link to="/" className="text-sm text-tinta/70 hover:text-lacre">← Volver al catálogo</Link>
      <article className="mt-3 flex overflow-hidden rounded-lg bg-papel-100 shadow-papel ring-1 ring-tinta/10">
        <div className="hidden w-16 shrink-0 items-center justify-center sm:flex" style={{ background: l.categoria_color }}>
          <span className="rotate-180 font-titulo text-lg font-bold tracking-wide text-papel [writing-mode:vertical-rl]">{l.titulo}</span>
        </div>
        <div className="flex-1 p-6">
          <Lomo nombre={l.categoria} color={l.categoria_color} />
          <h1 className="mt-3 font-titulo text-3xl font-bold text-tinta">{l.titulo}</h1>
          <p className="text-lg text-tinta/85">{l.autor}</p>
          <dl className="mt-5 grid grid-cols-2 gap-4 sm:grid-cols-4">
            <Dato etiqueta="Editorial">{l.editorial || '—'}</Dato>
            <Dato etiqueta="Año">{l.anio || '—'}</Dato>
            <Dato etiqueta="Estado">{l.estado_fisico}</Dato>
            <Dato etiqueta="Código">{l.codigo}</Dato>
          </dl>
          {l.disponible ? (
            <div className="mt-6 flex flex-wrap items-end justify-between gap-4 border-t border-dashed border-tinta/25 pt-5">
              <div>
                <p className="font-titulo text-4xl font-bold text-tinta">{plata(l.precio)}</p>
                <p className="text-pino">Socios con la cuota al día: {plata(l.precio_socio)}</p>
              </div>
              <Boton tam="lg" variante={bolsa.tiene(l.id) ? 'secundario' : 'primario'} onClick={() => (bolsa.tiene(l.id) ? bolsa.quitar(l.id) : bolsa.agregar(l))}>
                {bolsa.tiene(l.id) ? '✓ Está en tu bolsa' : 'Sumar a la bolsa'}
              </Boton>
            </div>
          ) : (
            <div className="mt-6 border-t border-dashed border-tinta/25 pt-5">
              <p className="sello text-lacre">Este libro ya encontró dueño</p>
              <p className="mt-3 text-tinta/80">
                {Number(l.otros_disponibles) > 0
                  ? `Pero hay ${l.otros_disponibles} ${Number(l.otros_disponibles) === 1 ? 'otro ejemplar' : 'otros ejemplares'} del mismo título. Buscalo en el catálogo.`
                  : 'Puede que aparezca otro en la próxima feria o en las donaciones que van llegando.'}
              </p>
            </div>
          )}
          <div className="mt-5">
            <BotonWhatsApp texto={textos.consulta(l.titulo)} telefono={WHATSAPP_BIBLIOTECA} tam="sm" className="bg-transparent text-pino ring-2 ring-inset ring-pino hover:bg-pino-50">
              Preguntar por WhatsApp
            </BotonWhatsApp>
          </div>
        </div>
      </article>
    </div>
  );
}
