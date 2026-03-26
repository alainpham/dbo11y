# Smart Farming Crop Health Tracker — PoC Demo

A full-stack Node.js application for monitoring crop health across farms and fields, backed by PostgreSQL, with built-in support for Grafana Database Observability.

---

## Quickstart

### One-command full deploy

Runs all 6 steps below in sequence:

```bash
# Fill in Grafana Cloud credentials first
cp grafana/.env.alloy.example grafana/.env.alloy
# edit grafana/.env.alloy

./full-deploy.sh <ssh-host>
# example:
./full-deploy.sh v8s
```

---

### Step-by-step

### 1. Deploy the application

```bash
./deploy.sh <ssh-host>
# example:
./deploy.sh v8s
```

This will:
- Sync project files to the remote server
- Install PostgreSQL and Node.js if missing
- Create the app database and user (`farmapp`)
- Initialize the schema and seed sample data
- Install npm dependencies and start the server

The dashboard will be available at `http://<server-ip>:3000`.

---

### 2. Set up PostgreSQL for Grafana DB Observability

Run this on the target server to create the dedicated monitoring user (`db-o11y`) and apply all required PostgreSQL settings:

```bash
ssh <ssh-host> 'bash -s' < setup-pg-observability.sh
# example : 
ssh v8s 'bash -s' < setup-pg-observability.sh
```

To override defaults:

```bash
ssh <ssh-host> 'DB_NAME=mydb DB_MONITOR_USER=db-o11y DB_MONITOR_PASS=secret bash -s' < setup-pg-observability.sh
```

---

### 3. Verify observability requirements

```bash
ssh <ssh-host> 'bash -s' < check-pg-observability.sh
# example : 
ssh v8s 'bash -s' < check-pg-observability.sh
```

This is a read-only audit script — it makes no changes to the system.

---

### 4. Install Grafana Alloy on the server

Fill in your Grafana Cloud credentials first:

```bash
cp grafana/.env.alloy.example grafana/.env.alloy
# edit grafana/.env.alloy with your Grafana Cloud URLs, IDs, and API key
```

Then copy the env file to the server and run the installer:

```bash
rsync -az grafana/ <ssh-host>:~/dbo11y/grafana/
ssh <ssh-host> 'bash -s' < grafana/deploy-alloy.sh
# example : 
rsync -az grafana/ v8s:~/dbo11y/grafana/
ssh v8s 'bash -s' < grafana/deploy-alloy.sh
```

---

### 5. Deploy the Alloy config

Syncs `grafana/config.alloy` to `/etc/alloy/config.alloy`, injects credentials as systemd environment variables, and restarts Alloy:

```bash
rsync -az grafana/ <ssh-host>:~/dbo11y/grafana/
ssh <ssh-host> 'bash -s' < grafana/deploy-alloy-config.sh
# example : 
rsync -az grafana/ v8s:~/dbo11y/grafana/
ssh v8s 'bash -s' < grafana/deploy-alloy-config.sh
```

To verify Alloy is running and shipping data:

```bash
ssh <ssh-host> 'journalctl -u alloy -n 50'
```

---

### 6. Deploy k6 background traffic

Installs k6 on the server, runs a smoke test, and sets up a cron job that fires every 15 minutes generating ~2-3 req/s of realistic mixed traffic for 5 minutes:

```bash
bash k6/deploy-k6-cron.sh <ssh-host>
# example:
bash k6/deploy-k6-cron.sh v8s
```

To override defaults:

```bash
APP_PORT=3000 K6_DURATION=5m CRON_SCHEDULE="*/15 * * * *" bash k6/deploy-k6-cron.sh <ssh-host>
```

To run the traffic script once (no cron):

```bash
# Locally (requires k6 installed)
BASE_URL=http://<server-ip>:3000 k6 run --duration=2m k6/traffic.js

# Directly on the server
ssh <ssh-host> 'k6 run --duration=2m --env BASE_URL=http://localhost:3000 ~/dbo11y/k6/traffic.js'
# example:
ssh v8s 'k6 run --duration=2m --env BASE_URL=http://localhost:3000 ~/dbo11y/k6/traffic.js'
```

To follow the k6 logs on the server:

```bash
ssh <ssh-host> 'tail -f ~/dbo11y/k6/k6.log'
#example : 
ssh v8s 'tail -f ~/dbo11y/k6/k6.log'
```

To remove the cron job:

```bash
ssh <ssh-host> 'crontab -l | grep -v k6-crophealth-traffic | crontab -'
```

---

## Scripts

| Script | Description |
|---|---|
| `full-deploy.sh [host]` | **One-command full deploy** — runs all 6 steps in sequence |
| `deploy.sh [host]` | Deploy the full app stack to a remote server over SSH |
| `setup-pg-observability.sh` | Configure PostgreSQL for Grafana DB Observability (creates `db-o11y` user, enables `pg_stat_statements`, sets required parameters) |
| `check-pg-observability.sh` | Read-only audit of all Grafana DB Observability requirements |
| `grafana/deploy-alloy.sh` | Install Grafana Alloy on the server |
| `grafana/deploy-alloy-config.sh` | Deploy `config.alloy` to `/etc/alloy/` and restart Alloy |
| `k6/deploy-k6-cron.sh [host]` | Install k6 and set up a cron job for background traffic |

---

## Database Users

Two users are intentionally kept separate:

| User | Role | Purpose |
|---|---|---|
| `farmapp` | Owner | Application user — full read/write access to the `crophealth` database |
| `db-o11y` | Read-only | Grafana Alloy monitoring user — `pg_monitor`, `pg_read_all_stats`, `SELECT` only |

---

## Manual Setup (without deploy.sh)

### Install PostgreSQL on Ubuntu 24.04

```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable --now postgresql
```

### Create the app database and user

```bash
sudo -u postgres psql <<EOF
CREATE USER farmapp WITH PASSWORD 'farmapp_password';
CREATE DATABASE crophealth OWNER farmapp;
GRANT ALL PRIVILEGES ON DATABASE crophealth TO farmapp;
EOF
```

### Initialize and seed the database

```bash
cp db/init.sql /tmp/init.sql && cp db/seed.sql /tmp/seed.sql
sudo -u postgres psql -d crophealth -f /tmp/init.sql
sudo -u postgres psql -d crophealth -f /tmp/seed.sql
```

### Install Node.js and run the app

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
cp .env.example .env
npm install
npm start
```

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `crophealth` | Database name |
| `DB_USER` | `farmapp` | Application database user |
| `DB_PASSWORD` | `farmapp_password` | Application database password |
| `PORT` | `3000` | HTTP server port |

---

## Project Structure

```
.
├── deploy.sh                        # Remote deployment script
├── setup-pg-observability.sh        # Grafana DB Observability setup
├── check-pg-observability.sh        # Grafana DB Observability audit
├── package.json
├── server.js                        # Express backend + REST API
├── .env.example
├── db/
│   ├── init.sql                     # Schema creation
│   └── seed.sql                     # Sample data
├── grafana/
│   ├── config.alloy                 # Alloy pipeline config (no secrets)
│   ├── deploy-alloy.sh              # Install Grafana Alloy
│   ├── deploy-alloy-config.sh       # Deploy config + restart Alloy
│   ├── .env.alloy.example           # Credentials template
│   └── .env.alloy                   # Credentials (gitignored)
├── k6/
│   ├── traffic.js                   # k6 load test script (~2-3 req/s mixed traffic)
│   └── deploy-k6-cron.sh            # Install k6 + set up cron job on remote server
└── public/
    ├── index.html                   # Single-page dashboard
    ├── style.css
    └── app.js                       # Frontend logic
```

---

## API Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/farms` | List all farms |
| GET | `/api/farms/:id/fields` | List fields for a farm |
| GET | `/api/fields` | List all fields |
| GET | `/api/fields/:id/readings` | Get health readings for a field |
| POST | `/api/readings` | Submit a new health reading |
| GET | `/api/alerts` | List open alerts |
| PATCH | `/api/alerts/:id/resolve` | Resolve an alert |
| GET | `/api/dashboard` | Aggregated dashboard stats |
