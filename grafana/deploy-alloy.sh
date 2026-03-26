#!/usr/bin/env bash
# grafana/deploy-alloy.sh
# Installs Grafana Alloy on the current machine using credentials from .env.alloy.
#
# Usage (local):
#   bash grafana/deploy-alloy.sh
#
# Usage (remote):
#   ssh <host> 'bash -s' < grafana/deploy-alloy.sh
#   (requires grafana/.env.alloy to already exist on the remote host, or pipe it first)
#
# To deploy env file + script in one step:
#   scp grafana/.env.alloy <host>:~/dbo11y/grafana/.env.alloy
#   ssh <host> 'bash -s' < grafana/deploy-alloy.sh

set -euo pipefail

if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR="${SCRIPT_DIR:-$HOME/dbo11y/grafana}"
fi
ENV_FILE="$SCRIPT_DIR/.env.alloy"

die() { echo "✘  $*" >&2; exit 1; }

# ─── Load env file ────────────────────────────────────────────────────────────
[ -f "$ENV_FILE" ] || die ".env.alloy not found at $ENV_FILE
  Copy the example and fill in your values:
    cp grafana/.env.alloy.example grafana/.env.alloy"

# shellcheck source=.env.alloy.example
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# ─── Validate required vars ───────────────────────────────────────────────────
required_vars=(
  ARCH
  GCLOUD_HOSTED_METRICS_URL
  GCLOUD_HOSTED_METRICS_ID
  GCLOUD_HOSTED_LOGS_URL
  GCLOUD_HOSTED_LOGS_ID
  GCLOUD_SCRAPE_INTERVAL
  GCLOUD_RW_API_KEY
)

for var in "${required_vars[@]}"; do
  [ -n "${!var:-}" ] || die "Required variable $var is not set in $ENV_FILE"
done

echo "▶  Installing Grafana Alloy (arch: $ARCH)…"

# ─── Run the official Grafana Alloy installer ─────────────────────────────────
ARCH="$ARCH" \
GCLOUD_HOSTED_METRICS_URL="$GCLOUD_HOSTED_METRICS_URL" \
GCLOUD_HOSTED_METRICS_ID="$GCLOUD_HOSTED_METRICS_ID" \
GCLOUD_SCRAPE_INTERVAL="$GCLOUD_SCRAPE_INTERVAL" \
GCLOUD_HOSTED_LOGS_URL="$GCLOUD_HOSTED_LOGS_URL" \
GCLOUD_HOSTED_LOGS_ID="$GCLOUD_HOSTED_LOGS_ID" \
GCLOUD_RW_API_KEY="$GCLOUD_RW_API_KEY" \
  /bin/sh -c "$(curl -fsSL https://storage.googleapis.com/cloud-onboarding/alloy/scripts/install-linux.sh)"

echo "✔  Grafana Alloy installed"
