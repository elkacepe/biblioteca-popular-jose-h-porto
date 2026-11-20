// CSV pensado para abrirse con Excel/LibreOffice en español: separador «;» y BOM UTF-8.
const celda = (v) => {
  if (v === null || v === undefined) return '';
  const s = String(v);
  return /[";\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

export function aCSV(filas, columnas) {
  const encabezado = columnas.map((c) => celda(c.titulo)).join(';');
  const cuerpo = filas.map((f) => columnas.map((c) => celda(typeof c.valor === 'function' ? c.valor(f) : f[c.clave])).join(';'));
  return '﻿' + [encabezado, ...cuerpo].join('\r\n');
}

export function descargarCSV(nombre, filas, columnas) {
  const blob = new Blob([aCSV(filas, columnas)], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nombre.endsWith('.csv') ? nombre : `${nombre}.csv`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
