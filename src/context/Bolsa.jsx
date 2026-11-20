import { createContext, useContext, useEffect, useState } from 'react';

// La bolsa vive en el navegador. No reserva nada: la reserva ocurre al confirmar el pedido,
// en una sola operación de la base.
const Ctx = createContext(null);
const CLAVE = 'porto.bolsa';

export function BolsaProvider({ children }) {
  const [items, setItems] = useState(() => {
    try { return JSON.parse(localStorage.getItem(CLAVE)) || []; } catch { return []; }
  });
  useEffect(() => { localStorage.setItem(CLAVE, JSON.stringify(items)); }, [items]);

  const valor = {
    items,
    agregar: (libro) => setItems((xs) => (xs.some((x) => x.id === libro.id) ? xs : [...xs, {
      id: libro.id, codigo: libro.codigo, titulo: libro.titulo, autor: libro.autor, precio: Number(libro.precio),
      categoria: libro.categoria, categoria_color: libro.categoria_color, estado_fisico: libro.estado_fisico,
    }])),
    quitar: (id) => setItems((xs) => xs.filter((x) => x.id !== id)),
    quitarVarios: (ids) => setItems((xs) => xs.filter((x) => !ids.includes(x.id))),
    vaciar: () => setItems([]),
    tiene: (id) => items.some((x) => x.id === id),
  };
  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>;
}

export const useBolsa = () => useContext(Ctx);
