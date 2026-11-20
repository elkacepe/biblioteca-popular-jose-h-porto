#!/usr/bin/env bash
# Crea una base limpia en un Postgres local y aplica stub + migraciones + seed.
set -euo pipefail
DB=${DB:-porto_test}
PSQL="psql -h ${PGHOST:-/tmp/pg} -U postgres -v ON_ERROR_STOP=1 -q"
$PSQL -d postgres -c "drop database if exists $DB" -c "create database $DB"
DIR=$(cd "$(dirname "$0")/.." && pwd)
$PSQL -d $DB -f "$DIR/tests/00_stub_supabase.sql"
for f in "$DIR"/migrations/*.sql; do $PSQL -d $DB -f "$f"; done
$PSQL -d $DB -f "$DIR/seed.sql"
echo "OK: base $DB lista"
