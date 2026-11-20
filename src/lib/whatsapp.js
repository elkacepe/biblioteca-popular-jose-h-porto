// Avisos: no se envía nada automáticamente. Se arma el texto y se abre WhatsApp
// para que la persona lo mande. Punto de conexión para una integración real: esta función.
export const WHATSAPP_BIBLIOTECA = import.meta.env.VITE_WHATSAPP_BIBLIOTECA || '5493541000000';

/** Normaliza un teléfono argentino de prueba a formato wa.me (549 + característica + número). */
export function telefonoWa(tel) {
  if (!tel) return '';
  let d = String(tel).replace(/\D/g, '');
  if (d.startsWith('549')) return d;
  if (d.startsWith('54')) return '549' + d.slice(2);
  if (d.startsWith('0')) d = d.slice(1);
  return '549' + d;
}

export function enlaceWhatsApp(texto, telefono) {
  const num = telefono ? telefonoWa(telefono) : '';
  return `https://wa.me/${num}?text=${encodeURIComponent(texto)}`;
}

export const textos = {
  reserva: (p) =>
    `¡Hola! Soy ${p.contacto}. Reservé en la web de la Biblioteca Popular José H. Porto el pedido #${p.numero} ` +
    `(${p.libros}) por ${p.total}. ¿Cómo hago el pago? La reserva dura 48 horas.`,
  enCamino: (e, dia) =>
    `¡Hola ${e.contacto}! Te escribe la Biblioteca Popular José H. Porto. Hoy ${dia} pasamos a llevarte el pedido #${e.numero} ` +
    `(${e.libros} ${e.libros === 1 ? 'libro' : 'libros'}) entre las 15 y las 19 a ${e.direccion}. ¡Gracias por bancar la biblioteca!`,
  noEntregado: (e, proximo) =>
    `¡Hola ${e.contacto}! Pasamos con tu pedido #${e.numero} de la Biblioteca Porto pero no lo pudimos entregar. ` +
    (proximo ? `Volvemos a intentar el ${proximo}.` : 'Lo vas a poder retirar en la biblioteca durante 15 días.'),
  listoRetiro: (p) =>
    `¡Hola ${p.contacto}! Tu pedido #${p.numero} ya está listo para retirar en la Biblioteca Popular José H. Porto, ` +
    `de lunes a viernes de 8:30 a 12 y de 15 a 19. Te lo guardamos 15 días.`,
  consulta: (titulo) =>
    `¡Hola! Vi en la web de la Biblioteca Porto «${titulo}». ¿Sigue disponible?`,
};
