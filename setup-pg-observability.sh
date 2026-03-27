#!/usr/bin/env bash
# setup-pg-observability.sh
# Configures PostgreSQL on this machine to meet Grafana Database Observability requirements.
# Must be run on the target server (or via: ssh <host> 'bash -s' < setup-pg-observability.sh)
#
# Two users are intentionally kept separate:
#   DB_APP_USER     — application user (read/write to the app database, e.g. farmapp)
#   DB_MONITOR_USER — dedicated read-only observability user for Grafana Alloy (e.g. db-o11y)
#
# What it does:
#   1. Enables pg_stat_statements in shared_preload_libraries
#   2. Restarts PostgreSQL to load pg_stat_statements (required before setting its GUCs)
#   3. Sets pg_stat_statements.track       = all
#   4. Sets track_io_timing               = on
#   5. Sets track_activity_query_size     = 4096
#   6. Creates the dedicated monitoring user if it doesn't exist
#   7. Creates the pg_stat_statements extension in the target database
#   8. Grants pg_monitor + pg_read_all_stats to the monitoring user
#   9. Grants USAGE on schema + SELECT on all tables to the monitoring user
#
# Usage:
#   bash setup-pg-observability.sh
#   DB_NAME=mydb DB_MONITOR_USER=db-o11y DB_MONITOR_PASS=secret bash setup-pg-observability.sh

set -euo pipefail

# ─── Config (override via env vars) ──────────────────────────────────────────
DB_NAME="${DB_NAME:-crophealth}"
DB_MONITOR_USER="${DB_MONITOR_USER:-db-o11y}"
DB_MONITOR_PASS="${DB_MONITOR_PASS:-db_o11y_password}"
PG_CONF_DIR="${PG_CONF_DIR:-}"          # auto-detected if empty
PG_VERSION="${PG_VERSION:-}"            # auto-detected if empty

info()    { echo "▶  $*"; }
ok()      { echo "✔  $*"; }
warn()    { echo "⚠  $*"; }
die()     { echo "✘  $*" >&2; exit 1; }
psql_su() { sudo -u postgres psql "$@"; }

# ─── 1. Detect PostgreSQL version and config dir ──────────────────────────────
info "Detecting PostgreSQL installation…"
command -v psql > /dev/null || die "psql not found. Install PostgreSQL first."

if [ -z "$PG_VERSION" ]; then
  PG_VERSION=$(psql_su -tc "SHOW server_version_num;" | tr -d '[:space:]')
  PG_MAJOR=$(psql_su -tc "SHOW server_version;" | grep -oP '^\s*\K\d+')
else
  PG_MAJOR="$PG_VERSION"
fi

if [ -z "$PG_CONF_DIR" ]; then
  PG_CONF_DIR=$(psql_su -tc "SHOW config_file;" | tr -d '[:space:]' | xargs dirname)
fi

PG_CONF="$PG_CONF_DIR/postgresql.conf"
ok "PostgreSQL $PG_MAJOR — config: $PG_CONF"

[ -f "$PG_CONF" ] || die "postgresql.conf not found at $PG_CONF"

# ─── 2. Enable pg_stat_statements in shared_preload_libraries ─────────────────
info "Checking shared_preload_libraries…"
CURRENT_SPL=$(psql_su -tc "SHOW shared_preload_libraries;" | tr -d '[:space:]')

if echo "$CURRENT_SPL" | grep -q "pg_stat_statements"; then
  ok "pg_stat_statements already in shared_preload_libraries"
else
  info "Adding pg_stat_statements to shared_preload_libraries…"
  if grep -qE "^#?shared_preload_libraries" "$PG_CONF"; then
    sudo sed -i "s|^#*shared_preload_libraries\s*=.*|shared_preload_libraries = 'pg_stat_statements'|" "$PG_CONF"
  else
    echo "shared_preload_libraries = 'pg_stat_statements'" | sudo tee -a "$PG_CONF" > /dev/null
  fi
  ok "shared_preload_libraries updated"
fi

# ─── 3. Restart PostgreSQL to load pg_stat_statements ────────────────────────
# Must happen before ALTER SYSTEM SET pg_stat_statements.* — the GUCs are only
# recognized after the library is loaded via shared_preload_libraries.
info "Restarting PostgreSQL to load pg_stat_statements…"
sudo systemctl restart postgresql
sleep 3
sudo systemctl is-active postgresql > /dev/null || die "PostgreSQL failed to start after restart"
ok "PostgreSQL restarted"

# ─── 4. Apply settings via ALTER SYSTEM (persisted to postgresql.auto.conf) ───
info "Applying pg_stat_statements and tracking settings…"

psql_su -c "ALTER SYSTEM SET pg_stat_statements.track = 'all';"
ok "pg_stat_statements.track = all"

psql_su -c "ALTER SYSTEM SET track_io_timing = on;"
ok "track_io_timing = on"

psql_su -c "ALTER SYSTEM SET track_activity_query_size = 4096;"
ok "track_activity_query_size = 4096"

psql_su -c "SELECT pg_reload_conf();" > /dev/null
ok "Configuration reloaded"

# track_activity_query_size is postmaster-level: needs a second restart to apply
info "Restarting PostgreSQL to apply track_activity_query_size…"
sudo systemctl restart postgresql
sleep 3
sudo systemctl is-active postgresql > /dev/null || die "PostgreSQL failed to start after second restart"
ok "PostgreSQL restarted"

# ─── 5. Verify settings took effect ──────────────────────────────────────────
info "Verifying settings…"
psql_su -c "SELECT name, setting FROM pg_settings
  WHERE name IN (
    'shared_preload_libraries',
    'pg_stat_statements.track',
    'track_io_timing',
    'track_activity_query_size'
  );"

# ─── 6. Create pg_stat_statements extension in target database ────────────────
info "Ensuring pg_stat_statements extension exists in database '$DB_NAME'…"
DB_EXISTS=$(psql_su -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" | tr -d '[:space:]')
if [ "$DB_EXISTS" != "1" ]; then
  warn "Database '$DB_NAME' does not exist — skipping extension and grant steps."
  warn "Create the database first and re-run this script."
else
  psql_su -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
  ok "pg_stat_statements extension ready in '$DB_NAME'"

  # ─── 7. Create monitoring user if missing, then grant roles ─────────────────
  USER_EXISTS=$(psql_su -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_MONITOR_USER';" | tr -d '[:space:]')
  if [ "$USER_EXISTS" != "1" ]; then
    info "Creating monitoring user '$DB_MONITOR_USER'…"
    psql_su -c "CREATE USER \"$DB_MONITOR_USER\" WITH PASSWORD '$DB_MONITOR_PASS' CONNECTION LIMIT 10;"
    ok "User '$DB_MONITOR_USER' created"
  else
    ok "User '$DB_MONITOR_USER' already exists"
  fi

  info "Granting roles and permissions to '$DB_MONITOR_USER'…"

  psql_su -c "GRANT pg_monitor TO \"$DB_MONITOR_USER\";"
  ok "GRANT pg_monitor"

  psql_su -c "GRANT pg_read_all_stats TO \"$DB_MONITOR_USER\";"
  ok "GRANT pg_read_all_stats"

  psql_su -d "$DB_NAME" -c "GRANT USAGE ON SCHEMA public TO \"$DB_MONITOR_USER\";"
  ok "GRANT USAGE ON SCHEMA public"

  psql_su -d "$DB_NAME" -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"$DB_MONITOR_USER\";"
  ok "GRANT SELECT ON ALL TABLES"

  psql_su -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO \"$DB_MONITOR_USER\";"
  ok "ALTER DEFAULT PRIVILEGES (future tables)"
fi

# ─── 8. Final verification ────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo " Grafana DB Observability — PostgreSQL Setup Complete"
echo "════════════════════════════════════════════════════════"
psql_su -d "$DB_NAME" -c "
SELECT
  (SELECT setting FROM pg_settings WHERE name = 'shared_preload_libraries')       AS shared_preload_libraries,
  (SELECT setting FROM pg_settings WHERE name = 'pg_stat_statements.track')       AS pss_track,
  (SELECT setting FROM pg_settings WHERE name = 'track_io_timing')                AS track_io_timing,
  (SELECT setting FROM pg_settings WHERE name = 'track_activity_query_size')      AS query_size,
  (SELECT extversion FROM pg_extension WHERE extname = 'pg_stat_statements')      AS pss_version,
  (SELECT COUNT(*) > 0 FROM pg_stat_statements)                                   AS pss_accessible;
"
echo ""
psql_su -c "
SELECT r.rolname AS monitoring_user, ARRAY_AGG(m.rolname ORDER BY m.rolname) AS granted_roles
FROM pg_roles r
JOIN pg_auth_members am ON am.member = r.oid
JOIN pg_roles m ON m.oid = am.roleid
WHERE r.rolname = '$DB_MONITOR_USER'
GROUP BY r.rolname;
"
