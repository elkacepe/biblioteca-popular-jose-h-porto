import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, fecha, hora, hoyISO, plata } from '../../lib/formato.js';
import { Aviso, Boton, Campo, Cargando, Entrada, Estado, Modal, Tarjeta, Titulo, Vacio, useAccion, useDatos } from '../../components/ui.jsx';

function proximoDomingo() {
  const d = new Date(hoyISO() + 'T12:00:00');
  d.setDate(d.getDate() + ((7 - d.getDay()) % 7 || 7));
  return d.toISOString().slice(0, 10);
}

export default function Ferias() {
  const nav = useNavigate();
  const [nueva, setNueva] = useState(false);
  const [f, setF] = useState({ fecha: proximoDomingo(), lugar: 'Plazoleta del Reloj Cucú', inicio: '10:00', fin: '13:00' });
  const { datos, error, cargando } = useDatos(() => consulta(supabase.from('ferias').select('*, cajas_feria(id, cupo_total, cupo_disponible, activa), arqueos(diferencia, efectivo_contado, transferencias_informadas)').order('fecha', { ascending: false })));
  const crear = useAccion(() => rpc('crear_feria', { p_fecha: f.fecha, p_lugar: f.lugar, p_hora_inicio: f.inicio, p_hora_fin: f.fin }));
  return (
    <div>
      <Titulo sub="Un domingo por mes, de 10 a 13. Hasta 8 cajas de 40 libros." accion={<Boton onClick={() => setNueva(true)}>+ Programar feria</Boton>}>Ferias</Titulo>
      <Aviso error={error} />
      {cargando ? <Cargando /> : !datos?.length ? <Vacio titulo="No hay ferias cargadas" /> : (
        <div className="grid gap-3 md:grid-cols-2">
          {datos.map((x) => {
            const libros = x.cajas_feria.reduce((s, k) => s + (k.cupo_total - k.cupo_disponible), 0);
            const a = x.arqueos?.[0] || x.arqueos;
            return (
              <Link key={x.id} to={`/panel/ferias/${x.id}`}>
                <Tarjeta className="flex items-center gap-4 p-4 hover:ring-2 hover:ring-tinta/40">
                  <div className="rounded bg-lacre px-3 py-1 text-center text-papel">
                    <p className="text-xs font-bold uppercase">{fecha(x.fecha, { day: undefined, month: 'short' })}</p>
                    <p className="font-titulo text-3xl font-bold leading-none">{new Date(x.fecha + 'T12:00:00').getDate()}</p>
                  </div>
                  <div className="flex-1">
                    <p className="font-titulo text-lg font-bold first-letter:uppercase text-tinta">{diaSemana(x.fecha)} {fecha(x.fecha, { month: 'long', year: 'numeric' })}</p>
                    <p className="text-sm text-tinta/70">{x.lugar} · {hora(x.hora_inicio)} a {hora(x.hora_fin)}</p>
                    <p className="text-sm text-tinta/70">{x.cajas_feria.length} cajas{x.estado !== 'Cerrada' ? ` · ${libros} libros armados` : ''}{a && x.estado === 'Cerrada' ? ` · diferencia ${plata(a.diferencia)}` : ''}</p>
                  </div>
                  <Estado valor={x.estado} />
                </Tarjeta>
              </Link>
            );
          })}
        </div>
      )}
      <Modal abierto={nueva} titulo="Programar feria" onCerrar={() => setNueva(false)}>
        <div className="space-y-4">
          <Campo etiqueta="Fecha (domingo)"><Entrada type="date" value={f.fecha} onChange={(e) => setF({ ...f, fecha: e.target.value })} /></Campo>
          <Campo etiqueta="Lugar"><Entrada value={f.lugar} onChange={(e) => setF({ ...f, lugar: e.target.value })} /></Campo>
          <div className="grid grid-cols-2 gap-3">
            <Campo etiqueta="Desde"><Entrada type="time" value={f.inicio} onChange={(e) => setF({ ...f, inicio: e.target.value })} /></Campo>
            <Campo etiqueta="Hasta"><Entrada type="time" value={f.fin} onChange={(e) => setF({ ...f, fin: e.target.value })} /></Campo>
          </div>
          <Aviso error={crear.error} />
          <Boton tam="lg" className="w-full" cargando={crear.cargando} onClick={async () => { const r = await crear.ejecutar(); if (r) nav(`/panel/ferias/${r.id}`); }}>Programar</Boton>
        </div>
      </Modal>
    </div>
  );
}
