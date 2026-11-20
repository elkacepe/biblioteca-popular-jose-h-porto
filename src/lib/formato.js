const pesos = new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS', maximumFractionDigits: 0 });

export const plata = (n) => pesos.format(Number(n || 0)).replace(/ /g, ' ');

const TZ = 'America/Argentina/Cordoba';

export function fecha(f, opciones = {}) {
  if (!f) return '—';
  const d = typeof f === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(f) ? new Date(f + 'T12:00:00-03:00') : new Date(f);
  return d.toLocaleDateString('es-AR', { timeZone: TZ, day: 'numeric', month: 'short', ...opciones });
}

export function fechaHora(f) {
  if (!f) return '—';
  return new Date(f).toLocaleString('es-AR', { timeZone: TZ, day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}

export function diaSemana(f) {
  if (!f) return '';
  const d = new Date(f + 'T12:00:00-03:00');
  return d.toLocaleDateString('es-AR', { timeZone: TZ, weekday: 'long' });
}

export const hora = (h) => (h ? h.slice(0, 5).replace(/^0/, '').replace(/:00$/, '') : '');

/** Fecha de hoy en Córdoba, formato AAAA-MM-DD. */
export function hoyISO() {
  return new Date().toLocaleDateString('en-CA', { timeZone: TZ });
}

export function faltan(f) {
  const ms = new Date(f) - new Date();
  if (ms <= 0) return 'venció';
  const h = Math.floor(ms / 3.6e6);
  if (h >= 24) return `${Math.floor(h / 24)} d ${h % 24} h`;
  return `${h} h ${Math.floor((ms % 3.6e6) / 6e4)} min`;
}

export const plural = (n, uno, varios) => `${n} ${n === 1 ? uno : varios}`;
