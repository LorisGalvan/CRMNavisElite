#!/usr/bin/env bash
# Prova lo schema su un PostgreSQL locale usa e getta.
# Uso: bash supabase/test/esegui.sh   (serve PostgreSQL 15+ installato)
set -euo pipefail
QUI="$(cd "$(dirname "$0")" && pwd)"
BIN="${PG_BIN:-$(dirname "$(command -v initdb || ls /usr/lib/postgresql/*/bin/initdb | tail -1)")}"
TMP="$(mktemp -d)"
trap '"$BIN/pg_ctl" -D "$TMP/data" stop -m fast >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
"$BIN/initdb" -D "$TMP/data" -U postgres >/dev/null
"$BIN/pg_ctl" -D "$TMP/data" -o "-k $TMP -p 5499 -c listen_addresses=" -l "$TMP/log" start >/dev/null
psql -h "$TMP" -p 5499 -U postgres -v ON_ERROR_STOP=1 -q -f "$QUI/finto_supabase.sql" -f "$QUI/../schema.sql" 2>&1 | grep -v NOTICE || true
cd "$QUI" && psql -h "$TMP" -p 5499 -U postgres -v ON_ERROR_STOP=1 -q -At -f permessi.sql
