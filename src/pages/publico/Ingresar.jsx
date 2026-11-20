import { useEffect, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { supabase } from '../../lib/supabase.js';
import { aAppError } from '../../lib/api.js';
import { inicioDeRol, useAuth } from '../../context/Auth.jsx';
import { Aviso, Boton, Campo, Entrada, Tarjeta } from '../../components/ui.jsx';

// Cuentas de la semilla (datos sintéticos). Se pueden ocultar con VITE_MOSTRAR_CUENTAS_PRUEBA=false.
const CUENTAS = [
  ['marta@porto.test', 'Bibliotecaria'], ['comision@porto.test', 'Comisión directiva'],
  ['norma@porto.test', 'Caja de feria'], ['ruben@porto.test', 'Caja de feria'], ['julia@porto.test', 'Caja de mostrador'],
  ['hugo@porto.test', 'Reparto (martes)'], ['carla@porto.test', 'Reparto (jueves)'],
  ['elena@porto.test', 'Socia al día'], ['tomas@porto.test', 'Socio con cuota vencida'], ['lucia@porto.test', 'Compradora, no socia'],
];
const CLAVE_PRUEBA = 'Porto2026!';
const MOSTRAR = import.meta.env.VITE_MOSTRAR_CUENTAS_PRUEBA !== 'false';

export default function Ingresar({ modo }) {
  const registro = modo === 'registro';
  const { sesion, rol } = useAuth();
  const nav = useNavigate();
  const loc = useLocation();
  const [email, setEmail] = useState('');
  const [clave, setClave] = useState('');
  const [nombre, setNombre] = useState('');
  const [error, setError] = useState(null);
  const [cargando, setCargando] = useState(false);

  useEffect(() => {
    if (sesion && rol) nav(loc.state?.desde && rol === 'comprador' ? loc.state.desde : inicioDeRol(rol), { replace: true });
  }, [sesion, rol, nav, loc.state]);

  async function enviar(e) {
    e.preventDefault();
    setCargando(true); setError(null);
    try {
      if (registro) {
        // El rol NO se manda: la base crea siempre la cuenta como «comprador».
        const { data, error: err } = await supabase.auth.signUp({ email, password: clave, options: { data: { nombre } } });
        if (err) throw err;
        if (!data.session) {
          setError({ tipo: 'regla', message: 'La cuenta se creó, pero el proyecto pide confirmar el correo. Desactivá «Confirm email» en Supabase (ver README) e ingresá.' });
        }
      } else {
        const { error: err } = await supabase.auth.signInWithPassword({ email, password: clave });
        if (err) throw err;
      }
    } catch (err) {
      const m = err.message || '';
      setError(/Invalid login/i.test(m) ? { tipo: 'regla', message: 'El correo o la contraseña no coinciden.' }
        : /already registered/i.test(m) ? { tipo: 'regla', message: 'Ya hay una cuenta con ese correo. Ingresá con tu contraseña.' }
        : /at least/i.test(m) ? { tipo: 'regla', message: 'La contraseña tiene que tener al menos 6 caracteres.' }
        : aAppError(err));
    } finally { setCargando(false); }
  }

  return (
    <div className="mx-auto grid max-w-4xl gap-6 md:grid-cols-2">
      <Tarjeta className="p-6">
        <h1 className="font-titulo text-3xl font-bold text-tinta">{registro ? 'Crear cuenta' : 'Ingresar'}</h1>
        <p className="mt-1 text-tinta/75">{registro ? 'Para reservar libros y seguir tus pedidos.' : 'Con tu correo y contraseña.'}</p>
        <form onSubmit={enviar} className="mt-5 space-y-4">
          {registro ? <Campo etiqueta="Nombre y apellido"><Entrada value={nombre} onChange={(e) => setNombre(e.target.value)} required autoComplete="name" /></Campo> : null}
          <Campo etiqueta="Correo"><Entrada type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="email" /></Campo>
          <Campo etiqueta="Contraseña" ayuda={registro ? 'Mínimo 6 caracteres.' : null}>
            <Entrada type="password" value={clave} onChange={(e) => setClave(e.target.value)} required minLength={6} autoComplete={registro ? 'new-password' : 'current-password'} />
          </Campo>
          <Aviso error={error} />
          <Boton type="submit" tam="lg" className="w-full" cargando={cargando}>{registro ? 'Crear mi cuenta' : 'Entrar'}</Boton>
        </form>
        <p className="mt-4 text-sm text-tinta/75">
          {registro ? <>¿Ya tenés cuenta? <Link className="font-semibold underline" to="/ingresar" state={loc.state}>Ingresá</Link></>
            : <>¿Primera vez? <Link className="font-semibold underline" to="/registro" state={loc.state}>Creá tu cuenta</Link></>}
        </p>
        <p className="mt-2 text-xs text-tinta/55">No hay recuperación de contraseña por correo: si te olvidaste, pedila en la biblioteca.</p>
      </Tarjeta>

      {MOSTRAR && !registro ? (
        <div>
          <p className="font-titulo text-xl font-bold text-tinta">Cuentas de prueba</p>
          <p className="mb-3 text-sm text-tinta/70">Datos sintéticos. Contraseña de todas: <code className="rounded bg-papel-300 px-1">{CLAVE_PRUEBA}</code>. Tocá una para completar.</p>
          <ul className="grid gap-2">
            {CUENTAS.map(([correo, papel]) => (
              <li key={correo}>
                <button type="button" onClick={() => { setEmail(correo); setClave(CLAVE_PRUEBA); }}
                  className="flex w-full items-center justify-between rounded-md bg-papel-100 px-3 py-2 text-left ring-1 ring-tinta/15 hover:ring-tinta">
                  <span className="font-semibold text-tinta">{correo}</span><span className="text-sm text-tinta/70">{papel}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  );
}
