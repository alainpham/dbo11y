#!/usr/bin/env bash
# k6/deploy-k6-cron.sh
# Installs k6 on the remote server and sets up a cron job that runs the
# traffic script every 15 minutes for 5 minutes, generating ~2-3 req/s of
# background traffic against the app.
#
# Usage:
#   bash k6/deploy-k6-cron.sh [ssh-host]   (default: v8l)

set -euo pipefail

HOST="${1:-v8l}"
REMOTE_DIR="~/dbo11y"
APP_PORT="${APP_PORT:-3000}"
K6_DURATION="${K6_DURATION:-5m}"
CRON_SCHEDULE="${CRON_SCHEDULE:-*/15 * * * *}"

info() { echo "▶  $*"; }
ok()   { echo "✔  $*"; }
die()  { echo "✘  $*" >&2; exit 1; }

# ─── 1. Verify SSH connectivity ───────────────────────────────────────────────
info "Connecting to $HOST…"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "echo ok" > /dev/null \
  || die "Cannot reach $HOST. Check your SSH config."
ok "Connected to $HOST"

# ─── 2. Sync k6 scripts ───────────────────────────────────────────────────────
info "Syncing k6 scripts to $HOST:$REMOTE_DIR/k6/…"
rsync -az "$(dirname "$0")/" "$HOST:$REMOTE_DIR/k6/"
ok "Scripts synced"

# ─── 3. Install k6 if missing ─────────────────────────────────────────────────
info "Checking k6 installation…"
ssh "$HOST" bash <<'REMOTE'
set -euo pipefail
if command -v k6 &>/dev/null; then
  echo "  k6 $(k6 version) already installed."
else
  echo "  Installing k6…"
  sudo gpg -k 2>/dev/null
  curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
    | sudo tee /etc/apt/sources.list.d/k6.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y k6
  echo "  k6 $(k6 version) installed."
fi
REMOTE
ok "k6 ready"

# ─── 4. Detect the server's local IP for BASE_URL ─────────────────────────────
SERVER_IP=$(ssh "$HOST" "hostname -I | awk '{print \$1}'" | tr -d '[:space:]')
BASE_URL="http://${SERVER_IP}:${APP_PORT}"
info "App URL: $BASE_URL"

# ─── 5. Install cron job ──────────────────────────────────────────────────────
CRON_CMD="k6 run --duration=${K6_DURATION} --quiet --env BASE_URL=${BASE_URL} ${REMOTE_DIR}/k6/traffic.js >> ${REMOTE_DIR}/k6/k6.log 2>&1"
CRON_ENTRY="${CRON_SCHEDULE} ${CRON_CMD}"
CRON_MARKER="# k6-crophealth-traffic"

info "Installing cron job ($CRON_SCHEDULE)…"
ssh "$HOST" bash <<REMOTE
set -euo pipefail

# Remove any previous entry for this job, then append the new one
( crontab -l 2>/dev/null | grep -v "$CRON_MARKER" ; echo "${CRON_ENTRY} ${CRON_MARKER}" ) | crontab -
echo "  Cron job installed:"
crontab -l | grep "$CRON_MARKER"
REMOTE
ok "Cron job installed"

# ─── 6. Smoke test — run once immediately ─────────────────────────────────────
info "Running a 15-second smoke test…"
ssh "$HOST" "k6 run --duration=15s --quiet --env BASE_URL=${BASE_URL} ${REMOTE_DIR}/k6/traffic.js" \
  && ok "Smoke test passed" \
  || die "Smoke test failed — check the app is running at ${BASE_URL}"

echo ""
echo "══════════════════════════════════════════════════════"
echo " k6 background traffic deployed"
echo "══════════════════════════════════════════════════════"
echo "  Host     : $HOST"
echo "  App URL  : $BASE_URL"
echo "  Schedule : $CRON_SCHEDULE (every 15 min, runs for $K6_DURATION)"
echo "  Logs     : ssh $HOST 'tail -f $REMOTE_DIR/k6/k6.log'"
echo ""
echo "  To remove the cron job:"
echo "    ssh $HOST 'crontab -l | grep -v k6-crophealth-traffic | crontab -'"
