import { test } from 'node:test';
import assert from 'node:assert/strict';
import { promoFeria, precioSugerido } from './reglas.js';
import { aCSV } from './csv.js';

const libros = (...precios) => precios.map((precio, i) => ({ id: `e${i}`, codigo: `PJ-${i}`, precio }));

test('dos libros no forman grupo', () => {
  assert.equal(promoFeria(libros(6000, 5000)).descuento, 0);
});

test('tres libros: el más barato va sin cargo', () => {
  const r = promoFeria(libros(3000, 4000, 2500));
  assert.equal(r.descuento, 2500);
  assert.equal(r.total, 7000);
});

test('cinco libros: un grupo completo (los tres más caros), dos sueltos', () => {
  const r = promoFeria(libros(4000, 3000, 2500, 2000, 1500));
  assert.equal(r.descuento, 2500);
  assert.equal(r.total, 10500);
});

test('seis libros: dos grupos', () => {
  assert.equal(promoFeria(libros(6000, 5000, 4000, 3000, 2500, 2000)).descuento, 6000);
});

test('precio sugerido redondea a la centena', () => {
  assert.equal(precioSugerido(4000, 'Bueno'), 3200);
  assert.equal(precioSugerido(3500, 'Regular'), 1800);
  assert.equal(precioSugerido(1500, 'Regular'), 800);
  assert.equal(precioSugerido(6000, 'Muy bueno'), 6000);
});

test('CSV con BOM, punto y coma y comillas', () => {
  const csv = aCSV([{ a: 'Hola; "che"', b: 1500 }], [{ clave: 'a', titulo: 'Texto' }, { clave: 'b', titulo: 'Importe' }]);
  assert.equal(csv, '﻿Texto;Importe\r\n"Hola; ""che""";1500');
});
