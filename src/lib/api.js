import { supabase } from './supabase.js';

/**
 * Error de la app. `tipo`:
 *  - 'conflicto': el dato cambió mientras tanto (otro canal se quedó con el libro, cupo lleno…). Se ofrece actualizar.
 *  - 'regla': la acción no cumple una regla del negocio (fuera de horario, falta motivo…).
 *  - 'permiso': la cuenta no puede hacer eso.
 *  - 'red': no hubo conexión.
 */
export class AppError extends Error {
  constructor(message, tipo = 'regla', detalle = null) {
    super(message);
    this.tipo = tipo;
    this.detalle = detalle;
  }
}

export function aAppError(error) {
  if (error instanceof AppError) return error;
  if (!error) return new AppError('Algo salió mal.');
  const msg = error.message || String(error);
  if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) {
    return new AppError('No hay conexión. Revisá la señal y probá de nuevo: no se guardó nada.', 'red');
  }
  let detalle = null;
  try { detalle = error.details ? JSON.parse(error.details) : null; } catch { detalle = error.details; }
  const tipo = ['conflicto', 'regla', 'permiso'].includes(error.hint) ? error.hint
    : error.code === '42501' ? 'permiso' : 'regla';
  return new AppError(msg, tipo, detalle);
}

/** Llama a una función de la base (una operación = una transacción). */
export async function rpc(nombre, params = {}) {
  const { data, error } = await supabase.rpc(nombre, params);
  if (error) throw aAppError(error);
  return data;
}

/** Consulta de tabla con RLS. */
export async function consulta(promesa) {
  const { data, error, count } = await promesa;
  if (error) throw aAppError(error);
  return count !== undefined && count !== null ? { data, count } : data;
}

/** Clave de idempotencia: la misma confirmación repetida no vuelve a cobrar ni a consumir. */
export function nuevaClave() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}
