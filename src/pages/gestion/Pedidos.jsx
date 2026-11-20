import { useState } from 'react';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, faltan, fecha, fechaHora, plata } from '../../lib/formato.js';
import { textos } from '../../lib/whatsapp.js';
import { Aviso, Boton, BotonWhatsApp, Cargando, Estado, Pestanas, Tarjeta, Titulo, Vacio, useAccion, useDatos } from '../../components/ui.jsx';

const GRUPOS = [
  { valor: 'cobrar', etiqueta: 'Por cobrar', estados: ['Reservado'] },
  { valor: 'preparar', etiqueta: 'Para preparar', estados: ['Cobrado'] },
  { valor: 'reparto', etiqueta: 'Preparados y en reparto', estados: ['Preparado', 'En reparto'] },
  { valor: 'retiro', etiqueta: 'Para retirar', estados: ['Retiro en biblioteca'] },
  { valor: 'cerrados', etiqueta: 'Cerrados', estados: ['Entregado', 'Retirado', 'Cancelado'] },
];

function TarjetaPedido({ p, onCambio }) {
  const listo = (msg) => (r) => { if (r !== undefined) onCambio(`#${p.numero}: ${typeof msg === 'function' ? msg(r) : msg}`); };
  const cobrar = useAccion((clave, medio) => rpc('registrar_cobro', { p_pedido: p.id, p_medio: medio, p_idem: clave }));
  const preparar = useAccion(() => rpc('marcar_preparado', { p_pedido: p.id }));
  const retirado = useAccion(() => rpc('marcar_retirado', { p_pedido: p.id }));
  const asignar = useAccion(() => rpc('asignar_recorrido_pendiente', { p_pedido: p.id }));
  const error = cobrar.error || preparar.error || retirado.error || asignar.error;
  const libros = p.pedido_items.length;
  const diasRetiro = p.retiro_desde ? 15 - Math.floor((Date.now() - new Date(p.retiro_desde)) / 864e5) : null;
  const sinRecorrido = p.modalidad === 'envio' && ['Cobrado', 'Preparado'].includes(p.estado) && !p.recorrido_id;

  return (
    <Tarjeta className="p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-titulo text-lg font-bold text-tinta">#{p.numero} · {p.contacto_nombre} {p.es_socio ? <span className="ml-1 rounded bg-pino px-1.5 text-xs text-papel">socio/a</span> : null}</p>
          <p className="text-sm text-tinta/70">{p.telefono} · {p.modalidad === 'envio' ? `Envío ${p.zonas?.nombre}: ${p.direccion}` : 'Retira en la biblioteca'}</p>
        </div>
        <div className="text-right"><Estado valor={p.estado} /><p className="mt-1 font-titulo text-lg font-bold tabular-nums">{plata(p.total)}</p></div>
      </div>
      <ul className="mt-2 text-sm text-tinta/85">
        {p.pedido_items.map((i) => <li key={i.ejemplar_id}>· {i.ejemplares?.titulos?.titulo} <span className="font-mono text-xs text-tinta/60">{i.ejemplares?.codigo} {i.ejemplares?.ubicaciones?.codigo ? `· ${i.ejemplares.ubicaciones.codigo}` : ''}</span></li>)}
      </ul>
      <p className="mt-1 text-xs text-tinta/60">
        Creado {fechaHora(p.created_at)}{Number(p.descuento_socio) ? ` · socio −${plata(p.descuento_socio)}` : ''}{p.modalidad === 'envio' ? ` · envío ${Number(p.envio) ? plata(p.envio) : 'sin cargo'}` : ''}
        {Number(p.credito_usado) ? ` · crédito −${plata(p.credito_usado)}` : ''}{p.intentos_fallidos ? ` · ${p.intentos_fallidos} entrega(s) fallida(s)` : ''}
      </p>
      {p.estado === 'Reservado' ? <p className="mt-2 text-sm font-semibold text-carbon">Reserva vence {fechaHora(p.reservado_hasta)} (faltan {faltan(p.reservado_hasta)})</p> : null}
      {p.recorridos?.fecha && ['Cobrado', 'Preparado', 'En reparto'].includes(p.estado) ? <p className="mt-2 text-sm">Recorrido: <b>{diaSemana(p.recorridos.fecha)} {fecha(p.recorridos.fecha)}</b></p> : null}
      {sinRecorrido ? <p className="mt-2 text-sm font-semibold text-lacre">Sin recorrido asignado (no había lugar).</p> : null}
      {diasRetiro !== null && p.estado === 'Retiro en biblioteca' ? <p className="mt-2 text-sm font-semibold text-lacre">Quedan {Math.max(diasRetiro, 0)} días para retirarlo; después se cancela y los libros vuelven a la venta.</p> : null}

      <div className="mt-3"><Aviso error={error} onActualizar={() => onCambio()} onCerrar={() => [cobrar, preparar, retirado, asignar].forEach((a) => a.limpiar())} /></div>

      <div className="mt-3 flex flex-wrap gap-2">
        {p.estado === 'Reservado' ? (
          <>
            <Boton tam="sm" variante="exito" cargando={cobrar.cargando} onClick={() => cobrar.ejecutar('efectivo').then(listo((r) => r.repetida ? 'Ya estaba cobrado.' : r.sin_recorrido ? 'Cobro registrado. No había lugar en los recorridos de la zona.' : r.recorrido_fecha ? `Cobro registrado. Va en el recorrido del ${fecha(r.recorrido_fecha)}.` : 'Cobro registrado.'))}>Cobró en efectivo</Boton>
            <Boton tam="sm" variante="exito" cargando={cobrar.cargando} onClick={() => cobrar.ejecutar('transferencia').then(listo((r) => r.recorrido_fecha ? `Transferencia registrada. Va en el recorrido del ${fecha(r.recorrido_fecha)}.` : 'Transferencia registrada.'))}>Llegó la transferencia</Boton>
          </>
        ) : null}
        {p.estado === 'Cobrado' ? <Boton tam="sm" cargando={preparar.cargando} onClick={() => preparar.ejecutar().then(listo(p.modalidad === 'retiro' ? 'Listo para retirar: avisale por WhatsApp.' : 'Paquete preparado.'))}>{p.modalidad === 'retiro' ? 'Listo para retirar' : 'Marcar preparado'}</Boton> : null}
        {sinRecorrido ? <Boton tam="sm" variante="secundario" cargando={asignar.cargando} onClick={() => asignar.ejecutar().then(listo('Asignado a un recorrido.'))}>Buscar lugar en un recorrido</Boton> : null}
        {p.estado === 'Retiro en biblioteca' ? (
          <>
            <Boton tam="sm" variante="exito" cargando={retirado.cargando} onClick={() => retirado.ejecutar().then(listo('Retirado. ¡Que lo disfrute!'))}>Lo retiró</Boton>
            <BotonWhatsApp tam="sm" telefono={p.telefono} texto={textos.listoRetiro({ contacto: p.contacto_nombre, numero: p.numero })} />
          </>
        ) : null}
        {p.estado === 'Reservado' ? <BotonWhatsApp tam="sm" telefono={p.telefono} texto={`¡Hola ${p.contacto_nombre}! Te escribimos de la Biblioteca Porto por tu pedido #${p.numero} (${libros} ${libros === 1 ? 'libro' : 'libros'}, ${plata(p.total)}). Te lo guardamos hasta el ${fechaHora(p.reservado_hasta)}. ¿Cómo querés pagarlo?`}>Coordinar pago</BotonWhatsApp> : null}
      </div>
    </Tarjeta>
  );
}

export default function Pedidos() {
  const [grupo, setGrupo] = useState('cobrar');
  const [aviso, setAviso] = useState(null);
  const { datos, error, cargando, recargar } = useDatos(async () => {
    await rpc('disponibilidad', { p_ids: [] });   // vence reservas de más de 48 h antes de listar
    return consulta(supabase.from('pedidos').select(`*, zonas!pedidos_zona_id_fkey(nombre), recorridos!pedidos_recorrido_id_fkey(fecha),
      pedido_items(ejemplar_id, precio_final, ejemplares(codigo, titulos(titulo), ubicaciones!ejemplares_ubicacion_id_fkey(codigo)))`)
      .order('created_at', { ascending: false }).limit(300));
  });
  const g = GRUPOS.find((x) => x.valor === grupo);
  const lista = (datos || []).filter((p) => g.estados.includes(p.estado));
  return (
    <div>
      <Titulo sub="Las reservas web duran 48 horas. Si no se registra el cobro, los libros vuelven solos a la venta.">Pedidos web</Titulo>
      <Pestanas valor={grupo} onCambio={setGrupo} opciones={GRUPOS.map((x) => ({ ...x, n: (datos || []).filter((p) => x.estados.includes(p.estado)).length }))} />
      <div className="mb-3 space-y-2"><Aviso error={error} /><Aviso exito={aviso} onCerrar={() => setAviso(null)} /></div>
      {cargando && !datos ? <Cargando /> : !lista.length ? <Vacio titulo="Nada por acá" texto="No hay pedidos en este estado." /> : (
        <div className="grid gap-3 lg:grid-cols-2">{lista.map((p) => <TarjetaPedido key={p.id} p={p} onCambio={(m) => { if (m) setAviso(m); recargar(); }} />)}</div>
      )}
    </div>
  );
}
