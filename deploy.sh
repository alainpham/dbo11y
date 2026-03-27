#!/usr/bin/env bash
# deploy.sh — Build and deploy Smart Farming Crop Health Tracker to a remote server via SSH
# Usage: ./deploy.sh [ssh-host]   (default host: v8l)

set -euo pipefail

HOST="${1:-v8l}"
REMOTE_DIR="~/dbo11y"
DB_NAME="crophealth"
DB_USER="farmapp"           # application user (read/write)
DB_PASS="farmapp_password"
DB_MONITOR_USER="db-o11y"   # dedicated observability user for Grafana Alloy (read-only)
DB_MONITOR_PASS="db_o11y_password"
APP_PORT="3000"

info()  { echo "▶  $*"; }
ok()    { echo "✔  $*"; }
die()   { echo "✘  $*" >&2; exit 1; }

# ─── 1. Verify SSH connectivity ───────────────────────────────────────────────
info "Connecting to $HOST…"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "echo ok" > /dev/null \
  || die "Cannot reach $HOST. Check your SSH config."
ok "Connected to $HOST"

# ─── 2. Sync project files ────────────────────────────────────────────────────
info "Syncing project files to $HOST:$REMOTE_DIR…"
rsync -az --exclude='node_modules' --exclude='.env' \
  "$(dirname "$0")/" "$HOST:$REMOTE_DIR/"
ok "Files synced"

# ─── 3. Remote setup ──────────────────────────────────────────────────────────
info "Running remote setup on $HOST…"

ssh "$HOST" bash <<EOF
set -euo pipefail

# ── 3a. Install PostgreSQL if missing ────────────────────────────────────────
if ! dpkg -l postgresql 2>/dev/null | grep -q '^ii'; then
  echo "  Installing PostgreSQL…"
  sudo apt-get update -qq
  sudo apt-get install -y postgresql postgresql-contrib
  sudo systemctl enable --now postgresql
else
  echo "  PostgreSQL already installed."
fi

# ── 3b. Install Node.js (v20 via NodeSource) if missing ──────────────────────
if ! command -v node &>/dev/null; then
  echo "  Installing Node.js 20…"
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
else
  echo "  Node.js \$(node --version) already installed."
fi

# ── 3c. Create app DB user (idempotent) ──────────────────────────────────────
echo "  Ensuring app user '$DB_USER' exists…"
sudo -u postgres psql -tc \
  "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" \
  | grep -q 1 \
  || sudo -u postgres psql -c \
       "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"

# ── 3d. Create observability user (idempotent) ────────────────────────────────
echo "  Ensuring observability user '$DB_MONITOR_USER' exists…"
sudo -u postgres psql -tc \
  "SELECT 1 FROM pg_roles WHERE rolname='$DB_MONITOR_USER'" \
  | grep -q 1 \
  || sudo -u postgres psql -c \
       "CREATE USER \"$DB_MONITOR_USER\" WITH PASSWORD '$DB_MONITOR_PASS' CONNECTION LIMIT 60;"

# ── 3e. Create database (idempotent) ─────────────────────────────────────────
echo "  Ensuring database '$DB_NAME' exists…"
sudo -u postgres psql -tc \
  "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" \
  | grep -q 1 \
  || sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"

sudo -u postgres psql -c \
  "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" > /dev/null

# ── 3f. Run schema + seed (copy to /tmp so postgres user can read them) ───────
echo "  Applying schema…"
cp $REMOTE_DIR/db/init.sql /tmp/init.sql
chmod 644 /tmp/init.sql
sudo -u postgres psql -d "$DB_NAME" -f /tmp/init.sql > /dev/null

echo "  Seeding data…"
cp $REMOTE_DIR/db/seed.sql /tmp/seed.sql
chmod 644 /tmp/seed.sql
sudo -u postgres psql -d "$DB_NAME" -f /tmp/seed.sql > /dev/null

# ── 3g. Write .env if it doesn't exist ───────────────────────────────────────
if [ ! -f $REMOTE_DIR/.env ]; then
  echo "  Writing .env…"
  cat > $REMOTE_DIR/.env <<ENV
DB_HOST=localhost
DB_PORT=5432
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
PORT=$APP_PORT
ENV
fi

# ── 3h. Install npm dependencies ─────────────────────────────────────────────
echo "  Installing npm dependencies…"
cd $REMOTE_DIR
npm install --silent

# ── 3i. Create systemd service (idempotent) ───────────────────────────────────
echo "  Setting up systemd service…"
NODE_BIN=\$(which node)
APP_DIR=\$(realpath $REMOTE_DIR)
APP_USER=\$(whoami)
sudo tee /etc/systemd/system/crophealth.service > /dev/null <<SERVICE
[Unit]
Description=Smart Farming Crop Health Tracker
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=\${APP_USER}
WorkingDirectory=\${APP_DIR}
EnvironmentFile=\${APP_DIR}/.env
ExecStart=\${NODE_BIN} server.js
Restart=always
RestartSec=5
StandardOutput=append:\${APP_DIR}/app.log
StandardError=append:\${APP_DIR}/app.log

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable crophealth
sudo systemctl restart crophealth

# ── 3j. Health check ─────────────────────────────────────────────────────────
sleep 3
curl -sf "http://localhost:$APP_PORT/api/dashboard" > /dev/null \
  && echo "  Health check passed." \
  || { echo "  Health check FAILED. Check $REMOTE_DIR/app.log"; exit 1; }
EOF

ok "Deployment complete!"
echo ""
echo "  Dashboard → http://$(ssh "$HOST" hostname -I | awk '{print $1}'):$APP_PORT"
echo "  Logs      → ssh $HOST 'tail -f $REMOTE_DIR/app.log'"
