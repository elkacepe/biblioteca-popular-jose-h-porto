-- Fija el search_path de las funciones auxiliares que no lo tenían (aviso del linter de Supabase).
alter function interno.ts(date, time) set search_path = public, pg_temp;
alter function interno.hoy() set search_path = public, interno, pg_temp;
alter function interno.conflicto(text, jsonb) set search_path = pg_temp;
alter function interno.regla(text) set search_path = pg_temp;
alter function interno.transicion_valida(public.estado_ejemplar, public.estado_ejemplar) set search_path = public, pg_temp;
alter function interno.tg_ejemplar_guardia() set search_path = public, interno, pg_temp;
alter function interno.tg_arqueo_bloqueado() set search_path = public, pg_temp;
alter function interno.tg_arqueo_no_borrar() set search_path = pg_temp;
alter function interno.mensaje_conflicto(jsonb) set search_path = pg_temp;
