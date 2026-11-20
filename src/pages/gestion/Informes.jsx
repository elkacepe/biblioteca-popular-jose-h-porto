import { useMemo, useState } from 'react';
import { rpc } from '../../lib/api.js';
import { descargarCSV } from '../../lib/csv.js';
import { fecha, fechaHora, hoyISO, plata } from '../../lib/formato.js';
import { Aviso, Boton, Campo, Cargando, Entrada, Estado, Pestanas, Selector, Tarjeta, Titulo, Vacio, useDatos } from '../../components/ui.jsx';

const CANALES = { web: 'Web', mostrador: 'Mostrador', feria: 'Feria' };
const SECCIONES = [
  { valor: 'recaudacion', etiqueta: 'Recaudación' }, { valor: 'movimientos', etiqueta: 'Movimientos' },
  { valor: 'vendidos', etiqueta: 'Más vendidos' }, { valor: 'devoluciones', etiqueta: 'Devoluciones' },
  { valor: 'fallidas', etiqueta: 'Entregas fallidas' }, { valor: 'antiguedad', etiqueta: '+180 días en depósito' },
];
const mesLargo = (m) => new Date(`${m}-15T12:00:00`).toLocaleDateString('es-AR', { month: 'long', year: 'numeric' });

function Barras({ filas }) {
  const max = Math.max(1, ...filas.map((f) => f.valor));
  return (
    <ul className="space-y-2">
      {filas.map((f) => (
        <li key={f.etiqueta}>
          <div className="mb-0.5 flex justify-between text-sm"><span className="inline-block first-letter:uppercase">{f.etiqueta}</span><span className="font-semibold tabular-nums">{plata(f.valor)}</span></div>
          <div className="h-3 rounded bg-papel-300"><div className="h-full rounded" style={{ width: `${(Math.max(f.valor, 0) / max) * 100}%`, background: f.color || '#21395B' }} /></div>
        </li>
      ))}
    </ul>
  );
}

function TablaCSV({ filas, columnas, nombre, vacio = 'No hay datos con estos filtros.' }) {
  if (!filas?.length) return <Vacio titulo={vacio} />;
  return (
    <div>
      <div className="mb-2 flex justify-between"><p className="text-sm text-tinta/70">{filas.length} filas</p>
        <Boton tam="sm" variante="secundario" onClick={() => descargarCSV(nombre, filas, columnas)}>Descargar CSV</Boton></div>
      <div className="overflow-x-auto">
        <table className="tabla">
          <thead><tr>{columnas.map((c) => <th key={c.titulo} className={c.num ? 'text-right' : ''}>{c.titulo}</th>)}</tr></thead>
          <tbody>{filas.map((f, i) => (
            <tr key={i}>{columnas.map((c) => {
              const v = typeof c.valor === 'function' ? c.valor(f) : f[c.clave];
              return <td key={c.titulo} className={c.num ? 'text-right tabular-nums' : ''}>{c.ver ? c.ver(f) : c.plata ? plata(v) : v}</td>;
            })}</tr>
          ))}</tbody>
        </table>
      </div>
    </div>
  );
}

export default function Informes() {
  const [seccion, setSeccion] = useState('recaudacion');
  const [desde, setDesde] = useState(`${hoyISO().slice(0, 4)}-01-01`);
  const [hasta, setHasta] = useState(hoyISO());
  const [canal, setCanal] = useState('');
  const [por, setPor] = useState('titulo');
  const [dias, setDias] = useState(180);
  const f = { p_desde: desde || null, p_hasta: hasta || null };
  const fc = { ...f, p_canal: canal || null };
  const sufijo = `${desde || 'inicio'}_${hasta || 'hoy'}${canal ? `_${canal}` : ''}`;

  const { datos, error, cargando } = useDatos(async () => {
    switch (seccion) {
      case 'recaudacion': return rpc('informe_recaudacion', fc);
      case 'movimientos': return rpc('informe_movimientos', fc);
      case 'vendidos': return rpc('informe_mas_vendidos', { ...fc, p_por: por });
      case 'devoluciones': return rpc('informe_devoluciones', fc);
      case 'fallidas': return rpc('informe_entregas_fallidas', f);
      default: return rpc('informe_antiguedad', { p_dias: Number(dias) || 180 });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seccion, desde, hasta, canal, por, dias]);

  const resumen = useMemo(() => {
    if (seccion !== 'recaudacion' || !datos) return null;
    const porCanal = {}; const porMes = {}; const porFeria = [];
    datos.forEach((r) => {
      porCanal[r.canal] = (porCanal[r.canal] || 0) + Number(r.neto);
      porMes[r.mes] = (porMes[r.mes] || { mes: r.mes, web: 0, mostrador: 0, feria: 0, total: 0 });
      porMes[r.mes][r.canal] += Number(r.neto); porMes[r.mes].total += Number(r.neto);
      if (r.feria_id) porFeria.push(r);
    });
    return { porCanal, porMes: Object.values(porMes).sort((a, b) => b.mes.localeCompare(a.mes)), porFeria, total: Object.values(porCanal).reduce((s, x) => s + x, 0) };
  }, [datos, seccion]);

  const colsRecaudacion = [
    { titulo: 'Mes', clave: 'mes' }, { titulo: 'Canal', valor: (r) => CANALES[r.canal] }, { titulo: 'Feria', clave: 'feria' },
    { titulo: 'Ventas', clave: 'ventas', num: true }, { titulo: 'Ingresos', clave: 'ingresos', num: true, plata: true },
    { titulo: 'Reintegros', clave: 'reintegros', num: true, plata: true }, { titulo: 'Neto', clave: 'neto', num: true, plata: true },
    { titulo: 'Efectivo', clave: 'efectivo', num: true, plata: true }, { titulo: 'Transferencias', clave: 'transferencias', num: true, plata: true },
  ];

  return (
    <div>
      <Titulo sub="Todo sale del libro de movimientos de dinero: lo que ves acá coincide con cada venta y cada reintegro registrados. El CSV respeta los filtros.">Informes</Titulo>
      <Tarjeta className="mb-4 grid gap-3 p-4 sm:grid-cols-4">
        <Campo etiqueta="Desde"><Entrada type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></Campo>
        <Campo etiqueta="Hasta"><Entrada type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} /></Campo>
        <Campo etiqueta="Canal"><Selector value={canal} onChange={(e) => setCanal(e.target.value)} disabled={['fallidas', 'antiguedad'].includes(seccion)}>
          <option value="">Todos</option>{Object.entries(CANALES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Selector></Campo>
        <div className="flex items-end"><Boton variante="fantasma" onClick={() => { setDesde(''); setHasta(''); setCanal(''); }}>Sin filtros</Boton></div>
      </Tarjeta>
      <Pestanas valor={seccion} onCambio={setSeccion} opciones={SECCIONES} />
      <Aviso error={error} />
      {cargando ? <Cargando texto="Haciendo las cuentas…" /> : null}

      {!cargando && seccion === 'recaudacion' && resumen ? (
        <div className="space-y-6">
          <div className="grid gap-4 md:grid-cols-2">
            <Tarjeta className="p-4">
              <p className="font-titulo text-lg font-bold text-tinta">Por canal · total {plata(resumen.total)}</p>
              <div className="mt-3"><Barras filas={['feria', 'mostrador', 'web'].map((c) => ({ etiqueta: CANALES[c], valor: resumen.porCanal[c] || 0, color: { feria: '#B23A32', mostrador: '#21395B', web: '#2F6B5E' }[c] }))} /></div>
            </Tarjeta>
            <Tarjeta className="p-4">
              <p className="font-titulo text-lg font-bold text-tinta">Por mes</p>
              <div className="mt-3"><Barras filas={resumen.porMes.slice(0, 6).map((m) => ({ etiqueta: mesLargo(m.mes), valor: m.total, color: '#E0A83B' }))} /></div>
            </Tarjeta>
          </div>
          <Tarjeta className="p-4">
            <p className="mb-2 font-titulo text-lg font-bold text-tinta">Por feria</p>
            {resumen.porFeria.length ? (
              <table className="tabla"><thead><tr><th>Feria</th><th className="text-right">Ventas</th><th className="text-right">Efectivo</th><th className="text-right">Transferencias</th><th className="text-right">Neto</th></tr></thead>
                <tbody>{resumen.porFeria.map((r) => <tr key={`${r.feria_id}-${r.mes}`}><td>{r.feria}</td><td className="text-right">{r.ventas}</td><td className="text-right tabular-nums">{plata(r.efectivo)}</td><td className="text-right tabular-nums">{plata(r.transferencias)}</td><td className="text-right font-semibold tabular-nums">{plata(r.neto)}</td></tr>)}</tbody></table>
            ) : <p className="text-tinta/70">No hubo ferias en el período.</p>}
          </Tarjeta>
          <TablaCSV filas={datos} columnas={colsRecaudacion} nombre={`recaudacion_${sufijo}`} />
        </div>
      ) : null}

      {!cargando && seccion === 'movimientos' ? (
        <>
          {datos?.length ? <p className="mb-2 font-titulo text-lg font-bold text-tinta">Saldo del período: {plata(datos.reduce((s, m) => s + Number(m.importe), 0))}</p> : null}
          <TablaCSV filas={datos} nombre={`movimientos_${sufijo}`} columnas={[
            { titulo: 'Fecha', valor: (m) => fechaHora(m.fecha) }, { titulo: 'Canal', valor: (m) => CANALES[m.canal] }, { titulo: 'Tipo', clave: 'tipo' },
            { titulo: 'Medio', clave: 'medio' }, { titulo: 'Importe', clave: 'importe', num: true, plata: true }, { titulo: 'Referencia', clave: 'referencia' }, { titulo: 'Usuario', clave: 'usuario' },
          ]} />
        </>
      ) : null}

      {!cargando && seccion === 'vendidos' ? (
        <>
          <Pestanas valor={por} onCambio={setPor} opciones={[{ valor: 'titulo', etiqueta: 'Por título' }, { valor: 'categoria', etiqueta: 'Por categoría' }]} />
          <TablaCSV filas={datos} nombre={`mas-vendidos-${por}_${sufijo}`} columnas={[
            { titulo: por === 'titulo' ? 'Título' : 'Categoría', clave: 'nombre' }, ...(por === 'titulo' ? [{ titulo: 'Categoría', clave: 'categoria' }] : []),
            { titulo: 'Ejemplares', clave: 'cantidad', num: true }, { titulo: 'Importe', clave: 'importe', num: true, plata: true },
          ]} />
        </>
      ) : null}

      {!cargando && seccion === 'devoluciones' ? (
        <TablaCSV filas={datos} nombre={`devoluciones_${sufijo}`} columnas={[
          { titulo: 'Motivo', clave: 'motivo' }, { titulo: 'Canal', valor: (r) => CANALES[r.canal] }, { titulo: 'Estado', clave: 'estado', ver: (r) => <Estado valor={r.estado} /> },
          { titulo: 'Cantidad', clave: 'cantidad', num: true }, { titulo: 'Reintegrado en efectivo', clave: 'reintegrado_efectivo', num: true, plata: true },
          { titulo: 'Reintegrado en crédito', clave: 'reintegrado_credito', num: true, plata: true },
        ]} />
      ) : null}

      {!cargando && seccion === 'fallidas' ? (
        <TablaCSV filas={datos} nombre={`entregas-fallidas_${desde || 'inicio'}_${hasta || 'hoy'}`} columnas={[
          { titulo: 'Fecha', valor: (r) => fecha(r.fecha, { year: 'numeric' }) }, { titulo: 'Zona', clave: 'zona' }, { titulo: 'Pedido', valor: (r) => `#${r.pedido}` },
          { titulo: 'Intento', clave: 'intento', num: true }, { titulo: 'Motivo', clave: 'motivo' }, { titulo: 'Repartidor', clave: 'repartidor' }, { titulo: 'Estado actual del pedido', clave: 'estado_actual' },
        ]} />
      ) : null}

      {!cargando && seccion === 'antiguedad' ? (
        <>
          <div className="mb-3 flex items-center gap-2"><span className="text-sm">Más de</span><Entrada type="number" className="w-24 py-1.5" value={dias} onChange={(e) => setDias(e.target.value)} /><span className="text-sm">días en depósito sin venderse</span></div>
          <TablaCSV filas={datos} nombre={`antiguedad-${dias}-dias`} vacio="No hay ejemplares tan viejos en el depósito" columnas={[
            { titulo: 'Código', clave: 'codigo' }, { titulo: 'Título', clave: 'titulo' }, { titulo: 'Categoría', clave: 'categoria' }, { titulo: 'Estado', clave: 'estado' },
            { titulo: 'Ubicación', clave: 'ubicacion' }, { titulo: 'Precio', clave: 'precio', num: true, plata: true }, { titulo: 'Días', clave: 'dias', num: true },
          ]} />
        </>
      ) : null}
    </div>
  );
}
