import { plata } from '../../lib/formato.js';
import { Boton, cx } from '../../components/ui.jsx';

/**
 * Bandeja de la venta que se está armando. Pensada para usar al sol:
 * letra grande, mucho contraste y dos botones de cobro enormes.
 */
export default function VentaEnCurso({ items, sinCargo = new Set(), descuentoSocio = 0, subtotal, total, nota, onQuitar, onCobrar, cargando, deshabilitado }) {
  if (!items.length) {
    return <p className="rounded-xl border-4 border-dashed border-carbon/25 p-6 text-center text-xl text-carbon/60">Tocá un libro para sumarlo a la venta</p>;
  }
  return (
    <section aria-label="Venta en curso" className="rounded-xl bg-white p-4 shadow-lg ring-4 ring-carbon">
      <ul className="divide-y divide-carbon/15">
        {items.map((it) => {
          const gratis = sinCargo.has(it.id);
          return (
            <li key={it.id} className="flex items-center gap-3 py-3">
              <div className="min-w-0 flex-1">
                <p className="truncate text-xl font-bold text-carbon">{it.titulo}</p>
                <p className="text-base text-carbon/70">{it.codigo}{it.caja ? ` · caja ${it.caja}` : ''}</p>
              </div>
              <p className={cx('text-xl font-bold tabular-nums', gratis && 'text-pino')}>
                {gratis ? <><span className="mr-2 text-base text-carbon/50 line-through">{plata(it.precio)}</span>¡GRATIS!</> : plata(it.precio)}
              </p>
              <button onClick={() => onQuitar(it.id)} className="flex h-12 w-12 items-center justify-center rounded-lg bg-papel text-3xl font-bold text-lacre ring-2 ring-lacre" aria-label={`Quitar ${it.titulo}`}>×</button>
            </li>
          );
        })}
      </ul>
      <div className="mt-2 space-y-1 border-t-4 border-carbon pt-3 text-xl">
        <div className="flex justify-between"><span>{items.length} {items.length === 1 ? 'libro' : 'libros'}</span><span className="tabular-nums">{plata(subtotal)}</span></div>
        {sinCargo.size ? <div className="flex justify-between font-bold text-pino"><span>Promo 3 libros ({sinCargo.size} sin cargo)</span><span className="tabular-nums">− {plata(subtotal - total - descuentoSocio)}</span></div> : null}
        {descuentoSocio ? <div className="flex justify-between font-bold text-pino"><span>Socio/a al día (15 %)</span><span className="tabular-nums">− {plata(descuentoSocio)}</span></div> : null}
        <div className="flex items-baseline justify-between pt-1"><span className="font-titulo text-2xl font-bold">COBRAR</span><span className="font-titulo text-5xl font-bold tabular-nums">{plata(total)}</span></div>
        {nota ? <p className="text-base text-carbon/70">{nota}</p> : null}
      </div>
      <div className="mt-4 grid grid-cols-2 gap-3">
        <Boton tam="xl" variante="negro" cargando={cargando} disabled={deshabilitado} onClick={() => onCobrar('efectivo')}>Efectivo</Boton>
        <Boton tam="xl" variante="primario" cargando={cargando} disabled={deshabilitado} onClick={() => onCobrar('transferencia')}>Transferencia</Boton>
      </div>
    </section>
  );
}
