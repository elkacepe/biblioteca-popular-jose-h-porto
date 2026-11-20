import { useParams } from 'react-router-dom';
import { rpc } from '../lib/api.js';
import { fechaHora, plata } from '../lib/formato.js';
import { Aviso, Boton, Cargando, useDatos } from '../components/ui.jsx';

export default function Ticket() {
  const { id } = useParams();
  const { datos: v, error, cargando } = useDatos(() => rpc('ticket_venta', { p_venta: Number(id) }), [id]);
  if (cargando) return <Cargando />;
  if (error) return <div className="p-4"><Aviso error={error} /></div>;
  return (
    <div className="mx-auto max-w-[80mm] bg-white p-4 font-mono text-[13px] leading-snug text-carbon print:max-w-none print:p-0">
      <div className="text-center">
        <p className="font-titulo text-[11px] font-bold uppercase tracking-[0.2em]">Biblioteca Popular</p>
        <p className="font-titulo text-xl font-bold">José H. Porto</p>
        <p>Villa Carlos Paz</p>
        <p className="mt-2">{v.canal === 'feria' ? 'Feria solidaria' : v.canal === 'web' ? 'Pedido web' : 'Mostrador'} · Venta #{v.numero}</p>
        <p>{fechaHora(v.created_at)}</p>
      </div>
      <hr className="my-2 border-dashed border-carbon" />
      {v.items.map((i) => (
        <div key={i.codigo} className="mb-1.5">
          <p className="font-bold">{i.titulo}</p>
          <div className="flex justify-between"><span>{i.codigo}</span>
            <span>{i.sin_cargo ? `${plata(i.precio)} → SIN CARGO` : Number(i.descuento) ? `${plata(i.precio)} −${plata(i.descuento)}` : plata(i.precio)}</span></div>
        </div>
      ))}
      <hr className="my-2 border-dashed border-carbon" />
      <div className="flex justify-between"><span>Subtotal</span><span>{plata(v.subtotal)}</span></div>
      {Number(v.descuento_socio) ? <div className="flex justify-between"><span>Socio/a 15 %</span><span>−{plata(v.descuento_socio)}</span></div> : null}
      {Number(v.descuento_promo) ? <div className="flex justify-between"><span>Promo 3 libros</span><span>−{plata(v.descuento_promo)}</span></div> : null}
      {Number(v.envio) ? <div className="flex justify-between"><span>Envío</span><span>{plata(v.envio)}</span></div> : null}
      {Number(v.credito_usado) ? <div className="flex justify-between"><span>Crédito</span><span>−{plata(v.credito_usado)}</span></div> : null}
      <div className="mt-1 flex justify-between text-base font-bold"><span>TOTAL</span><span>{plata(v.total)}</span></div>
      <p>Pago: {v.medio_pago}</p>
      {v.vendedor ? <p>Atendió: {v.vendedor}</p> : null}
      <hr className="my-2 border-dashed border-carbon" />
      <p className="text-center">Cambios y devoluciones: 7 días corridos con este ticket{v.canal === 'feria' ? ', solo por defectos no informados' : ''}.</p>
      <p className="mt-1 text-center font-bold">¡Gracias por bancar la biblioteca!</p>
      <p className="mt-1 text-center text-[11px]">Comprobante no fiscal</p>
      <div className="no-imprimir mt-4 flex justify-center"><Boton onClick={() => window.print()}>Imprimir</Boton></div>
    </div>
  );
}
