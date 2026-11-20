import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { rpc, consulta } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { diaSemana, fecha, fechaHora, hora, plata } from '../../lib/formato.js';
import { textos, WHATSAPP_BIBLIOTECA } from '../../lib/whatsapp.js';
import { useAuth } from '../../context/Auth.jsx';
import { useBolsa } from '../../context/Bolsa.jsx';
import { Aviso, Boton, BotonWhatsApp, Campo, Entrada, Lomo, Selector, Tarjeta, Titulo, Vacio, cx, useAccion } from '../../components/ui.jsx';

function OpcionEntrega({ activa, onClick, titulo, children }) {
  return (
    <button type="button" onClick={onClick} aria-pressed={activa}
      className={cx('rounded-md p-4 text-left ring-2 transition', activa ? 'bg-tinta text-papel ring-tinta' : 'bg-papel-100 text-tinta ring-tinta/20 hover:ring-tinta/50')}>
      <p className="font-titulo text-lg font-bold">{titulo}</p>
      <p className={cx('text-sm', activa ? 'text-papel/85' : 'text-tinta/70')}>{children}</p>
    </button>
  );
}

export default function Bolsa() {
  const { perfil, rol, recargarPerfil } = useAuth();
  const bolsa = useBolsa();
  const [noDisponibles, setNoDisponibles] = useState([]);
  const [zonas, setZonas] = useState([]);
  const [modalidad, setModalidad] = useState('retiro');
  const [zona, setZona] = useState('');
  const [direccion, setDireccion] = useState('');
  const [telefono, setTelefono] = useState('');
  const [contacto, setContacto] = useState('');
  const [cotizacion, setCotizacion] = useState(null);
  const [recorrido, setRecorrido] = useState(undefined);
  const [hecho, setHecho] = useState(null);

  useEffect(() => { consulta(supabase.from('zonas').select('*').order('id')).then(setZonas).catch(() => {}); }, []);
  useEffect(() => {
    if (!perfil) return;
    setContacto((c) => c || perfil.nombre || '');
    setTelefono((t) => t || perfil.telefono || '');
    setDireccion((d) => d || perfil.direccion || '');
    setZona((z) => z || (perfil.zona_id ? String(perfil.zona_id) : ''));
  }, [perfil]);

  const ids = bolsa.items.map((x) => x.id);
  const idsClave = ids.join(',');

  const verificar = useCallback(async () => {
    if (!ids.length) { setNoDisponibles([]); return; }
    const disp = await rpc('disponibilidad', { p_ids: ids });
    setNoDisponibles(disp.filter((d) => !d.disponible).map((d) => d.id).concat(ids.filter((i) => !disp.some((d) => d.id === i))));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [idsClave]);
  useEffect(() => { verificar().catch(() => {}); }, [verificar]);

  useEffect(() => {
    if (!perfil || rol !== 'comprador' || !ids.length) { setCotizacion(null); return; }
    rpc('cotizar_pedido', { p_ejemplares: ids, p_modalidad: modalidad }).then(setCotizacion).catch(() => setCotizacion(null));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [idsClave, modalidad, perfil, rol]);

  useEffect(() => {
    if (modalidad !== 'envio' || !zona) { setRecorrido(undefined); return; }
    rpc('proximo_recorrido', { p_zona: Number(zona) }).then((r) => setRecorrido(r[0] || null)).catch(() => setRecorrido(undefined));
  }, [modalidad, zona]);

  const confirmar = useAccion((clave) => rpc('crear_pedido', {
    p_ejemplares: ids.filter((i) => !noDisponibles.includes(i)), p_modalidad: modalidad,
    p_zona: modalidad === 'envio' ? Number(zona) : null, p_direccion: modalidad === 'envio' ? direccion : null,
    p_telefono: telefono, p_contacto: contacto, p_idem: clave,
  }));

  async function enviar(e) {
    e.preventDefault();
    const r = await confirmar.ejecutar();
    if (r) {
      window.scrollTo(0, 0);
      setHecho({ ...r, libros: bolsa.items.filter((x) => !noDisponibles.includes(x.id)).map((x) => x.titulo) });
      bolsa.vaciar();
      recargarPerfil();
    } else {
      verificar().catch(() => {});
    }
  }

  if (hecho) {
    return (
      <div className="mx-auto max-w-xl space-y-4">
        <Tarjeta className="p-6">
          <p className="sello text-pino">Reservado</p>
          <h1 className="mt-4 font-titulo text-3xl font-bold text-tinta">¡Listo! Te guardamos los libros</h1>
          <p className="mt-2 text-lg text-tinta/85">
            Pedido <b>#{hecho.numero}</b> por <b>{plata(hecho.total)}</b>. La reserva dura hasta el <b>{fechaHora(hecho.reservado_hasta)}</b>:
            si para entonces no registramos el pago, los libros vuelven a la venta.
          </p>
          <ul className="mt-3 list-inside list-disc text-tinta/80">{hecho.libros.map((t) => <li key={t}>{t}</li>)}</ul>
          <p className="mt-4 text-tinta/80">Escribinos para coordinar el pago (efectivo en la biblioteca o transferencia):</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <BotonWhatsApp tam="lg" telefono={WHATSAPP_BIBLIOTECA}
              texto={textos.reserva({ contacto, numero: hecho.numero, libros: hecho.libros.join(', '), total: plata(hecho.total) })}>
              Mandar aviso por WhatsApp
            </BotonWhatsApp>
            <Link to="/mis-pedidos"><Boton tam="lg" variante="secundario">Seguir mi pedido</Boton></Link>
          </div>
        </Tarjeta>
      </div>
    );
  }

  if (!bolsa.items.length) {
    return (
      <div className="mx-auto max-w-xl">
        <Titulo>Tu bolsa</Titulo>
        <Vacio titulo="Todavía no elegiste ningún libro" texto="Recorré los estantes y sumá los que te gusten.">
          <Link to="/"><Boton>Ir al catálogo</Boton></Link>
        </Vacio>
      </div>
    );
  }

  const disponibles = bolsa.items.filter((x) => !noDisponibles.includes(x.id));
  const subtotal = disponibles.reduce((s, x) => s + x.precio, 0);

  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_420px]">
      <section>
        <Titulo sub="Los libros no se apartan hasta que confirmás el pedido.">Tu bolsa</Titulo>
        {noDisponibles.length ? (
          <div className="mb-4">
            <Aviso error={{ tipo: 'conflicto', message: `${noDisponibles.length === 1 ? 'Un libro ya encontró dueño' : `${noDisponibles.length} libros ya encontraron dueño`} mientras lo pensabas (se vendió, se reservó o se fue a la feria).` }} />
            <Boton className="mt-2" tam="sm" variante="secundario" onClick={() => bolsa.quitarVarios(noDisponibles)}>Sacarlos de la bolsa</Boton>
          </div>
        ) : null}
        <ul className="space-y-3">
          {bolsa.items.map((x) => {
            const no = noDisponibles.includes(x.id);
            return (
              <li key={x.id} className={cx('flex items-center gap-3 rounded-md bg-papel-100 p-3 ring-1 ring-tinta/10', no && 'opacity-60')}>
                <div className="h-14 w-2 rounded-sm" style={{ background: x.categoria_color }} aria-hidden />
                <div className="min-w-0 flex-1">
                  <p className={cx('font-titulo font-bold text-tinta', no && 'line-through')}>{x.titulo}</p>
                  <p className="text-sm text-tinta/70">{x.autor} · {x.estado_fisico} · {x.codigo}</p>
                  {no ? <p className="text-sm font-semibold text-lacre">Este libro ya encontró dueño</p> : <Lomo nombre={x.categoria} color={x.categoria_color} className="mt-1" />}
                </div>
                <div className="text-right">
                  <p className="font-semibold tabular-nums">{plata(x.precio)}</p>
                  <button onClick={() => bolsa.quitar(x.id)} className="text-sm text-tinta/60 hover:text-lacre">Quitar</button>
                </div>
              </li>
            );
          })}
        </ul>
      </section>

      <aside className="lg:pt-16">
        <Tarjeta className="p-5">
          {!perfil ? (
            <div className="space-y-3">
              <p className="font-titulo text-xl font-bold text-tinta">Para reservar, ingresá con tu cuenta</p>
              <p className="text-tinta/75">Así podés seguir el pedido. Si sos socio o socia con la cuota al día, el descuento del 15 % se aplica solo.</p>
              <div className="flex gap-2">
                <Link to="/ingresar" state={{ desde: '/bolsa' }}><Boton>Ingresar</Boton></Link>
                <Link to="/registro" state={{ desde: '/bolsa' }}><Boton variante="secundario">Crear cuenta</Boton></Link>
              </div>
            </div>
          ) : rol !== 'comprador' ? (
            <p className="text-tinta/80">Estás con una cuenta del equipo de la biblioteca. Para comprar por la web, ingresá con una cuenta de comprador.</p>
          ) : (
            <form onSubmit={enviar} className="space-y-4">
              <p className="font-titulo text-xl font-bold text-tinta">¿Cómo te lo llevás?</p>
              <div className="grid grid-cols-2 gap-2">
                <OpcionEntrega activa={modalidad === 'retiro'} onClick={() => setModalidad('retiro')} titulo="Retiro">En la biblioteca, sin cargo</OpcionEntrega>
                <OpcionEntrega activa={modalidad === 'envio'} onClick={() => setModalidad('envio')} titulo="Envío">{plata(1800)} · sin cargo para socios con 4 libros o más</OpcionEntrega>
              </div>
              {modalidad === 'envio' ? (
                <>
                  <Campo etiqueta="Zona">
                    <Selector value={zona} onChange={(e) => setZona(e.target.value)} required>
                      <option value="">Elegí tu zona</option>
                      {zonas.map((z) => <option key={z.id} value={z.id}>{z.nombre} · {z.dia_semana === 2 ? 'martes' : 'jueves'} de {hora(z.hora_inicio)} a {hora(z.hora_fin)}</option>)}
                    </Selector>
                  </Campo>
                  {recorrido ? (
                    <p className="rounded bg-mostaza-50 px-3 py-2 text-sm text-carbon">
                      {recorrido.cupo_disponible === 1 ? 'Queda 1 lugar' : `Quedan ${recorrido.cupo_disponible} lugares`} en el recorrido del <b>{diaSemana(recorrido.fecha)} {fecha(recorrido.fecha)}</b>.
                      Los pedidos para ese día cierran el {diaSemana(recorrido.cierre.slice(0, 10))} a las 12. Te asignamos lugar cuando registramos el pago.
                    </p>
                  ) : recorrido === null ? (
                    <p className="rounded bg-lacre-50 px-3 py-2 text-sm text-lacre-700">Los recorridos de las próximas dos semanas para esta zona están completos. Podés elegir retiro en la biblioteca.</p>
                  ) : null}
                  <Campo etiqueta="Dirección"><Entrada value={direccion} onChange={(e) => setDireccion(e.target.value)} required placeholder="Calle, número, piso" /></Campo>
                </>
              ) : null}
              <div className="grid grid-cols-2 gap-3">
                <Campo etiqueta="Nombre"><Entrada value={contacto} onChange={(e) => setContacto(e.target.value)} required /></Campo>
                <Campo etiqueta="Teléfono"><Entrada value={telefono} onChange={(e) => setTelefono(e.target.value)} inputMode="tel" required /></Campo>
              </div>

              <dl className="space-y-1 border-t border-dashed border-tinta/25 pt-3 text-tinta">
                <div className="flex justify-between"><dt>{disponibles.length} {disponibles.length === 1 ? 'libro' : 'libros'}</dt><dd className="tabular-nums">{plata(cotizacion?.subtotal ?? subtotal)}</dd></div>
                {Number(cotizacion?.descuento_socio) > 0 ? <div className="flex justify-between text-pino"><dt>Descuento de socio (15 %)</dt><dd className="tabular-nums">− {plata(cotizacion.descuento_socio)}</dd></div> : null}
                {modalidad === 'envio' ? <div className="flex justify-between"><dt>Envío</dt><dd className="tabular-nums">{Number(cotizacion?.envio) === 0 ? 'sin cargo' : plata(cotizacion?.envio ?? 1800)}</dd></div> : null}
                {Number(cotizacion?.credito) > 0 ? <div className="flex justify-between text-pino"><dt>Crédito a favor</dt><dd className="tabular-nums">− {plata(cotizacion.credito)}</dd></div> : null}
                <div className="flex justify-between border-t border-tinta/20 pt-2 font-titulo text-2xl font-bold"><dt>Total</dt><dd className="tabular-nums">{plata(cotizacion?.total ?? subtotal)}</dd></div>
              </dl>
              {cotizacion && !cotizacion.es_socio ? <p className="text-xs text-tinta/60">Si sos socio o socia, avisá en la biblioteca para que carguen tu número: con la cuota al día tenés 15 % menos.</p> : null}

              <Aviso error={confirmar.error} onActualizar={() => { confirmar.limpiar(); verificar(); }} />
              <Boton type="submit" tam="lg" className="w-full" cargando={confirmar.cargando} disabled={!disponibles.length}>
                Reservar por 48 horas
              </Boton>
              <p className="text-center text-xs text-tinta/60">Sin pago en línea: coordinás el pago con la biblioteca.</p>
            </form>
          )}
        </Tarjeta>
      </aside>
    </div>
  );
}
