#!/usr/bin/env bash
# full-deploy.sh — End-to-end deployment: app + observability + Alloy + k6
# Usage: ./full-deploy.sh [ssh-host]   (default: v8l)
#
# Prerequisites:
#   - SSH access to the target host
#   - grafana/.env.alloy filled in (copy from grafana/.env.alloy.example)

set -euo pipefail

HOST="${1:-v8l}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()    { echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "▶  $*"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
ok()      { echo "✔  $*"; }
die()     { echo ""; echo "✘  $*" >&2; exit 1; }

# ─── Pre-flight checks ────────────────────────────────────────────────────────
[ -f "$SCRIPT_DIR/grafana/.env.alloy" ] \
  || die "grafana/.env.alloy not found. Copy the example and fill in your credentials:
  cp grafana/.env.alloy.example grafana/.env.alloy"

# ─── Step 1: Deploy app stack ─────────────────────────────────────────────────
info "Step 1/6 — Deploy app stack to $HOST"
bash "$SCRIPT_DIR/deploy.sh" "$HOST"

# ─── Step 2: Configure PostgreSQL for DB Observability ────────────────────────
info "Step 2/6 — Configure PostgreSQL for Grafana DB Observability"
ssh "$HOST" 'bash -s' < "$SCRIPT_DIR/setup-pg-observability.sh"
ok "PostgreSQL observability configured"

# ─── Step 3: Verify observability requirements ────────────────────────────────
info "Step 3/6 — Verify observability requirements"
ssh "$HOST" 'bash -s' < "$SCRIPT_DIR/check-pg-observability.sh"

# ─── Step 4: Install Grafana Alloy ────────────────────────────────────────────
info "Step 4/6 — Install Grafana Alloy on $HOST"
rsync -az "$SCRIPT_DIR/grafana/" "$HOST:~/dbo11y/grafana/"
ssh "$HOST" 'bash -s' < "$SCRIPT_DIR/grafana/deploy-alloy.sh"

# ─── Step 5: Deploy Alloy config ──────────────────────────────────────────────
info "Step 5/6 — Deploy Alloy config and credentials"
rsync -az "$SCRIPT_DIR/grafana/" "$HOST:~/dbo11y/grafana/"
ssh "$HOST" 'bash -s' < "$SCRIPT_DIR/grafana/deploy-alloy-config.sh"

# ─── Step 6: Deploy k6 background traffic ────────────────────────────────────
info "Step 6/6 — Deploy k6 background traffic cron job"
bash "$SCRIPT_DIR/k6/deploy-k6-cron.sh" "$HOST"

# ─── Summary ──────────────────────────────────────────────────────────────────
SERVER_IP=$(ssh "$HOST" "hostname -I | awk '{print \$1}'" | tr -d '[:space:]')

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║           Full deployment complete!                  ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Host         : $HOST"
echo "║  Dashboard    : http://${SERVER_IP}:3000"
echo "║  App logs     : ssh $HOST 'tail -f ~/dbo11y/app.log'"
echo "║  Alloy logs   : ssh $HOST 'journalctl -u alloy -f'"
echo "║  k6 logs      : ssh $HOST 'tail -f ~/dbo11y/k6/k6.log'"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Run k6 test  : ssh $HOST 'BASE_URL=http://localhost:3000 k6 run ~/dbo11y/k6/traffic.js'"
echo "╚══════════════════════════════════════════════════════╝"
