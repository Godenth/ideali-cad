#!/bin/bash
# Sobe um Postgres local descartável e aplica as migrações (para testes).
PGBIN=/usr/lib/postgresql/16/bin; D=/var/tmp/pgtest
[ -d $D/data ] || (mkdir -p $D && chown postgres $D && su postgres -c "$PGBIN/initdb -D $D/data -A trust >/dev/null")
su postgres -c "$PGBIN/pg_ctl -D $D/data -o '-p 5499 -k /tmp' -l $D/log status" >/dev/null 2>&1 || su postgres -c "$PGBIN/pg_ctl -D $D/data -o '-p 5499 -k /tmp' -l $D/log -w start" >/dev/null
cd "$(dirname "$0")/.."
P="psql -h /tmp -p 5499 -U postgres -q -v ON_ERROR_STOP=1"
$P -c "drop database if exists t" && $P -c "create database t" && $P -d t -f tests/stub_supabase_local.sql && $P -d t -f migrations/001_base.sql && $P -d t -f migrations/002_trabalho.sql && echo BANCO_OK
