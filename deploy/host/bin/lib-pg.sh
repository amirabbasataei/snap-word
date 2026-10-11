# Shared helpers for the infra scripts (sourced, not executed).
PG="${PG:-infra-postgres}"
# psql_su: arguments only (-c ...). psql_in: SQL on stdin. Only psql_in uses
# `docker exec -i`, which would otherwise swallow the caller's stdin.
psql_su() { docker exec -e PGOPTIONS="-c client_min_messages=warning" "$PG" psql -v ON_ERROR_STOP=1 -U postgres -qtA "$@"; }
psql_in() { docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$PG" psql -v ON_ERROR_STOP=1 -U postgres -qtA "$@"; }
# "schema.table=rows" for every user table, one per line, sorted (PostGIS catalogs excluded).
table_counts() {
  psql_in -d "$1" <<'SQL'
select format('%I.%I=%s', table_schema, table_name,
  (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text)
from information_schema.tables
where table_type = 'BASE TABLE'
  and table_schema not in ('pg_catalog', 'information_schema', 'tiger', 'tiger_data', 'topology')
  and table_name <> 'spatial_ref_sys'
order by 1;
SQL
}
