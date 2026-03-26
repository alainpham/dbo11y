#!/usr/bin/env bash
# check-pg-observability.sh
# Read-only audit of PostgreSQL requirements for Grafana Database Observability.
# Makes no changes to the system.
#
# DB_MONITOR_USER is the dedicated observability user (db-o11y), not the app user (farmapp).
#
# Usage:
#   bash check-pg-observability.sh
#   DB_NAME=mydb DB_MONITOR_USER=db-o11y bash check-pg-observability.sh

set -euo pipefail

DB_NAME="${DB_NAME:-crophealth}"
DB_MONITOR_USER="${DB_MONITOR_USER:-db-o11y}"

PASS=0
FAIL=0
WARN=0

# ─── Output helpers ───────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

pass() { echo -e "  ${GREEN}✔ PASS${RESET}  $*"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✘ FAIL${RESET}  $*"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${RESET}  $*"; WARN=$((WARN + 1)); }
info() { echo -e "  ${CYAN}ℹ${RESET}      $*"; }
section() { echo -e "\n${BOLD}── $* ${RESET}"; }

psql_su()   { sudo -u postgres psql -t -A "$@" 2>/dev/null; }
psql_su_db(){ sudo -u postgres psql -t -A -d "$DB_NAME" "$@" 2>/dev/null; }

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Grafana DB Observability — PostgreSQL Requirements     ║"
echo "║   Host: $(hostname)$(printf '%*s' $((42 - ${#HOSTNAME})) '')║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  Database : $DB_NAME"
echo "  User     : $DB_MONITOR_USER"

# ─── 1. PostgreSQL version ────────────────────────────────────────────────────
section "1. PostgreSQL Version"
if ! command -v psql &>/dev/null; then
  fail "psql not found — PostgreSQL is not installed"
  exit 1
fi

PG_VERSION=$(psql_su -c "SHOW server_version;" | tr -d '[:space:]')
PG_MAJOR=$(echo "$PG_VERSION" | grep -oP '^\d+')
info "Detected version: $PG_VERSION"
if [ "$PG_MAJOR" -ge 14 ]; then
  pass "Version $PG_MAJOR ≥ 14"
else
  fail "Version $PG_MAJOR < 14 — upgrade required"
fi

# ─── 2. postgresql.conf settings ─────────────────────────────────────────────
section "2. postgresql.conf Settings"

check_setting() {
  local name="$1" expected="$2" op="${3:-eq}"  # op: eq | gte
  local actual
  actual=$(psql_su -c "SHOW $name;" | tr -d '[:space:]')
  info "$name = $actual"
  if [ "$op" = "gte" ]; then
    if [ "$actual" -ge "$expected" ] 2>/dev/null; then
      pass "$name ≥ $expected"
    else
      fail "$name = $actual (required: ≥ $expected)"
    fi
  else
    if [ "$actual" = "$expected" ]; then
      pass "$name = $expected"
    else
      fail "$name = $actual (required: $expected)"
    fi
  fi
}

SPL=$(psql_su -c "SHOW shared_preload_libraries;" | tr -d '[:space:]')
info "shared_preload_libraries = $SPL"
if echo "$SPL" | grep -q "pg_stat_statements"; then
  pass "shared_preload_libraries contains pg_stat_statements"
else
  fail "pg_stat_statements missing from shared_preload_libraries"
fi

PSS_TRACK=$(psql_su -c "SHOW pg_stat_statements.track;" | tr -d '[:space:]')
info "pg_stat_statements.track = $PSS_TRACK"
if [ "$PSS_TRACK" = "all" ]; then
  pass "pg_stat_statements.track = all"
else
  fail "pg_stat_statements.track = $PSS_TRACK (required: all)"
fi

TRACK_IO=$(psql_su -c "SHOW track_io_timing;" | tr -d '[:space:]')
info "track_io_timing = $TRACK_IO"
[ "$TRACK_IO" = "on" ] && pass "track_io_timing = on" || fail "track_io_timing = $TRACK_IO (required: on)"

QS_RAW=$(psql_su -c "SHOW track_activity_query_size;" | tr -d '[:space:]')
QS=$(psql_su -c "SELECT setting FROM pg_settings WHERE name='track_activity_query_size';" | tr -d '[:space:]')
info "track_activity_query_size = $QS_RAW ($QS bytes)"
if [ "$QS" -ge 4096 ] 2>/dev/null; then
  pass "track_activity_query_size = $QS bytes (≥ 4096)"
else
  fail "track_activity_query_size = $QS bytes (required: ≥ 4096)"
fi

# ─── 3. pg_stat_statements extension ─────────────────────────────────────────
section "3. pg_stat_statements Extension"

DB_EXISTS=$(psql_su -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" | tr -d '[:space:]')
if [ "$DB_EXISTS" != "1" ]; then
  fail "Database '$DB_NAME' does not exist"
else
  pass "Database '$DB_NAME' exists"

  EXT=$(psql_su_db -c "SELECT extversion FROM pg_extension WHERE extname='pg_stat_statements';" | tr -d '[:space:]')
  if [ -n "$EXT" ]; then
    pass "pg_stat_statements extension installed (v$EXT)"
  else
    fail "pg_stat_statements extension not installed in '$DB_NAME'"
  fi

  PSS_COUNT=$(psql_su_db -c "SELECT COUNT(*) FROM pg_stat_statements;" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$PSS_COUNT" ]; then
    pass "pg_stat_statements view accessible ($PSS_COUNT rows)"
  else
    fail "pg_stat_statements view not accessible"
  fi
fi

# ─── 4. Monitoring user ───────────────────────────────────────────────────────
section "4. Monitoring User: $DB_MONITOR_USER"

USER_EXISTS=$(psql_su -c "SELECT 1 FROM pg_roles WHERE rolname='$DB_MONITOR_USER';" | tr -d '[:space:]')
if [ "$USER_EXISTS" != "1" ]; then
  fail "User '$DB_MONITOR_USER' does not exist"
else
  pass "User '$DB_MONITOR_USER' exists"

  has_role() {
    psql_su -c "
      SELECT 1 FROM pg_auth_members am
      JOIN pg_roles r  ON r.oid  = am.member
      JOIN pg_roles mr ON mr.oid = am.roleid
      WHERE r.rolname = '$DB_MONITOR_USER' AND mr.rolname = '$1';
    " | tr -d '[:space:]'
  }

  if [ "$(has_role pg_monitor)" = "1" ]; then
    pass "Role pg_monitor granted"
  else
    fail "Role pg_monitor NOT granted"
  fi

  if [ "$(has_role pg_read_all_stats)" = "1" ]; then
    pass "Role pg_read_all_stats granted"
  else
    fail "Role pg_read_all_stats NOT granted"
  fi
fi

# ─── 5. Schema & table permissions ───────────────────────────────────────────
section "5. Schema & Table Permissions (database: $DB_NAME)"

if [ "$DB_EXISTS" = "1" ] && [ "$USER_EXISTS" = "1" ]; then
  USAGE=$(psql_su_db -c "
    SELECT has_schema_privilege('$DB_MONITOR_USER', 'public', 'USAGE');
  " | tr -d '[:space:]')
  [ "$USAGE" = "t" ] && pass "USAGE on schema public granted" || fail "USAGE on schema public NOT granted"

  SEL=$(psql_su_db -c "
    SELECT COUNT(*) FROM information_schema.role_table_grants
    WHERE grantee = '$DB_MONITOR_USER' AND privilege_type = 'SELECT'
      AND table_schema = 'public';
  " | tr -d '[:space:]')
  if [ "$SEL" -gt 0 ] 2>/dev/null; then
    pass "SELECT granted on $SEL table(s) in schema public"
  else
    fail "SELECT NOT granted on any tables in schema public"
  fi
fi

# ─── 6. Connectivity check ────────────────────────────────────────────────────
section "6. Connectivity (localhost)"

PG_HBA=$(sudo cat "$(psql_su -c "SHOW hba_file;" | tr -d '[:space:]')" 2>/dev/null)
if echo "$PG_HBA" | grep -qE "^host\s+all\s+all\s+(127\.0\.0\.1/32|::1/128)"; then
  pass "pg_hba.conf allows TCP connections from localhost"
else
  warn "No explicit localhost TCP entry found in pg_hba.conf — verify manually"
fi

if echo "$PG_HBA" | grep -qE "scram-sha-256|md5"; then
  pass "Password authentication (scram-sha-256 or md5) configured"
else
  warn "No password auth method detected in pg_hba.conf"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════${RESET}"
TOTAL=$((PASS + FAIL + WARN))
echo -e "  ${GREEN}${PASS} passed${RESET}  |  ${RED}${FAIL} failed${RESET}  |  ${YELLOW}${WARN} warnings${RESET}  (${TOTAL} checks)"
echo -e "${BOLD}══════════════════════════════════════════════════════════${RESET}"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n  ${RED}✘ Not ready.${RESET} Run setup-pg-observability.sh to fix the issues above."
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo -e "\n  ${YELLOW}⚠ Ready with warnings.${RESET} Review warnings before connecting Alloy."
else
  echo -e "\n  ${GREEN}✔ All checks passed.${RESET} PostgreSQL is ready for Grafana DB Observability."
fi
