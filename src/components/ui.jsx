import { forwardRef, useCallback, useEffect, useRef, useState } from 'react';
import { aAppError, nuevaClave } from '../lib/api.js';
import { plata } from '../lib/formato.js';
import { enlaceWhatsApp } from '../lib/whatsapp.js';

const cx = (...c) => c.filter(Boolean).join(' ');
export { cx };

const VARIANTES = {
  primario: 'bg-tinta text-papel hover:bg-tinta-700 active:bg-tinta-900',
  secundario: 'bg-papel-100 text-tinta ring-2 ring-inset ring-tinta hover:bg-papel-300',
  fantasma: 'text-tinta hover:bg-papel-300 underline-offset-4 hover:underline',
  peligro: 'bg-lacre text-papel hover:bg-lacre-700',
  exito: 'bg-pino text-papel hover:brightness-110',
  aviso: 'bg-mostaza text-carbon hover:brightness-105',
  negro: 'bg-carbon text-papel hover:bg-black',
};
const TAMANOS = {
  sm: 'min-h-9 px-3 text-sm',
  md: 'min-h-11 px-4 text-base',
  lg: 'min-h-14 px-5 text-lg',
  xl: 'min-h-[4.5rem] px-6 text-2xl',
};

export function Boton({ variante = 'primario', tam = 'md', cargando = false, className, children, disabled, ...props }) {
  return (
    <button
      className={cx('inline-flex items-center justify-center gap-2 rounded-md font-semibold transition select-none',
        'focus-visible:outline focus-visible:outline-4 focus-visible:outline-offset-2 focus-visible:outline-mostaza',
        'disabled:opacity-50 disabled:cursor-not-allowed', VARIANTES[variante], TAMANOS[tam], className)}
      disabled={disabled || cargando}
      {...props}
    >
      {cargando ? <span className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-r-transparent" aria-hidden /> : null}
      {children}
    </button>
  );
}

export function Campo({ etiqueta, ayuda, children, className }) {
  return (
    <label className={cx('block', className)}>
      <span className="mb-1 block text-sm font-semibold text-tinta">{etiqueta}</span>
      {children}
      {ayuda ? <span className="mt-1 block text-sm text-tinta/70">{ayuda}</span> : null}
    </label>
  );
}

const baseEntrada = 'rounded-md border-2 border-tinta/25 bg-papel-100 px-3 py-2.5 text-base text-carbon placeholder:text-tinta/40 focus:border-tinta focus:outline-none';
export const Entrada = forwardRef(function Entrada(props, ref) {
  return <input ref={ref} {...props} className={cx(baseEntrada, /(^|\s)w-/.test(props.className || '') ? '' : 'w-full', props.className)} />;
});
export const AreaTexto = (props) => <textarea rows={3} {...props} className={cx(baseEntrada, 'w-full', props.className)} />;
export const Selector = ({ children, ...props }) => (
  <select {...props} className={cx(baseEntrada, /(^|\s)w-/.test(props.className || '') ? '' : 'w-full', 'pr-8', props.className)}>{children}</select>
);

/** Etiqueta de categoría con forma de lomo de libro. */
export function Lomo({ nombre, color = '#21395B', className }) {
  return (
    <span
      className={cx('inline-flex items-center rounded-[3px] px-2 py-1 text-[11px] font-bold uppercase tracking-[0.12em] text-papel', className)}
      style={{ background: color, boxShadow: 'inset 0 3px 0 rgba(244,235,217,.35), inset 0 -3px 0 rgba(244,235,217,.35), inset 3px 0 0 rgba(0,0,0,.18)' }}
    >
      {nombre}
    </span>
  );
}

const COLOR_ESTADO = {
  // ejemplares
  'En clasificación': 'bg-papel-300 text-tinta',
  Acervo: 'bg-tinta text-papel',
  'En venta': 'bg-pino text-papel',
  Reservado: 'bg-mostaza text-carbon',
  'En feria': 'bg-lacre text-papel',
  Vendido: 'bg-carbon text-papel',
  'En devolución': 'bg-mostaza-50 text-carbon ring-1 ring-mostaza',
  Descartado: 'bg-papel-400 text-tinta line-through',
  // pedidos
  Nuevo: 'bg-papel-300 text-tinta', Cobrado: 'bg-tinta-100 text-tinta', Preparado: 'bg-tinta text-papel',
  'En reparto': 'bg-mostaza text-carbon', Entregado: 'bg-pino text-papel', 'Retiro en biblioteca': 'bg-lacre-50 text-lacre ring-1 ring-lacre',
  Retirado: 'bg-pino text-papel', Cancelado: 'bg-papel-400 text-tinta/70',
  // otros
  Planificada: 'bg-papel-300 text-tinta', Abierta: 'bg-pino text-papel', Cerrada: 'bg-carbon text-papel',
  Programado: 'bg-papel-300 text-tinta', 'En curso': 'bg-mostaza text-carbon', Finalizado: 'bg-carbon text-papel',
  Pendiente: 'bg-papel-300 text-tinta', Entregada: 'bg-pino text-papel', 'No entregada': 'bg-lacre text-papel',
  Solicitada: 'bg-mostaza text-carbon', 'En revisión': 'bg-tinta-100 text-tinta', Aprobada: 'bg-pino text-papel', Rechazada: 'bg-lacre text-papel',
  Recibido: 'bg-papel-300 text-tinta', Clasificado: 'bg-pino text-papel',
};

export function Estado({ valor, className }) {
  return (
    <span className={cx('inline-flex items-center whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-bold', COLOR_ESTADO[valor] || 'bg-papel-300 text-tinta', className)}>
      {valor}
    </span>
  );
}

/** Aviso en la misma pantalla que originó la acción. Para conflictos ofrece actualizar. */
export function Aviso({ error, exito, onActualizar, onCerrar, grande = false }) {
  const ref = useRef(null);
  useEffect(() => { if ((error || exito) && ref.current) ref.current.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }, [error, exito]);
  if (!error && !exito) return null;
  const estilo = exito ? 'border-pino bg-pino-50 text-pino'
    : error.tipo === 'conflicto' ? 'border-lacre bg-lacre-50 text-lacre-700'
    : error.tipo === 'red' ? 'border-carbon bg-papel-300 text-carbon'
    : 'border-mostaza bg-mostaza-50 text-carbon';
  const titulo = exito ? null : error.tipo === 'conflicto' ? 'Cambió algo mientras tanto' : error.tipo === 'permiso' ? 'Sin permiso' : error.tipo === 'red' ? 'Sin conexión' : 'No se pudo';
  return (
    <div ref={ref} role={error ? 'alert' : 'status'} className={cx('rounded-md border-l-8 p-4', estilo, grande ? 'text-xl' : 'text-base')}>
      {titulo ? <p className="font-titulo font-bold">{titulo}</p> : null}
      <p className={cx(exito && 'font-semibold')}>{exito || error.message}</p>
      {(onActualizar && error?.tipo === 'conflicto') || onCerrar ? (
        <div className="mt-3 flex flex-wrap gap-2">
          {onActualizar && error?.tipo === 'conflicto' ? <Boton tam={grande ? 'lg' : 'sm'} variante="peligro" onClick={onActualizar}>Actualizar datos</Boton> : null}
          {onCerrar ? <Boton tam={grande ? 'lg' : 'sm'} variante="fantasma" onClick={onCerrar}>Entendido</Boton> : null}
        </div>
      ) : null}
    </div>
  );
}

export function Tarjeta({ className, children, ...props }) {
  return <div className={cx('rounded-lg border border-tinta/15 bg-papel-100 shadow-papel', className)} {...props}>{children}</div>;
}

export function Titulo({ children, sub, accion }) {
  return (
    <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="font-titulo text-3xl font-bold leading-tight text-tinta sm:text-4xl">{children}</h1>
        {sub ? <p className="mt-1 text-tinta/75">{sub}</p> : null}
      </div>
      {accion}
    </div>
  );
}

export function Subtitulo({ children, className }) {
  return <h2 className={cx('font-titulo text-xl font-bold text-tinta', className)}>{children}</h2>;
}

export function Cargando({ texto = 'Buscando en los estantes…' }) {
  return (
    <div className="flex items-center gap-3 py-10 text-tinta/70" role="status">
      <span className="inline-block h-5 w-5 animate-spin rounded-full border-2 border-tinta border-r-transparent" aria-hidden />
      {texto}
    </div>
  );
}

export function Vacio({ titulo, texto, children }) {
  return (
    <div className="rounded-lg border-2 border-dashed border-tinta/25 px-6 py-10 text-center">
      <p className="font-titulo text-xl font-bold text-tinta">{titulo}</p>
      {texto ? <p className="mx-auto mt-1 max-w-md text-tinta/70">{texto}</p> : null}
      {children ? <div className="mt-4">{children}</div> : null}
    </div>
  );
}

export function Modal({ abierto, titulo, onCerrar, children, ancho = 'max-w-lg' }) {
  useEffect(() => {
    if (!abierto) return undefined;
    const esc = (e) => e.key === 'Escape' && onCerrar?.();
    window.addEventListener('keydown', esc);
    return () => window.removeEventListener('keydown', esc);
  }, [abierto, onCerrar]);
  if (!abierto) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-carbon/50 sm:items-center sm:p-4" onClick={onCerrar}>
      <div role="dialog" aria-modal="true" aria-label={titulo}
        className={cx('max-h-[92vh] w-full overflow-y-auto rounded-t-2xl bg-papel p-5 shadow-2xl sm:rounded-2xl', ancho)}
        onClick={(e) => e.stopPropagation()}>
        <div className="mb-4 flex items-start justify-between gap-4">
          <h2 className="font-titulo text-2xl font-bold text-tinta">{titulo}</h2>
          <button onClick={onCerrar} className="-m-2 rounded p-2 text-2xl leading-none text-tinta/60 hover:text-tinta" aria-label="Cerrar">×</button>
        </div>
        {children}
      </div>
    </div>
  );
}

export const Dinero = ({ valor, className }) => <span className={cx('tabular-nums', className)}>{plata(valor)}</span>;

export function IconoWhatsApp({ className = 'h-5 w-5' }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="currentColor" aria-hidden>
      <path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2Zm0 18.2a8.2 8.2 0 0 1-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2Zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8-.2-.1-.4-.1-.6.1l-.8 1c-.1.2-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.3-.4.3-.4.8-1.4.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.7 11.8 11.8 0 0 0 4.5 4c1.7.7 2.3.8 3.2.6.5-.1 1.5-.6 1.7-1.2.2-.6.2-1.1.2-1.2-.1-.1-.2-.2-.4-.3Z" />
    </svg>
  );
}

/** Abre WhatsApp con el texto armado. No envía nada por su cuenta. */
export function BotonWhatsApp({ texto, telefono, children = 'Avisar por WhatsApp', tam = 'md', className }) {
  return (
    <a href={enlaceWhatsApp(texto, telefono)} target="_blank" rel="noreferrer"
      className={cx('inline-flex items-center justify-center gap-2 rounded-md bg-pino font-semibold text-papel hover:brightness-110', TAMANOS[tam], className)}>
      <IconoWhatsApp /> {children}
    </a>
  );
}

/**
 * Ejecuta una acción contra la base con una clave de idempotencia estable mientras dure
 * el intento: un doble toque o un reintento por mala señal no duplica la operación.
 */
export function useAccion(fn) {
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState(null);
  const clave = useRef(nuevaClave());
  const ejecutar = useCallback(async (...args) => {
    setCargando(true); setError(null);
    try {
      const r = await fn(clave.current, ...args);
      clave.current = nuevaClave();
      return r;
    } catch (e) {
      const err = aAppError(e);
      if (err.tipo !== 'red') clave.current = nuevaClave();   // sin conexión: se reintenta con la misma clave
      setError(err);
      return undefined;
    } finally {
      setCargando(false);
    }
  }, [fn]);
  return { ejecutar, cargando, error, setError, limpiar: () => setError(null) };
}

/** Carga datos y expone recargar(). */
export function useDatos(cargar, deps = []) {
  const [datos, setDatos] = useState(null);
  const [error, setError] = useState(null);
  const [cargando, setCargando] = useState(true);
  const recargar = useCallback(async () => {
    setCargando(true); setError(null);
    try { setDatos(await cargar()); } catch (e) { setError(aAppError(e)); } finally { setCargando(false); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(() => { recargar(); }, [recargar]);
  return { datos, error, cargando, recargar, setDatos };
}

export function Pestanas({ opciones, valor, onCambio }) {
  return (
    <div className="-mx-4 mb-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:px-0">
      {opciones.map((o) => (
        <button key={o.valor} onClick={() => onCambio(o.valor)}
          className={cx('whitespace-nowrap rounded-full px-4 py-2 text-sm font-semibold transition',
            valor === o.valor ? 'bg-tinta text-papel' : 'bg-papel-100 text-tinta ring-1 ring-tinta/20 hover:bg-papel-300')}>
          {o.etiqueta}{o.n !== undefined ? <span className="ml-1.5 opacity-70">{o.n}</span> : null}
        </button>
      ))}
    </div>
  );
}

export function Dato({ etiqueta, children, className }) {
  return (
    <div className={className}>
      <dt className="text-xs font-semibold uppercase tracking-wider text-tinta/60">{etiqueta}</dt>
      <dd className="text-tinta">{children}</dd>
    </div>
  );
}
