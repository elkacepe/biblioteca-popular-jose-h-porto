import { useState } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { fecha, plata } from '../../lib/formato.js';
import { Aviso, Boton, BotonWhatsApp, Cargando, useAccion, useDatos } from '../../components/ui.jsx';

function Fila({ etiqueta, valor, fuerte, tono }) {
  return (
    <div className={`flex items-baseline justify-between py-2 ${fuerte ? 'border-t-4 border-carbon text-2xl font-bold' : 'text-xl'}`}>
      <span>{etiqueta}</span><span className={`tabular-nums ${tono || ''}`}>{valor}</span>
    </div>
  );
}

export default function Cierre() {
  const { id, jornada } = useParams();
  const loc = useLocation();
  const esFeria = Boolean(id);
  const enPanel = loc.pathname.startsWith('/panel');
  const [contado, setContado] = useState('');
  const [transfer, setTransfer] = useState('');
  const [motivo, setMotivo] = useState('');
  const [rendicion, setRendicion] = useState(null);

  const base = useDatos(async () => {
    const [resumen, cabecera] = await Promise.all([
      rpc('resumen_caja', esFeria ? { p_feria: Number(id) } : { p_jornada: Number(jornada) }),
      esFeria ? consulta(supabase.from('ferias').select('*').eq('id', id).maybeSingle())
        : consulta(supabase.from('jornadas_mostrador').select('*').eq('id', jornada).maybeSingle()),
    ]);
    return { resumen, cabecera };
  }, [id, jornada]);

  const cerrar = useAccion((clave) => rpc(esFeria ? 'cerrar_feria' : 'cerrar_jornada', {
    ...(esFeria ? { p_feria: Number(id) } : { p_jornada: Number(jornada) }),
    p_efectivo_contado: Number(contado || 0), p_transferencias: Number(transfer || 0), p_motivo: motivo || null, p_idem: clave,
  }));

  if (base.cargando && !base.datos) return <Cargando />;
  if (base.error) return <Aviso error={base.error} grande />;
  const { resumen, cabecera } = base.datos;
  const esperado = Number(resumen.efectivo) + Number(resumen.transferencias);
  const diferencia = contado === '' ? null : Number(contado || 0) + Number(transfer || 0) - esperado;
  const titulo = esFeria ? `Feria del ${fecha(cabecera?.fecha)}` : `Mostrador del ${fecha(cabecera?.fecha)}`;
  const volver = esFeria ? (enPanel ? `/panel/ferias/${id}` : `/caja/feria/${id}`) : (enPanel ? '/panel/mostrador' : '/caja/mostrador');

  if (rendicion || cabecera?.estado === 'Cerrada') {
    const r = rendicion;
    const texto = r ? `Rendición ${titulo} · Biblioteca Porto\nVentas: ${resumen.ventas} (${resumen.ejemplares} libros)\nEsperado: ${plata(Number(r.efectivo_esperado) + Number(r.transferencias_registradas))}\n` +
      `Contado: ${plata(Number(contado) + Number(transfer))} (efectivo ${plata(contado)}, transferencias ${plata(transfer)})\nDiferencia: ${plata(r.diferencia)}${motivo ? ` — ${motivo}` : ''}` +
      (esFeria ? `\nVolvieron al depósito: ${r.ejemplares_devueltos} libros` : '') : '';
    return (
      <div className="space-y-4 text-carbon">
        <div className="rounded-xl bg-pino p-5 text-papel">
          <p className="font-titulo text-3xl font-bold">Caja cerrada 🔒</p>
          <p className="text-xl">{titulo}. La rendición quedó lista para la comisión directiva{r?.repetida ? ' (ya estaba cerrada)' : ''}.</p>
        </div>
        {r ? (
          <div className="rounded-xl bg-white p-4 ring-4 ring-carbon">
            <Fila etiqueta="Esperado" valor={plata(Number(r.efectivo_esperado) + Number(r.transferencias_registradas))} />
            <Fila etiqueta="Contado" valor={plata(Number(contado) + Number(transfer))} />
            <Fila etiqueta="Diferencia" valor={plata(r.diferencia)} fuerte tono={Number(r.diferencia) ? 'text-lacre' : 'text-pino'} />
            {esFeria ? <p className="mt-2 text-xl"><b>{r.ejemplares_devueltos}</b> libros sin vender volvieron a su estante en el depósito.</p> : null}
          </div>
        ) : <p className="text-xl">Esta caja ya se cerró. Solo la bibliotecaria puede agregarle una nota.</p>}
        {r ? <BotonWhatsApp tam="lg" className="w-full" texto={texto}>Mandar la rendición por WhatsApp</BotonWhatsApp> : null}
        <Link to={enPanel ? '/panel/rendiciones' : '/caja'} className="block rounded-xl bg-papel-300 p-4 text-center text-xl font-bold ring-2 ring-carbon">Listo</Link>
      </div>
    );
  }

  return (
    <div className="space-y-4 text-carbon">
      <Link to={volver} className="text-lg underline">← Volver a la caja</Link>
      <h1 className="font-titulo text-3xl font-bold">Arqueo · {titulo}</h1>
      <div className="rounded-xl bg-white p-4 ring-2 ring-carbon/30">
        <Fila etiqueta={`${resumen.ventas} ventas · ${resumen.ejemplares} libros`} valor="" />
        <Fila etiqueta="Efectivo esperado" valor={plata(resumen.efectivo)} />
        <Fila etiqueta="Transferencias registradas" valor={plata(resumen.transferencias)} />
        <Fila etiqueta="Total esperado" valor={plata(esperado)} fuerte />
        {esFeria ? <p className="text-lg text-carbon/75">{resumen.sin_vender} libros sin vender van a volver solos a su estante.</p> : null}
      </div>

      <label className="block">
        <span className="mb-1 block text-xl font-bold">Efectivo contado</span>
        <input inputMode="decimal" type="number" min="0" value={contado} onChange={(e) => setContado(e.target.value)} placeholder="0"
          className="h-16 w-full rounded-xl border-4 border-carbon bg-white px-4 text-3xl font-bold tabular-nums focus:outline-none focus:ring-4 focus:ring-mostaza" />
      </label>
      <label className="block">
        <span className="mb-1 block text-xl font-bold">Transferencias recibidas</span>
        <span className="mb-1 block text-base text-carbon/70">Sumá lo que ves en la cuenta de la biblioteca (registradas: {plata(resumen.transferencias)}).</span>
        <input inputMode="decimal" type="number" min="0" value={transfer} onChange={(e) => setTransfer(e.target.value)} placeholder="0"
          className="h-16 w-full rounded-xl border-4 border-carbon bg-white px-4 text-3xl font-bold tabular-nums focus:outline-none focus:ring-4 focus:ring-mostaza" />
      </label>

      {diferencia !== null ? (
        <div className={`rounded-xl p-4 text-2xl font-bold ${diferencia === 0 ? 'bg-pino text-papel' : 'bg-lacre text-papel'}`}>
          {diferencia === 0 ? 'Cierra justo. ¡Bien ahí!' : `Diferencia: ${plata(diferencia)}`}
        </div>
      ) : null}
      {diferencia ? (
        <label className="block">
          <span className="mb-1 block text-xl font-bold">¿Por qué no cierra?</span>
          <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2} placeholder="Faltó cambio, se dio mal un vuelto…"
            className="w-full rounded-xl border-4 border-carbon bg-white p-3 text-xl focus:outline-none focus:ring-4 focus:ring-mostaza" />
        </label>
      ) : null}

      <Aviso error={cerrar.error} grande onCerrar={cerrar.limpiar} />
      <Boton tam="xl" variante="peligro" className="w-full" cargando={cerrar.cargando} disabled={contado === ''}
        onClick={async () => { const r = await cerrar.ejecutar(); if (r) { if (r.repetida) base.recargar(); else setRendicion(r); } }}>
        Cerrar la caja
      </Boton>
      <p className="text-center text-base text-carbon/70">Después de cerrar, la rendición queda bloqueada. Solo la bibliotecaria puede agregarle una nota.</p>
    </div>
  );
}
