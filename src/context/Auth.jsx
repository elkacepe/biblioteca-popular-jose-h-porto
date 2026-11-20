import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase.js';

const Ctx = createContext(null);

export function AuthProvider({ children }) {
  const [sesion, setSesion] = useState(null);
  const [perfil, setPerfil] = useState(null);
  const [cargando, setCargando] = useState(true);

  const cargarPerfil = useCallback(async (s) => {
    if (!s?.user) { setPerfil(null); return; }
    const { data } = await supabase.from('perfiles').select('*').eq('id', s.user.id).maybeSingle();
    setPerfil(data);
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      setSesion(data.session);
      await cargarPerfil(data.session);
      setCargando(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_evento, s) => {
      setSesion(s);
      // Se difiere para no bloquear el callback de Supabase.
      setTimeout(() => cargarPerfil(s), 0);
    });
    return () => sub.subscription.unsubscribe();
  }, [cargarPerfil]);

  const valor = {
    sesion, perfil, cargando, rol: perfil?.rol ?? null,
    recargarPerfil: () => cargarPerfil(sesion),
    salir: async () => { await supabase.auth.signOut(); setPerfil(null); },
  };
  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>;
}

export const useAuth = () => useContext(Ctx);

/** Pantalla de inicio según el rol. */
export function inicioDeRol(rol) {
  switch (rol) {
    case 'bibliotecaria': return '/panel';
    case 'comision': return '/panel';
    case 'caja': return '/caja';
    case 'repartidor': return '/reparto';
    default: return '/';
  }
}
