# Biblioteca Popular José H. Porto · Libros solidarios

Sistema con el que la biblioteca convierte los libros repetidos de sus donaciones en plata para funcionar.
Catálogo público + panel de gestión + caja de feria para el celular + hoja de reparto, sobre **React + Tailwind + Supabase**.

La idea central: **no se venden productos con cantidades, se venden ejemplares únicos que se mueven**.
Cada copia tiene un código (`PJ-01023`), una sola ubicación y un solo estado. Toda operación que cambia
estado, stock, cupo o dinero se resuelve **dentro de la base, en una sola transacción**, con las filas bloqueadas.

## Entrega

| | |
|---|---|
| **Previsualización** | <https://biblioteca-popular-jose-h-porto.vercel.app/> |
| **Repositorio** | <https://github.com/elkacepe/biblioteca-popular-jose-h-porto> |
| **Base de datos** | Proyecto Supabase `biblioteca-porto` (región São Paulo), instalado desde cero con `supabase/instalar_todo.sql` |
| **SQL** | `supabase/migrations/` (7 archivos), `supabase/seed.sql`, `supabase/instalar_todo.sql` |
| **Variables** | `.env.example` (solo nombres y valores de prueba; ninguna clave secreta) |
| **Cuentas de prueba** | ver sección 1.3 · contraseña `Porto2026!` |
| **Caso del briefing** | ver sección 2 bis |

---

## 1. Cómo arrancar

Requisitos: **Node 20 o superior** (probado con Node 22) y un proyecto gratuito de Supabase.

### 1.1 Base de datos (Supabase) — paso a paso, sin experiencia previa

1. Entrá a <https://supabase.com>, creá una cuenta gratis (podés usar GitHub) y tocá **New project**.
   Nombre `biblioteca-porto`, región **South America (São Paulo)**, inventá una contraseña de base y guardala. Esperá ~2 minutos.
2. Menú izquierdo **Authentication → Sign In / Providers → Email**: desactivá **«Confirm email»** y guardá.
   (No hay confirmaciones ni recuperación por correo.)
3. Menú izquierdo **SQL Editor → New query**: pegá **todo** el contenido de [`supabase/instalar_todo.sql`](supabase/instalar_todo.sql)
   y tocá **Run**. Crea tablas, reglas, seguridad, cuentas de prueba y datos sintéticos. Debe terminar con «Success».
   (Es la concatenación de `supabase/migrations/*.sql` + `supabase/seed.sql`; con la CLI: `npx supabase db reset --linked`.)
4. **Project Settings → API** (o el botón **Connect**): copiá la **Project URL** y la clave **anon public**.
   La `service_role` **no** se copia en ningún lado.

### 1.2 Aplicación

```bash
npm install
cp .env.example .env.local      # completá VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY (Project Settings → API)
npm run dev                     # http://localhost:5173
```

Otros comandos: `npm run build` (genera `dist/`), `npm run preview`, `npm test` (pruebas de la promo, el precio sugerido y el CSV).

> En `.env.local` va **solo la clave anon** (pública). La `service_role` no se usa en ningún lado: ni en el navegador ni en el repositorio.

### 1.3 Cuentas de prueba

Todas con contraseña **`Porto2026!`**. Datos 100 % sintéticos. En la pantalla de ingreso hay una lista para completarlas con un toque
(se oculta con `VITE_MOSTRAR_CUENTAS_PRUEBA=false`).

| Correo | Rol | Para probar |
|---|---|---|
| `marta@porto.test` | Bibliotecaria | Todo el panel: donaciones, depósito, pedidos, ferias, mostrador, reparto, devoluciones, rendiciones, informes, ajustes |
| `comision@porto.test` | Comisión directiva | Tablero, informes y rendiciones, sin editar |
| `norma@porto.test` · `ruben@porto.test` | Voluntariado de caja (feria) | Caja de la feria del domingo, venta simultánea, cierre |
| `julia@porto.test` | Voluntariado de caja (mostrador) | Mostrador con ticket y cierre de jornada |
| `hugo@porto.test` | Reparto (martes: Centro, Villa del Lago, Santa Rita) | Hoja del martes con 9 entregas de Centro |
| `carla@porto.test` | Reparto (jueves: La Cuesta, Playas de Oro) | Hoja del jueves |
| `elena@porto.test` | Compradora, socia n.º 1047 con la cuota al día | 15 % de descuento, envío sin cargo con 4 libros |
| `tomas@porto.test` | Comprador, socio 0882 con la cuota vencida | Sin descuento; pedido en «Retiro en biblioteca» |
| `lucia@porto.test` | Compradora, no socia | Su reserva de hace 49 h se cancela sola |
| `raul@`, `sofia@`, `andres@`, `beatriz@`, `ines@`, `diego@porto.test` | Compradores de zona Centro | Pedidos del recorrido; Sofía tiene una devolución pedida |

El **registro público** crea siempre cuentas con rol **comprador**: el trigger `interno.tg_nuevo_usuario` ignora cualquier rol que mande el formulario
y los perfiles no tienen permiso de escritura desde la API. Los roles del personal se asignan en la base (lo hace `seed.sql`).

---

### 1.4 Publicar en Vercel (URL de previsualización)

1. En <https://vercel.com> → **Add New → Project** → importá el repositorio de GitHub.
2. Framework: **Vite** (se detecta solo; `vercel.json` ya trae el build y la regla para que funcionen las rutas internas).
3. En **Environment Variables** cargá `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` (las del paso 1.1.4) y, opcional, `VITE_WHATSAPP_BIBLIOTECA`.
4. **Deploy**. Cada push a GitHub genera una URL de previsualización nueva.

---

## 2. Dónde está cada cosa

```
supabase/
  migrations/
    …001_esquema.sql      tablas, tipos y restricciones (el modelo de ejemplares únicos)
    …002_reglas.sql       TODAS las operaciones de negocio (funciones RPC transaccionales)
    …003_seguridad.sql    alta de perfiles, permisos y políticas RLS
    …004_datos_base.sql   configuración, categorías, zonas y ubicaciones de prueba
    …005_demo.sql         datos de demostración y reiniciar_demo()
    …006_informes.sql     funciones de informes (solo lectura)
    …007_search_path.sql  ajuste de seguridad pedido por el linter de Supabase
  seed.sql                cuentas de Auth de prueba + carga de la demo
  instalar_todo.sql       migraciones + seed en un solo archivo (para pegar en el SQL Editor)
  tests/
    aceptacion.sql        pruebas de los 11 criterios de aceptación
    caso_briefing.sql     el caso de Norma, la socia de Villa del Lago y el martes de reparto
    run_local.sh          arma una base local (Postgres 16) con un stub de auth
    run_concurrencia.sh   dos voluntarias venden el mismo libro al mismo tiempo
src/
  lib/                    supabase.js (cliente), api.js (rpc + errores + idempotencia), reglas.js (vista previa de promo/precio),
                          formato.js, csv.js, whatsapp.js
  context/                Auth.jsx (sesión y rol), Bolsa.jsx (carrito en localStorage)
  components/             ui.jsx (botones, avisos, lomos de categoría…), Layouts.jsx (público, panel, campo)
  pages/publico/          Catalogo, Libro, Bolsa (reserva), Ferias, Ingresar/Registro
  pages/comprador/        MisPedidos (seguimiento, cancelación, devoluciones, crédito)
  pages/gestion/          Inicio, Donaciones, Lote, Deposito (ficha del ejemplar), Pedidos, Ferias, Feria (armado de cajas),
                          Mostrador, Reparto, Devoluciones, Rendiciones, Informes, Ajustes
  pages/caja/             MisCajas, CajaFeria (pensada para el sol), VentaEnCurso, Cierre (arqueo de feria o jornada)
  pages/reparto/          MisRecorridos, Hoja
  pages/Ticket.jsx        ticket imprimible
```

**Lógica de datos:** toda en `supabase/migrations/…002_reglas.sql`. La app no escribe tablas: llama funciones (`supabase.rpc`).
Las pantallas leen tablas directamente (las filtra RLS) o funciones de consulta.

---

## 2 bis. Reproducir el caso del briefing (con los datos sintéticos)

Con la base recién instalada (o después de **Ajustes → Reiniciar datos**). Conviene usar dos ventanas: una normal y otra de incógnito.

| # | Quién | Qué hacer | Resultado esperado |
|---|---|---|---|
| 1 | `norma@porto.test` (celular) | **Abrir la caja** de la feria del domingo → **Abrir la feria**. Anotá el título y el código de cualquier libro de la lista (p. ej. una novela). | La feria pasa a «Abierta» y se ven los libros de las 3 cajas. |
| 2 | `elena@porto.test` (socia de Villa del Lago, otra ventana) | En el catálogo buscá ese título o su código. | Ese ejemplar **no se ofrece en la web** (como mucho aparecen otras copias del mismo título que siguen en el estante): no hay choque posible. |
| 3 | Norma | Tocá el libro y **Efectivo**. | «¡Vendido!». Si alguien hubiera intentado el mismo ejemplar por otro canal, recibiría «Este libro ya encontró dueño». |
| 4 | Norma | **Terminar la feria: arqueo y rendición** → cargá el efectivo contado y las transferencias → **Cerrar la caja**. | Diferencia calculada (si no es cero, pide motivo). «N libros sin vender volvieron a su estante». Rendición bloqueada 🔒. |
| 5 | `comision@porto.test` | **Rendiciones** e **Informes**. | La rendición de la feria aparece cerrada; la recaudación se suma por canal. |
| 6 | `hugo@porto.test` (celular) | **Mis recorridos** → martes, zona Centro. | **9 entregas**. En el panel de Marta: «Quedan 3 lugares» en ese recorrido. |
| 7 | Hugo | **Salgo a repartir**; marcá entregas como **Entregada** y una (1.er intento) como **No entregada → No había nadie**. | «Queda para el recorrido del …»: pasa al **siguiente recorrido de su zona**. Botón para avisar por WhatsApp. |
| 8 | Hugo | Marcá **No entregada** el pedido de Beatriz Ocampo (ya es su **2.º intento**). | «Segunda vez sin entregar: queda para retirar en la biblioteca (15 días)». En Marta → Pedidos → «Para retirar». |

> En los datos de prueba la zona Centro reparte **solo los martes**, así que «el siguiente recorrido» es el martes siguiente
> (el briefing habla del jueves porque es un ejemplo narrativo; la regla implementada es «siguiente recorrido de su zona»).

Lo mismo está automatizado en `supabase/tests/caso_briefing.sql` (ver sección 7).

---

## 3. Cómo se garantiza que un ejemplar no se venda dos veces

- **Dónde está la garantía: en la base.** Cada operación (`crear_pedido`, `vender_feria`, `vender_mostrador`, `agregar_a_caja`,
  `registrar_cobro`, `cerrar_feria`, `marcar_entrega`, `resolver_devolucion`, …) es una función `security definer` que corre en una
  transacción, bloquea las filas involucradas con `SELECT … FOR UPDATE` en orden fijo (sin interbloqueos), **vuelve a leer el estado actual**
  y, si alguna regla falla, lanza una excepción: no queda ningún cambio parcial.
- **Segunda red:** un trigger en `ejemplares` rechaza cualquier transición de estado inválida (p. ej. de «En feria» a «Reservado»), y hay
  `CHECK` para cupos (`cupo_disponible` nunca negativo), descarte con motivo, reserva con vencimiento, etc.
- **Nadie escribe tablas desde la API:** `authenticated` y `anon` solo tienen `SELECT` (filtrado por RLS).
- **Idempotencia:** cada confirmación manda una clave (`p_idem`). Si se repite (doble toque, reintento con mala señal), la base devuelve el
  mismo resultado sin volver a cobrar, consumir cupo ni liberar nada (`public.operaciones`). Además, repetir una acción ya hecha
  (cobrar un pedido cobrado, cerrar una feria cerrada) responde «ya estaba».
- **Conflictos en pantalla:** el error vuelve con `hint = 'conflicto'` y la lista de ejemplares afectados. La pantalla que originó la acción
  muestra «Este libro ya encontró dueño: «Amalia» (PJ-01005)…» y un botón **Actualizar datos** que saca ese libro de la venta y refresca.

---

## 4. Qué está simulado y cómo se comporta

| Qué | Cómo funciona hoy | Dónde conectar lo real |
|---|---|---|
| **Pagos** | No hay pago en línea. La bibliotecaria registra el cobro a mano («Cobró en efectivo» / «Llegó la transferencia»); en feria y mostrador la caja elige el medio. No hay tarjetas ni rechazos simulados. | `public.registrar_cobro`, `public.vender_feria`, `public.vender_mostrador` (`supabase/migrations/…002_reglas.sql`) y los botones de `src/pages/gestion/Pedidos.jsx` / `src/pages/caja/VentaEnCurso.jsx` |
| **Avisos (correo, SMS)** | No se envía nada. Se confirma en pantalla y hay botones **«… por WhatsApp»** que abren `wa.me` con el texto armado; la persona lo manda. | `src/lib/whatsapp.js` (`enlaceWhatsApp` y `textos`) |
| **Número de WhatsApp de la biblioteca** | De prueba: `VITE_WHATSAPP_BIBLIOTECA` (por defecto `5493541000000`). | `.env.local` |
| **Mapas** | No hay. La hoja de reparto muestra la dirección y el teléfono (enlace `tel:`). | `src/pages/reparto/Hoja.jsx` |
| **Tareas programadas** | No hay cron. El vencimiento de reservas (48 h), la cancelación de retiros (15 días) y la apertura de recorridos de las próximas 2 semanas se aplican de forma **perezosa**: `interno.mantenimiento()` corre al principio de cada operación y de cada consulta del catálogo. Con pg_cron se podría agendar `select interno.mantenimiento();` cada 15 minutos, pero no es necesario. | `interno.mantenimiento` |
| **Correo de Auth** | Desactivado: cuentas confirmadas al crearse, sin recuperación de contraseña (se pide en la biblioteca). | Supabase → Authentication |
| **Horarios** | Por defecto la demo está en **modo prueba**: permite vender en mostrador y feria a cualquier hora (hay un aviso en el panel). Se desactiva en **Ajustes**, y entonces la base exige L a V 8:30–12 y 15–19 para el mostrador y el horario del domingo de la feria. | `public.config.permitir_fuera_de_horario` |
| **Ticket** | Comprobante no fiscal, imprimible desde el navegador (`/ticket/:id`). | `src/pages/Ticket.jsx` |

---

## 5. Datos de ejemplo y cómo reiniciarlos

Las fechas se calculan **respecto del día en que se carga la demo**, así siempre hay una feria por venir, un martes de reparto y una reserva vencida.

- 5 lotes de donaciones (dos anónimos; uno en clasificación y uno recién recibido sin cargar).
- 47 títulos (clásicos de dominio público y títulos inventados) y **≈213 ejemplares**: 53 en venta (los 2 vencidos de Lucía vuelven al cargar), 34 en 3 cajas de la próxima feria,
  4 esperando precio, 2 en el acervo (primer ejemplar de un título nuevo), 2 descartados y el resto vendidos.
- 3 ferias: dos cerradas con rendición (una con diferencia de −$500 y su motivo) y **la del próximo domingo** con 3 cajas armadas y Norma y Rubén asignados.
- 10 jornadas de mostrador cerradas, con ventas (algunas con descuento de socio) y una devolución aprobada en efectivo.
- Reparto: el **martes que viene, zona Centro, 9 entregas** asignadas a Hugo (una es un 2.º intento porque el martes pasado «no había nadie») →
  **«Quedan 3 lugares en el recorrido del martes»**. Un pedido en Villa del Lago, otro en La Cuesta (jueves) y el de Tomás en «Retiro en biblioteca» tras dos fallas.
- Pedidos web: 2 reservas sin cobrar (la de Lucía, de hace 49 h, se cancela sola al primer acceso), 3 cobrados para preparar, entregados y retirados de meses anteriores.
- 1 devolución web pedida por Sofía (dentro de los 7 días, reintegro en crédito).

**Reiniciar:** entrá como `marta@porto.test` → **Ajustes → Reiniciar datos**. Borra todo lo operativo y vuelve a cargar la demo
(función `public.reiniciar_demo()`, solo bibliotecaria). Las cuentas de acceso no se tocan. También se puede ejecutar `select interno.cargar_demo();`
sobre una base vacía. Lo único guardado en el navegador es la bolsa de compras (`localStorage` → `porto.bolsa`).

---

## 6. Reglas implementadas (resumen)

- **Acervo:** al cargar un ejemplar se busca el título por título + autor normalizados. Si la biblioteca no lo tiene, el primer ejemplar
  en condiciones va a **Acervo** y no se puede publicar; los siguientes quedan **En clasificación** con precio sugerido. «Muy malo» → **Descartado** con motivo (y opción de reciclado); no cuenta para el acervo.
- **Precio sugerido** = precio base de la categoría × (100 / 80 / 50 %), redondeado a la centena. Editable antes de publicar.
- **Web:** reserva de 48 h; socio con cuota al día −15 %; envío $1.800, sin cargo para socios con 4 o más libros; el crédito a favor se aplica solo.
- **Feria:** promo — se ordenan los libros de la venta de mayor a menor precio, se arman grupos de 3 y el más barato de cada grupo **completo** va sin cargo (2 libros no forman grupo; con 5 libros bonifica el 3.º más caro; con 6, el 3.º y el 6.º). **Nunca** descuento de socio.
- **Cajas:** 40 libros, hasta 8 por feria; al sumar un libro baja el cupo y el libro desaparece de la web; al cerrar la feria se liberan.
- **Cierre:** efectivo esperado/contado, transferencias registradas/informadas, diferencia (si no es cero, exige motivo). Los sobrantes vuelven a su estante con traslado automático. La rendición queda **bloqueada** (trigger) y solo la bibliotecaria agrega notas.
- **Reparto:** al registrar el cobro el pedido toma el próximo recorrido de su zona con lugar y cuyo cierre (12 h del día anterior) no pasó. 1.ª falla → siguiente recorrido; 2.ª falla → **Retiro en biblioteca**; 15 días sin retirar → cancelado y los libros vuelven a **En venta**.
- **Devoluciones:** 7 días corridos desde la entrega (web: entrega o retiro; mostrador/feria: la venta). En feria solo con defecto no informado. Solicitada → En revisión (el libro pasa a «En devolución») → Aprobada (vuelve a la venta o se descarta) o Rechazada. Reintegro en efectivo (sale del libro de dinero) o crédito, a elección de la persona. El envío se devuelve solo si la falla fue de la biblioteca.
- **Informes:** recaudación por canal, feria y mes; movimientos; más vendidos por título y categoría; devoluciones por motivo; entregas fallidas; ejemplares con +180 días en depósito. Todo sale de `movimientos_dinero` y `venta_items`; cada tabla tiene **Descargar CSV** con los mismos filtros (separador `;`, UTF-8 con BOM para Excel).

### Seguridad (RLS)
RLS activado en **todas** las tablas. Cada repartidor ve solo sus recorridos, entregas y los pedidos de esas entregas; cada voluntario de caja ve solo
las ferias que tiene asignadas (cajas, ejemplares de esas cajas, ventas y arqueos) o el mostrador; cada comprador ve solo sus pedidos, compras,
devoluciones y su perfil. Cambiar un id en la URL no muestra nada fuera de alcance. El público (anon) **no puede leer tablas privadas**:
el catálogo sale de `catalogo_publico()` / `ejemplar_publico()`, que devuelven solo campos públicos (sin ubicación, lote ni historial).
La comisión directiva lee todo y no puede ejecutar ninguna operación.

---

## 7. Pruebas

```bash
# Requiere un Postgres 16 local (no hace falta Supabase): crea la base con un stub de auth
supabase/tests/run_local.sh
psql -h /tmp/pg -U postgres -d porto_test -f supabase/tests/aceptacion.sql   # 11 criterios, ~70 comprobaciones
psql -h /tmp/pg -U postgres -d porto_test -f supabase/tests/caso_briefing.sql # el caso del briefing (correr después de aceptacion.sql)
supabase/tests/run_concurrencia.sh                                         # venta simultánea + doble confirmación
npm test                                                                    # promo, precio sugerido y CSV en JS
```
(`PGHOST` y `DB` se pueden cambiar por variable de entorno.)

---

## 8. Decisiones que no estaban en el encargo

- **Asignación de recorrido al cobrar, no al reservar.** Una reserva sin pagar no ocupa lugar en la camioneta. Al reservar, la persona ve cuántos lugares quedan en el próximo recorrido.
- **«Su caja» = la feria asignada.** Los voluntarios se asignan a una feria (y operan todas sus cajas, como pasa en la plaza) o al mostrador. Las cajas físicas son ubicaciones reutilizables («Caja de feria 1» a «12»).
- **Pedido cobrado que nunca se retira (15 días):** se cancela, los libros vuelven a la venta y lo pagado por los libros queda como **crédito**; el envío no se devuelve.
- **El crédito** se usa automáticamente en el próximo pedido web. En el mostrador solo se puede dar crédito si la venta está a nombre de un socio (por número).
- **Reintegros en efectivo** se descuentan de la jornada de mostrador abierta ese día (salen de esa caja); en los informes siguen contando en el canal de la venta original.
- **Diferencia de arqueo** = (efectivo contado + transferencias informadas) − (efectivo esperado + transferencias registradas).
- **Una feria por mes y solo domingos** se valida en la base. Pedidos con retiro pasan de «Cobrado» a «Retiro en biblioteca» al estar listos (mismo plazo de 15 días).
- **Promo con 5 libros:** el grupo completo lo forman los 3 más caros (orden de mayor a menor), así que va sin cargo el 3.º más caro, no el más barato de toda la venta.
- **Precios redondeados** al peso en descuentos; el precio sugerido, a la centena (Poesía Regular $1.750 → $1.800).
- **Horario y zona horaria:** todo se calcula en `America/Argentina/Cordoba`.
