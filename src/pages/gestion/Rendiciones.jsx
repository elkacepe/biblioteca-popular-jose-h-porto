import { useState } from 'react';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { descargarCSV } from '../../lib/csv.js';
import { fecha, fechaHora, plata } from '../../lib/formato.js';
import { useAuth } from '../../context/Auth.jsx';
import { AreaTexto, Aviso, Boton, Cargando, Pestanas, Tarjeta, Titulo, Vacio, cx, useAccion, useDatos } from '../../components/ui.jsx';

function Nota({ a, onCambio }) {
  const [texto, setTexto] = useState('');
  const [abierta, setAbierta] = useState(false);
  const acc = useAccion(() => rpc('nota_rendicion', { p_arqueo: a.id, p_nota: texto }));
  if (!abierta) return <button className="text-sm font-semibold text-tinta underline" onClick={() => setAbierta(true)}>Agregar nota</button>;
  return (
    <div className="mt-2 space-y-2">
      <AreaTexto rows={2} value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="La rendición está cerrada: la nota se agrega al pie." />
      {acc.error ? <p className="text-sm text-lacre">{acc.error.message}</p> : null}
      <div className="flex gap-2"><Boton tam="sm" disabled={!texto.trim()} cargando={acc.cargando} onClick={async () => { if ((await acc.ejecutar()) !== undefined) { setTexto(''); setAbierta(false); onCambio(); } }}>Guardar nota</Boton>
        <Boton tam="sm" variante="fantasma" onClick={() => setAbierta(false)}>Cancelar</Boton></div>
    </div>
  );
}

export default function Rendiciones() {
  const { rol } = useAuth();
  const [canal, setCanal] = useState('todos');
  const { datos, error, cargando, recargar } = useDatos(() => consulta(supabase.from('arqueos')
    .select('*, ferias(fecha, lugar), jornadas_mostrador(fecha), cerro:perfiles!arqueos_cerrado_por_fkey(nombre)').order('cerrado_en', { ascending: false })));
  const lista = (datos || []).filter((a) => canal === 'todos' || a.canal === canal);
  const nombre = (a) => (a.canal === 'feria' ? `Feria del ${fecha(a.ferias?.fecha, { year: 'numeric' })}` : `Mostrador ${fecha(a.jornadas_mostrador?.fecha, { year: 'numeric' })}`);
  const exportar = () => descargarCSV(`rendiciones-${canal}`, lista, [
    { titulo: 'Rendición', valor: nombre }, { titulo: 'Canal', clave: 'canal' }, { titulo: 'Ventas', clave: 'cantidad_ventas' },
    { titulo: 'Libros', clave: 'ejemplares_vendidos' }, { titulo: 'Efectivo esperado', clave: 'efectivo_esperado' },
    { titulo: 'Efectivo contado', clave: 'efectivo_contado' }, { titulo: 'Transferencias registradas', clave: 'transferencias_registradas' },
    { titulo: 'Transferencias informadas', clave: 'transferencias_informadas' }, { titulo: 'Diferencia', clave: 'diferencia' },
    { titulo: 'Motivo', clave: 'motivo_diferencia' }, { titulo: 'Volvieron al depósito', clave: 'ejemplares_devueltos' },
    { titulo: 'Cerró', valor: (a) => a.cerro?.nombre }, { titulo: 'Cerrada', valor: (a) => fechaHora(a.cerrado_en) }, { titulo: 'Nota', clave: 'nota_bibliotecaria' },
  ]);
  return (
    <div>
      <Titulo sub="Cada feria y cada jornada de mostrador se cierran con un arqueo. Una vez cerrada, la rendición no se modifica."
        accion={<Boton variante="secundario" onClick={exportar} disabled={!lista.length}>Descargar CSV</Boton>}>Rendiciones</Titulo>
      <Pestanas valor={canal} onCambio={setCanal} opciones={[{ valor: 'todos', etiqueta: 'Todas' }, { valor: 'feria', etiqueta: 'Ferias' }, { valor: 'mostrador', etiqueta: 'Mostrador' }]} />
      <Aviso error={error} />
      {cargando && !datos ? <Cargando /> : !lista.length ? <Vacio titulo="Todavía no hay rendiciones" /> : (
        <div className="grid gap-3 lg:grid-cols-2">
          {lista.map((a) => {
            const esperado = Number(a.efectivo_esperado) + Number(a.transferencias_registradas);
            const contado = Number(a.efectivo_contado) + Number(a.transferencias_informadas);
            return (
              <Tarjeta key={a.id} className="p-4">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <p className="font-titulo text-lg font-bold text-tinta">🔒 {nombre(a)}</p>
                    <p className="text-sm text-tinta/70">Cerró {a.cerro?.nombre || '—'} · {fechaHora(a.cerrado_en)} · {a.cantidad_ventas} ventas · {a.ejemplares_vendidos} libros</p>
                  </div>
                  <p className={cx('rounded px-2 py-1 font-titulo font-bold tabular-nums', Number(a.diferencia) ? 'bg-lacre text-papel' : 'bg-pino text-papel')}>{plata(a.diferencia)}</p>
                </div>
                <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
                  <dt className="text-tinta/70">Efectivo esperado / contado</dt><dd className="text-right tabular-nums">{plata(a.efectivo_esperado)} / {plata(a.efectivo_contado)}</dd>
                  <dt className="text-tinta/70">Transferencias registradas / informadas</dt><dd className="text-right tabular-nums">{plata(a.transferencias_registradas)} / {plata(a.transferencias_informadas)}</dd>
                  <dt className="font-semibold">Total esperado / contado</dt><dd className="text-right font-semibold tabular-nums">{plata(esperado)} / {plata(contado)}</dd>
                  {a.canal === 'feria' ? <><dt className="text-tinta/70">Volvieron al depósito</dt><dd className="text-right">{a.ejemplares_devueltos} libros</dd></> : null}
                </dl>
                {a.motivo_diferencia ? <p className="mt-2 text-sm"><b>Motivo:</b> {a.motivo_diferencia}</p> : null}
                {a.nota_bibliotecaria ? <p className="mt-2 whitespace-pre-line rounded bg-papel-300 p-2 text-sm">{a.nota_bibliotecaria}</p> : null}
                {rol === 'bibliotecaria' ? <div className="mt-2"><Nota a={a} onCambio={recargar} /></div> : null}
              </Tarjeta>
            );
          })}
        </div>
      )}
    </div>
  );
}
