import { useState } from 'react';
import { consulta, rpc } from '../../lib/api.js';
import { supabase } from '../../lib/supabase.js';
import { fecha, hoyISO, plata } from '../../lib/formato.js';
import { ROLES } from '../../lib/reglas.js';
import { Aviso, Boton, Cargando, Entrada, Modal, Tarjeta, Titulo, useAccion, useDatos } from '../../components/ui.jsx';

function FilaSocio({ p, onCambio }) {
  const [num, setNum] = useState(p.numero_socio || '');
  const [hasta, setHasta] = useState(p.cuota_al_dia_hasta || '');
  const acc = useAccion(() => rpc('actualizar_socio', { p_perfil: p.id, p_numero: num, p_cuota_hasta: hasta || null }));
  const alDia = p.numero_socio && p.cuota_al_dia_hasta >= hoyISO();
  return (
    <tr>
      <td><p className="font-semibold">{p.nombre}</p><p className="text-xs text-tinta/60">{p.email}</p></td>
      <td><Entrada value={num} onChange={(e) => setNum(e.target.value)} className="w-24 py-1.5" placeholder="—" aria-label="Número de socio" /></td>
      <td><Entrada type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="w-40 py-1.5" aria-label="Cuota al día hasta" /></td>
      <td className="text-sm">{p.numero_socio ? (alDia ? <span className="text-pino">al día</span> : <span className="text-lacre">vencida</span>) : '—'}</td>
      <td className="text-right tabular-nums">{Number(p.credito) ? plata(p.credito) : '—'}</td>
      <td><Boton tam="sm" variante="secundario" cargando={acc.cargando} onClick={async () => { if ((await acc.ejecutar()) !== undefined) onCambio(); }}>Guardar</Boton>
        {acc.error ? <p className="text-xs text-lacre">{acc.error.message}</p> : null}</td>
    </tr>
  );
}

export default function Ajustes() {
  const [confirmar, setConfirmar] = useState(false);
  const [aviso, setAviso] = useState(null);
  const d = useDatos(async () => {
    const [config, perfiles] = await Promise.all([
      consulta(supabase.from('config').select('*').single()),
      consulta(supabase.from('perfiles').select('*').order('rol').order('nombre')),
    ]);
    return { config, perfiles };
  });
  const modo = useAccion((_c, v) => rpc('configurar_modo_prueba', { p_permitir: v }));
  const reiniciar = useAccion(() => rpc('reiniciar_demo'));

  if (d.cargando && !d.datos) return <Cargando />;
  const { config, perfiles } = d.datos || {};
  return (
    <div className="space-y-6">
      <Titulo sub="Parámetros de prueba de la demo. Los cambios de reglas de negocio se hacen en la base (ver README).">Ajustes</Titulo>
      <Aviso error={d.error || modo.error || reiniciar.error} exito={aviso} onCerrar={() => setAviso(null)} />

      {config ? (
        <Tarjeta className="space-y-3 p-5">
          <p className="font-titulo text-xl font-bold text-tinta">Horarios</p>
          <p className="text-tinta/80">Mostrador: lunes a viernes de 8:30 a 12 y de 15 a 19. Feria: el domingo de la feria, de 10 a 13.</p>
          <label className="flex items-center gap-3 text-lg">
            <input type="checkbox" className="h-6 w-6 accent-tinta" checked={config.permitir_fuera_de_horario}
              onChange={async (e) => { if ((await modo.ejecutar(e.target.checked)) !== undefined) { d.recargar(); setAviso(e.target.checked ? 'Modo prueba activado.' : 'Ahora se respetan los horarios.'); } }} />
            Modo prueba: permitir vender fuera de horario
          </label>
          <p className="text-sm text-tinta/60">
            Parámetros: socio {config.descuento_socio_pct} % · envío {plata(config.costo_envio)} (sin cargo para socios desde {config.envio_gratis_socio_desde} libros) ·
            reserva {config.horas_reserva_web} h · devolución {config.dias_devolucion} días · retiro {config.dias_retiro} días · caja {config.cupo_caja_feria} libros ·
            {config.max_cajas_feria} cajas por feria · recorrido {config.cupo_recorrido} lugares.
          </p>
        </Tarjeta>
      ) : null}

      <Tarjeta className="p-5">
        <p className="mb-1 font-titulo text-xl font-bold text-tinta">Socios y cuentas</p>
        <p className="mb-3 text-sm text-tinta/70">El rol de cada cuenta se asigna en la base, nunca desde un formulario. Acá solo se carga el número de socio y hasta cuándo está paga la cuota.</p>
        <div className="overflow-x-auto">
          <table className="tabla">
            <thead><tr><th>Persona</th><th>N.º socio</th><th>Cuota paga hasta</th><th>Estado</th><th className="text-right">Crédito</th><th /></tr></thead>
            <tbody>
              {perfiles?.filter((p) => p.rol === 'comprador').map((p) => <FilaSocio key={p.id} p={p} onCambio={d.recargar} />)}
            </tbody>
          </table>
        </div>
        <details className="mt-4 text-sm">
          <summary className="cursor-pointer font-semibold text-tinta">Equipo de la biblioteca ({perfiles?.filter((p) => p.rol !== 'comprador').length})</summary>
          <ul className="mt-2 grid gap-1 sm:grid-cols-2">{perfiles?.filter((p) => p.rol !== 'comprador').map((p) => <li key={p.id}>{p.nombre} · <span className="text-tinta/60">{ROLES[p.rol]} · {p.email}</span></li>)}</ul>
        </details>
      </Tarjeta>

      <Tarjeta className="border-lacre p-5">
        <p className="font-titulo text-xl font-bold text-lacre">Reiniciar los datos de prueba</p>
        <p className="mt-1 text-tinta/80">Borra donaciones, ejemplares, pedidos, ferias, ventas y rendiciones, y vuelve a cargar la demo con fechas relativas a hoy ({fecha(hoyISO(), { year: 'numeric' })}). Las cuentas de acceso no se tocan.</p>
        <Boton className="mt-3" variante="peligro" onClick={() => setConfirmar(true)}>Reiniciar datos</Boton>
      </Tarjeta>
      <Modal abierto={confirmar} titulo="¿Reiniciar la demo?" onCerrar={() => setConfirmar(false)}>
        <p className="mb-4 text-tinta/80">Se pierde todo lo cargado desde el último reinicio. No se puede deshacer.</p>
        <div className="flex gap-2">
          <Boton variante="peligro" cargando={reiniciar.cargando} onClick={async () => { if (await reiniciar.ejecutar()) { setConfirmar(false); setAviso('Listo: la demo volvió a su estado inicial.'); d.recargar(); } }}>Sí, reiniciar</Boton>
          <Boton variante="fantasma" onClick={() => setConfirmar(false)}>Cancelar</Boton>
        </div>
      </Modal>
    </div>
  );
}
