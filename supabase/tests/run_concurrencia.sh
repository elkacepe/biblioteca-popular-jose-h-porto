#!/usr/bin/env bash
# Dos voluntarias venden el MISMO ejemplar al mismo tiempo en la feria.
# Esperado: una venta y un mensaje claro para la otra. Requiere run_local.sh antes.
set -euo pipefail
DB=${DB:-porto_test}
PSQL="psql -h ${PGHOST:-/tmp/pg} -U postgres -d $DB -X -q -t -A"
FERIA=$($PSQL -c "update ferias set estado='Abierta' where estado='Planificada' returning id")
EJ=$($PSQL -c "select e.id from ejemplares e join cajas_feria k on k.id=e.caja_feria_id where k.feria_id=$FERIA and e.estado='En feria' order by codigo limit 1")
como() { echo "select set_config('request.jwt.claim.sub',(select id::text from perfiles where email='$1'),false); set role authenticated;"; }

# Norma toma el libro y tarda 2 segundos en confirmar (la transacción queda abierta).
( $PSQL -c "$(como norma@porto.test) begin; select vender_feria($FERIA, array['$EJ']::uuid[], 'efectivo')->>'numero'; select pg_sleep(2); commit;" \
   > /tmp/venta_norma.txt 2>&1 ) &
sleep 0.5
# Rubén confirma el mismo libro mientras tanto: espera el bloqueo y recibe el conflicto.
$PSQL -c "$(como ruben@porto.test) select vender_feria($FERIA, array['$EJ']::uuid[], 'efectivo');" > /tmp/venta_ruben.txt 2>&1 || true
wait
echo "Norma: $(grep -v '^$' /tmp/venta_norma.txt | tr '\n' ' ')"
echo "Rubén: $(grep -o 'ERROR:.*' /tmp/venta_ruben.txt || cat /tmp/venta_ruben.txt)"
N=$($PSQL -c "select count(*) from venta_items where ejemplar_id='$EJ'")
echo "Ventas registradas para el ejemplar: $N"
test "$N" = "1" && grep -q "ya encontró dueño" /tmp/venta_ruben.txt && echo "OK: una sola venta y mensaje claro"

# Doble toque en «Confirmar» con la misma clave de idempotencia: una sola venta.
EJ2=$($PSQL -c "select e.id from ejemplares e join cajas_feria k on k.id=e.caja_feria_id where k.feria_id=$FERIA and e.estado='En feria' order by codigo limit 1")
K=$(cat /proc/sys/kernel/random/uuid)
A=$($PSQL -c "$(como norma@porto.test) select vender_feria($FERIA, array['$EJ2']::uuid[], 'efectivo', '$K')->>'venta_id';" | tail -1)
B=$($PSQL -c "$(como norma@porto.test) select vender_feria($FERIA, array['$EJ2']::uuid[], 'efectivo', '$K')->>'venta_id';" | tail -1)
echo "Primera confirmación: venta $A · repetida: venta $B"
test "$A" = "$B" && test "$($PSQL -c "select count(*) from movimientos_dinero where venta_id=$A")" = "1" && echo "OK: repetir la confirmación no cobra dos veces"
