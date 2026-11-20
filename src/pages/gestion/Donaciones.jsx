import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { fecha } from '../../lib/formato.js';
import { AreaTexto, Aviso, Boton, Campo, Cargando, Entrada, Estado, Modal, Tarjeta, Titulo, Vacio, useAccion, useDatos } from '../../components/ui.jsx';

export default function Donaciones() {
  const nav = useNavigate();
  const [nuevo, setNuevo] = useState(false);
  const [procedencia, setProcedencia] = useState('');
  const [anonima, setAnonima] = useState(false);
  const [obs, setObs] = useState('');
  const { datos, error, cargando } = useDatos(() => consulta(
    supabase.from('lotes').select('*, ejemplares(estado)').order('recibido_en', { ascending: false })));
  const crear = useAccion(() => rpc('crear_lote', { p_procedencia: procedencia, p_anonima: anonima, p_observaciones: obs }));

  return (
    <div>
      <Titulo sub="Cada donación entra como un lote. Al cargar sus libros, el sistema decide qué va al acervo y qué a la venta."
        accion={<Boton onClick={() => setNuevo(true)}>+ Recibir donación</Boton>}>Donaciones</Titulo>
      <Aviso error={error} />
      {cargando ? <Cargando /> : !datos?.length ? <Vacio titulo="Todavía no hay donaciones cargadas" /> : (
        <div className="grid gap-3 md:grid-cols-2">
          {datos.map((l) => {
            const cuenta = (e) => l.ejemplares.filter((x) => x.estado === e).length;
            return (
              <Link key={l.id} to={`/panel/donaciones/${l.id}`}>
                <Tarjeta className="h-full p-4 hover:ring-2 hover:ring-tinta/40">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <p className="font-titulo text-lg font-bold text-tinta">{l.anonima ? 'Donación anónima' : l.procedencia}</p>
                      <p className="text-sm text-tinta/65">{l.codigo} · recibido el {fecha(l.recibido_en, { year: 'numeric' })}</p>
                    </div>
                    <Estado valor={l.estado} />
                  </div>
                  <p className="mt-3 text-sm text-tinta/80">
                    {l.ejemplares.length} ejemplares · {cuenta('Acervo')} al acervo · {cuenta('En clasificación')} sin publicar · {cuenta('Descartado')} descartados
                  </p>
                  {l.observaciones ? <p className="mt-1 text-sm italic text-tinta/60">{l.observaciones}</p> : null}
                </Tarjeta>
              </Link>
            );
          })}
        </div>
      )}
      <Modal abierto={nuevo} titulo="Recibir una donación" onCerrar={() => setNuevo(false)}>
        <div className="space-y-4">
          <label className="flex items-center gap-3 text-lg">
            <input type="checkbox" className="h-6 w-6 accent-tinta" checked={anonima} onChange={(e) => setAnonima(e.target.checked)} />
            Es anónima
          </label>
          {!anonima ? <Campo etiqueta="¿De quién viene?"><Entrada value={procedencia} onChange={(e) => setProcedencia(e.target.value)} placeholder="Familia, institución, vecino…" /></Campo> : null}
          <Campo etiqueta="Observaciones"><AreaTexto value={obs} onChange={(e) => setObs(e.target.value)} placeholder="Cantidad de cajas, estado general…" /></Campo>
          <Aviso error={crear.error} />
          <Boton tam="lg" className="w-full" cargando={crear.cargando}
            onClick={async () => { const l = await crear.ejecutar(); if (l) nav(`/panel/donaciones/${l.id}`); }}>Crear lote y empezar a clasificar</Boton>
        </div>
      </Modal>
    </div>
  );
}
