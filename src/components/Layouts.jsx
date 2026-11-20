import { useEffect, useState } from 'react';
import { Link, NavLink, Navigate, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { inicioDeRol, useAuth } from '../context/Auth.jsx';
import { useBolsa } from '../context/Bolsa.jsx';
import { supabase, configurado } from '../lib/supabase.js';
import { ROLES } from '../lib/reglas.js';
import { Cargando, cx } from './ui.jsx';

export function Membrete({ claro = false, compacto = false }) {
  return (
    <Link to="/" className="group flex items-center gap-3" aria-label="Biblioteca Popular José H. Porto, inicio">
      <svg viewBox="0 0 40 40" className={cx('shrink-0', compacto ? 'h-9 w-9' : 'h-11 w-11')} aria-hidden>
        <rect x="4" y="8" width="7" height="26" rx="1" fill={claro ? '#F4EBD9' : '#21395B'} />
        <rect x="13" y="11" width="6" height="23" rx="1" fill="#B23A32" />
        <rect x="22" y="6" width="7" height="28" rx="1" fill="#E0A83B" transform="rotate(9 25 20)" />
        <rect x="2" y="34" width="36" height="3" rx="1" fill={claro ? '#F4EBD9' : '#21395B'} />
      </svg>
      <span className="whitespace-nowrap leading-none">
        <span className={cx('block text-[11px] font-bold uppercase tracking-[0.22em]', claro ? 'text-mostaza' : 'text-lacre')}>Biblioteca Popular</span>
        <span className={cx('block font-titulo font-bold', compacto ? 'text-lg' : 'text-xl sm:text-2xl', claro ? 'text-papel' : 'text-tinta')}>José H. Porto</span>
      </span>
    </Link>
  );
}

function AvisoConfig() {
  if (configurado) return null;
  return (
    <div className="bg-lacre px-4 py-2 text-center text-sm font-semibold text-papel">
      Falta configurar Supabase: copiá <code>.env.example</code> como <code>.env.local</code> y completá la URL y la clave anon.
    </div>
  );
}

export function LayoutPublico() {
  const { perfil, rol, salir } = useAuth();
  const { items } = useBolsa();
  const nav = useNavigate();
  const link = ({ isActive }) => cx('rounded px-2 py-1 font-semibold', isActive ? 'text-lacre' : 'text-tinta hover:text-lacre');
  return (
    <div className="flex min-h-screen flex-col">
      <AvisoConfig />
      <header className="sticky top-0 z-30 border-b-4 border-double border-tinta/30 bg-papel/95 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3">
          <Membrete compacto />
          <nav className="flex items-center gap-1 text-sm sm:gap-3 sm:text-base">
            <NavLink to="/" end className={link}>Catálogo</NavLink>
            <NavLink to="/ferias" className={link}>Ferias</NavLink>
            <NavLink to="/bolsa" className={({ isActive }) => cx('relative rounded-md px-3 py-1.5 font-semibold', isActive ? 'bg-lacre text-papel' : 'bg-tinta text-papel')}>
              Bolsa{items.length ? <span className="ml-1.5 rounded-full bg-mostaza px-1.5 text-xs text-carbon">{items.length}</span> : null}
            </NavLink>
          </nav>
        </div>
        <div className="border-t border-tinta/10 bg-papel-100">
          <div className="mx-auto flex max-w-6xl items-center justify-end gap-3 px-4 py-1.5 text-sm">
            {perfil ? (
              <>
                <span className="truncate text-tinta/70">Hola, <b className="text-tinta">{perfil.nombre.split(' ')[0]}</b></span>
                {rol === 'comprador'
                  ? <Link to="/mis-pedidos" className="font-semibold text-tinta underline-offset-2 hover:underline">Mis pedidos</Link>
                  : <Link to={inicioDeRol(rol)} className="font-semibold text-tinta underline-offset-2 hover:underline">Ir a mi panel</Link>}
                <button onClick={async () => { await salir(); nav('/'); }} className="text-tinta/70 hover:text-lacre">Salir</button>
              </>
            ) : (
              <>
                <Link to="/ingresar" className="font-semibold text-tinta hover:text-lacre">Ingresar</Link>
                <Link to="/registro" className="text-tinta/70 hover:text-lacre">Crear cuenta</Link>
              </>
            )}
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6"><Outlet /></main>
      <footer className="mt-10 bg-tinta text-papel">
        <div className="mx-auto grid max-w-6xl gap-6 px-4 py-8 sm:grid-cols-3">
          <div><Membrete claro compacto /><p className="mt-3 text-sm text-papel/80">Más de 75 años en Villa Carlos Paz. Lo que juntamos con estos libros sostiene la biblioteca.</p></div>
          <div className="text-sm"><p className="font-titulo font-bold text-mostaza">Mostrador</p><p>Lunes a viernes de 8:30 a 12 y de 15 a 19</p></div>
          <div className="text-sm"><p className="font-titulo font-bold text-mostaza">Feria solidaria</p><p>Un domingo por mes, de 10 a 13, en la plazoleta del Reloj Cucú</p></div>
        </div>
      </footer>
    </div>
  );
}

export function RequiereRol({ roles, children }) {
  const { sesion, rol, cargando } = useAuth();
  const loc = useLocation();
  if (cargando) return <div className="mx-auto max-w-6xl px-4"><Cargando texto="Abriendo la biblioteca…" /></div>;
  if (!sesion) return <Navigate to="/ingresar" state={{ desde: loc.pathname }} replace />;
  if (!rol) return <div className="mx-auto max-w-6xl px-4"><Cargando texto="Buscando tu ficha…" /></div>;
  if (!roles.includes(rol)) return <Navigate to={inicioDeRol(rol)} replace />;
  return children;
}

const NAV_PANEL = {
  bibliotecaria: [
    ['/panel', 'Inicio'], ['/panel/donaciones', 'Donaciones'], ['/panel/deposito', 'Depósito'], ['/panel/pedidos', 'Pedidos'],
    ['/panel/ferias', 'Ferias'], ['/panel/mostrador', 'Mostrador'], ['/panel/reparto', 'Reparto'], ['/panel/devoluciones', 'Devoluciones'],
    ['/panel/rendiciones', 'Rendiciones'], ['/panel/informes', 'Informes'], ['/panel/ajustes', 'Ajustes'],
  ],
  comision: [['/panel', 'Tablero'], ['/panel/informes', 'Informes'], ['/panel/rendiciones', 'Rendiciones']],
};

export function useModoPrueba() {
  const [modo, setModo] = useState(false);
  useEffect(() => {
    supabase.from('config').select('permitir_fuera_de_horario').maybeSingle()
      .then(({ data }) => setModo(Boolean(data?.permitir_fuera_de_horario)));
  }, []);
  return modo;
}

export function LayoutPanel() {
  const { perfil, rol, salir } = useAuth();
  const nav = useNavigate();
  const modoPrueba = useModoPrueba();
  const items = NAV_PANEL[rol] || [];
  return (
    <div className="min-h-screen">
      <AvisoConfig />
      <header className="bg-tinta text-papel">
        <div className="mx-auto flex max-w-7xl items-center justify-between gap-3 px-4 py-3">
          <Membrete claro compacto />
          <div className="text-right text-sm leading-tight">
            <p className="font-semibold">{perfil?.nombre}</p>
            <p className="text-papel/70">{ROLES[rol]} · <button className="underline-offset-2 hover:underline" onClick={async () => { await salir(); nav('/'); }}>Salir</button></p>
          </div>
        </div>
        <nav className="mx-auto flex max-w-7xl gap-1 overflow-x-auto px-2 pb-2 sm:px-4" aria-label="Secciones del panel">
          {items.map(([to, txt]) => (
            <NavLink key={to} to={to} end={to === '/panel'}
              className={({ isActive }) => cx('whitespace-nowrap rounded-t-md px-3 py-2 text-sm font-semibold',
                isActive ? 'bg-papel text-tinta' : 'text-papel/85 hover:bg-tinta-700')}>
              {txt}
            </NavLink>
          ))}
          <NavLink to="/" className="ml-auto whitespace-nowrap px-3 py-2 text-sm text-papel/70 hover:text-papel">Ver catálogo ↗</NavLink>
        </nav>
      </header>
      {modoPrueba && rol === 'bibliotecaria' ? (
        <div className="bg-mostaza-50 px-4 py-1.5 text-center text-sm text-carbon">
          <b>Modo prueba:</b> se permite operar mostrador y feria fuera de horario. Se cambia en <Link className="underline" to="/panel/ajustes">Ajustes</Link>.
        </div>
      ) : null}
      <main className="mx-auto max-w-7xl px-4 py-6"><Outlet /></main>
    </div>
  );
}

/** Layout mínimo para quien opera desde el celular (caja y reparto): cero distracciones. */
export function LayoutCampo() {
  const { perfil, rol, salir } = useAuth();
  const nav = useNavigate();
  const esCaja = useLocation().pathname.startsWith('/caja');
  return (
    <div className="min-h-screen bg-papel">
      <AvisoConfig />
      <header className="flex items-center justify-between gap-3 bg-carbon px-4 py-3 text-papel">
        <Link to={esCaja ? '/caja' : '/reparto'} className="font-titulo text-lg font-bold">Porto · {esCaja ? 'Caja' : 'Reparto'}</Link>
        {rol === 'bibliotecaria' ? <Link to="/panel" className="text-sm text-papel/80 underline">Volver al panel</Link> : null}
        <div className="flex items-center gap-3 text-sm">
          <span className="hidden sm:inline">{perfil?.nombre}</span>
          <button onClick={async () => { await salir(); nav('/'); }} className="rounded border border-papel/40 px-3 py-1.5 font-semibold">Salir</button>
        </div>
      </header>
      <main className="mx-auto max-w-3xl px-3 py-4 sm:px-4"><Outlet /></main>
    </div>
  );
}
