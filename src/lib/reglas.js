// Espejo de reglas para VISTA PREVIA en pantalla. La base de datos siempre recalcula
// y es la que decide (ver supabase/migrations/*_reglas.sql).

export const MULTIPLICADOR = { 'Muy bueno': 1, Bueno: 0.8, Regular: 0.5 };

/** Precio sugerido: precio base de la categoría × estado físico, redondeado a la centena. */
export function precioSugerido(precioBase, estadoFisico) {
  const m = MULTIPLICADOR[estadoFisico];
  if (!m) return null;
  return Math.round((precioBase * m) / 100) * 100;
}

/**
 * Promoción de feria: se ordenan los libros por precio de mayor a menor y se arman
 * grupos de 3; el más barato de cada grupo completo va sin cargo. 2 libros no forman grupo.
 * Recibe [{id, codigo, precio}] y devuelve el set de ids sin cargo y el descuento.
 */
export function promoFeria(items) {
  const orden = [...items].sort((a, b) => b.precio - a.precio || String(a.codigo).localeCompare(String(b.codigo)));
  const sinCargo = new Set();
  let descuento = 0;
  orden.forEach((it, i) => {
    if ((i + 1) % 3 === 0) { sinCargo.add(it.id); descuento += Number(it.precio); }
  });
  const subtotal = items.reduce((s, it) => s + Number(it.precio), 0);
  return { sinCargo, descuento, subtotal, total: subtotal - descuento };
}

export const DESCUENTO_SOCIO = 0.15;

export const MOTIVOS_DEVOLUCION = [
  'Defecto no informado', 'Páginas faltantes o dañadas', 'No era el libro pedido',
  'Llegó dañado en el envío', 'Ya lo tenía', 'Cambié de idea', 'Otro',
];

export const MOTIVOS_NO_ENTREGA = ['No había nadie', 'Dirección incompleta', 'No atendieron el teléfono', 'Rechazó el pedido', 'Otro'];

export const ROLES = {
  comprador: 'Comprador/a',
  caja: 'Voluntariado de caja',
  repartidor: 'Reparto voluntario',
  bibliotecaria: 'Bibliotecaria',
  comision: 'Comisión directiva',
};
