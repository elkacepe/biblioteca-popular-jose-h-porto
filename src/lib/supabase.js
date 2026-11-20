import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const configurado = Boolean(url && anonKey && !url.includes('tu-proyecto'));

// Solo la clave anon (pública). La service_role nunca se usa en el navegador.
export const supabase = createClient(url || 'http://localhost:54321', anonKey || 'falta-configurar', {
  auth: { persistSession: true, autoRefreshToken: true },
});
