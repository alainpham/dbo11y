#!/usr/bin/env bash
# grafana/deploy-alloy-config.sh
# Deploys config.alloy from this repo to /etc/alloy/config.alloy on the current machine
# and restarts the Alloy service.
#
# Must be run on the target server (env file and config must already be present):
#   ssh <host> 'bash -s' < grafana/deploy-alloy-config.sh
#
# Or with a full remote deploy in one step:
#   rsync -az grafana/ <host>:~/dbo11y/grafana/
#   ssh <host> 'bash -s' < grafana/deploy-alloy-config.sh

set -euo pipefail

if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR="${SCRIPT_DIR:-$HOME/dbo11y/grafana}"
fi
ENV_FILE="$SCRIPT_DIR/.env.alloy"
SRC_CONFIG="$SCRIPT_DIR/config.alloy"
DEST_CONFIG="/etc/alloy/config.alloy"

info() { echo "▶  $*"; }
ok()   { echo "✔  $*"; }
die()  { echo "✘  $*" >&2; exit 1; }

# ─── Load env file ────────────────────────────────────────────────────────────
[ -f "$ENV_FILE" ] || die ".env.alloy not found at $ENV_FILE
  Copy the example and fill in your values:
    cp grafana/.env.alloy.example grafana/.env.alloy"

[ -f "$SRC_CONFIG" ] || die "config.alloy not found at $SRC_CONFIG"

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

# ─── Validate required vars ───────────────────────────────────────────────────
required_vars=(
  GCLOUD_HOSTED_METRICS_URL
  GCLOUD_HOSTED_METRICS_ID
  GCLOUD_HOSTED_LOGS_URL
  GCLOUD_HOSTED_LOGS_ID
  GCLOUD_RW_API_KEY
  POSTGRES_DSN
)

for var in "${required_vars[@]}"; do
  [ -n "${!var:-}" ] || die "Required variable $var is not set in $ENV_FILE"
done

# ─── Copy config ──────────────────────────────────────────────────────────────
[ -d /etc/alloy ] || die "/etc/alloy directory not found — is Alloy installed? Run deploy-alloy.sh first."

info "Copying config.alloy to $DEST_CONFIG…"
sudo cp "$SRC_CONFIG" "$DEST_CONFIG"
sudo chown root:alloy "$DEST_CONFIG"
sudo chmod 640 "$DEST_CONFIG"
ok "Config deployed to $DEST_CONFIG"

# ─── Write Postgres DSN secret file (read by local.file in config.alloy) ─────
PG_SECRET_FILE="/var/lib/alloy/postgres_secret_crophealth"
info "Writing PostgreSQL DSN secret to $PG_SECRET_FILE…"
echo -n "${POSTGRES_DSN}" | sudo tee "$PG_SECRET_FILE" > /dev/null
sudo chown alloy:alloy "$PG_SECRET_FILE"
sudo chmod 600 "$PG_SECRET_FILE"
ok "PostgreSQL secret file written"

# ─── Write environment + flags to Alloy systemd override ─────────────────────
# CUSTOM_ARGS enables public-preview components (database_observability.postgres).
# Alloy reads env vars from the drop-in so sys.env() calls in config.alloy work.
ALLOY_ENV_DIR="/etc/systemd/system/alloy.service.d"
ALLOY_ENV_FILE="$ALLOY_ENV_DIR/env.conf"

# Set CUSTOM_ARGS in /etc/default/alloy (the canonical EnvironmentFile for Alloy on Debian).
# This is necessary because /etc/default/alloy is loaded after our systemd drop-in,
# so setting CUSTOM_ARGS in the drop-in would be overridden back to "".
info "Enabling --stability.level=public-preview in /etc/default/alloy…"
sudo sed -i 's|^CUSTOM_ARGS=.*|CUSTOM_ARGS="--stability.level=public-preview"|' /etc/default/alloy
ok "CUSTOM_ARGS set"

info "Writing environment variables to $ALLOY_ENV_FILE…"
sudo mkdir -p "$ALLOY_ENV_DIR"
sudo tee "$ALLOY_ENV_FILE" > /dev/null <<EOF
[Service]
Environment="GCLOUD_HOSTED_METRICS_URL=${GCLOUD_HOSTED_METRICS_URL}"
Environment="GCLOUD_HOSTED_METRICS_ID=${GCLOUD_HOSTED_METRICS_ID}"
Environment="GCLOUD_HOSTED_LOGS_URL=${GCLOUD_HOSTED_LOGS_URL}"
Environment="GCLOUD_HOSTED_LOGS_ID=${GCLOUD_HOSTED_LOGS_ID}"
Environment="GCLOUD_RW_API_KEY=${GCLOUD_RW_API_KEY}"
EOF
sudo chmod 600 "$ALLOY_ENV_FILE"
ok "Environment file written"

# ─── Restart Alloy ────────────────────────────────────────────────────────────
info "Reloading systemd and restarting Alloy…"
sudo systemctl stop alloy 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl reset-failed alloy 2>/dev/null || true
sudo systemctl start alloy
sleep 3
sudo systemctl is-active alloy > /dev/null || die "Alloy failed to start — check: journalctl -u alloy -n 50"
ok "Alloy restarted successfully"

echo ""
echo "════════════════════════════════════════════════"
echo " Alloy config deployed and service restarted"
echo "════════════════════════════════════════════════"
echo "  Config  : $DEST_CONFIG"
echo "  Env     : $ALLOY_ENV_FILE"
echo "  Status  : $(sudo systemctl is-active alloy)"
echo ""
echo "  Logs    : journalctl -u alloy -f"
