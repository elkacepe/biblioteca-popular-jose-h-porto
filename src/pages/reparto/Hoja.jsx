import { useState } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import { rpc } from '../../lib/api.js';
import { diaSemana, fecha, fechaHora, hora, plata } from '../../lib/formato.js';
import { MOTIVOS_NO_ENTREGA } from '../../lib/reglas.js';
import { textos } from '../../lib/whatsapp.js';
import { Aviso, Boton, BotonWhatsApp, Cargando, Estado, cx, useAccion, useDatos } from '../../components/ui.jsx';

function Entrega({ e, dia, onCambio }) {
  const [fallo, setFallo] = useState(false);
  const [otro, setOtro] = useState('');
  const [resultado, setResultado] = useState(null);
  const marcar = useAccion((clave, entregada, motivo) => rpc('marcar_entrega', { p_entrega: e.id, p_entregada: entregada, p_motivo: motivo, p_idem: clave }));

  async function confirmar(entregada, motivo) {
    const r = await marcar.ejecutar(entregada, motivo);
    if (r) { setResultado(r); setFallo(false); onCambio(); }
  }
  const pendiente = e.resultado === 'Pendiente';
  const proximo = resultado?.reprogramado_para ? `${diaSemana(resultado.reprogramado_para)} ${fecha(resultado.reprogramado_para)}` : null;

  return (
    <li className={cx('rounded-xl bg-white p-4 ring-4', pendiente ? 'ring-carbon' : e.resultado === 'Entregada' ? 'ring-pino' : 'ring-lacre')}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-bold uppercase tracking-wider text-carbon/60">Pedido #{e.numero}{e.intento > 1 ? ` · ${e.intento}.º intento` : ''}</p>
          <p className="font-titulo text-2xl font-bold">{e.contacto}</p>
          <p className="text-xl">{e.direccion}</p>
          <a href={`tel:${e.telefono}`} className="text-lg font-semibold text-tinta underline">{e.telefono}</a>
        </div>
        <Estado valor={e.resultado} className="text-sm" />
      </div>
      <p className="mt-2 text-lg">{e.libros} {e.libros === 1 ? 'libro' : 'libros'}: <span className="text-carbon/75">{e.titulos}</span></p>
      <p className="text-lg font-semibold">{e.cobrado ? 'Ya está pagado' : `Cobrar ${plata(e.total)}`}</p>
      {e.motivo ? <p className="mt-1 text-lg text-lacre">No entregada: {e.motivo} · {fechaHora(e.marcado_en)}</p> : null}

      <div className="mt-3"><Aviso error={marcar.error} grande onActualizar={() => { marcar.limpiar(); onCambio(); }} onCerrar={marcar.error?.tipo !== 'conflicto' ? marcar.limpiar : undefined} /></div>

      {pendiente && !fallo ? (
        <div className="mt-3 grid grid-cols-2 gap-3">
          <Boton tam="xl" variante="exito" cargando={marcar.cargando} onClick={() => confirmar(true, null)}>Entregada</Boton>
          <Boton tam="xl" variante="peligro" onClick={() => setFallo(true)}>No entregada</Boton>
        </div>
      ) : null}
      {pendiente && fallo ? (
        <div className="mt-3 space-y-2">
          <p className="text-xl font-bold">¿Qué pasó?</p>
          <div className="grid grid-cols-2 gap-2">
            {MOTIVOS_NO_ENTREGA.filter((m) => m !== 'Otro').map((m) => (
              <Boton key={m} tam="lg" variante="secundario" cargando={marcar.cargando} onClick={() => confirmar(false, m)}>{m}</Boton>
            ))}
          </div>
          <div className="flex gap-2">
            <input value={otro} onChange={(x) => setOtro(x.target.value)} placeholder="Otro motivo" className="h-14 flex-1 rounded-lg border-4 border-carbon px-3 text-lg" />
            <Boton tam="lg" variante="peligro" disabled={!otro.trim()} cargando={marcar.cargando} onClick={() => confirmar(false, otro.trim())}>OK</Boton>
          </div>
          <Boton variante="fantasma" onClick={() => setFallo(false)}>Volver</Boton>
        </div>
      ) : null}

      {resultado && resultado.resultado === 'No entregada' ? (
        <p className="mt-3 rounded-lg bg-lacre-50 p-3 text-lg text-lacre-700">
          {resultado.retiro_en_biblioteca ? 'Segunda vez sin entregar: queda para retirar en la biblioteca (15 días).'
            : proximo ? `Queda para el recorrido del ${proximo}.` : 'No hay lugar en los próximos recorridos: la biblioteca lo reprograma.'}
        </p>
      ) : null}

      <div className="mt-3 flex flex-wrap gap-2">
        {pendiente ? <BotonWhatsApp tam="lg" telefono={e.telefono} texto={textos.enCamino(e, dia)}>Avisar que voy</BotonWhatsApp> : null}
        {resultado?.resultado === 'No entregada' || (!pendiente && e.resultado === 'No entregada') ? (
          <BotonWhatsApp tam="lg" telefono={e.telefono} texto={textos.noEntregado(e, resultado?.retiro_en_biblioteca ? null : proximo || (e.estado_pedido === 'Retiro en biblioteca' ? null : 'próximo recorrido'))}>
            Avisar que no se pudo
          </BotonWhatsApp>
        ) : null}
      </div>
    </li>
  );
}

export default function Hoja() {
  const { id } = useParams();
  const enPanel = useLocation().pathname.startsWith('/panel');
  const hoja = useDatos(() => rpc('hoja_recorrido', { p_recorrido: Number(id) }), [id]);
  const iniciar = useAccion(() => rpc('iniciar_recorrido', { p_recorrido: Number(id) }));
  if (hoja.cargando && !hoja.datos) return <Cargando />;
  if (hoja.error) return <Aviso error={hoja.error} grande />;
  const r = hoja.datos;
  const pend = r.entregas.filter((e) => e.resultado === 'Pendiente');
  const dia = `${diaSemana(r.fecha)} ${fecha(r.fecha)}`;
  return (
    <div className="space-y-4 text-carbon">
      <Link to={enPanel ? '/panel/reparto' : '/reparto'} className="text-lg underline">← {enPanel ? 'Reparto' : 'Mis recorridos'}</Link>
      <header className="rounded-xl bg-carbon p-4 text-papel">
        <p className="text-sm font-bold uppercase tracking-widest text-mostaza">Zona {r.zona} · {r.estado}</p>
        <h1 className="font-titulo text-3xl font-bold first-letter:uppercase">{dia}</h1>
        <p className="text-lg">{hora(r.hora_inicio)} a {hora(r.hora_fin)} · {r.entregas.length} entregas · {pend.length} pendientes{r.repartidor ? ` · ${r.repartidor}` : ''}</p>
      </header>
      {r.estado === 'Programado' && pend.length ? (
        <Boton tam="xl" className="w-full" cargando={iniciar.cargando} onClick={async () => { if ((await iniciar.ejecutar()) !== undefined) hoja.recargar(); }}>Salgo a repartir</Boton>
      ) : null}
      <Aviso error={iniciar.error} grande />
      <ol className="space-y-4">{r.entregas.map((e) => <Entrega key={e.id} e={e} dia={dia} onCambio={hoja.recargar} />)}</ol>
    </div>
  );
}
