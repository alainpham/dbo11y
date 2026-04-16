/**
 * k6 background traffic script — Smart Farming Crop Health Tracker
 *
 * Generates ~2-3 req/s of realistic mixed read/write traffic against the app API.
 *
 * Usage:
 *   k6 run k6/traffic.js
 *   BASE_URL=http://192.168.122.20:3000 k6 run k6/traffic.js
 *
 * To run continuously in the background:
 *   k6 run --duration=0 k6/traffic.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { randomIntBetween, randomItem } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

// ─── Config ──────────────────────────────────────────────────────────────────
const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export const options = {
  scenarios: {
    background_traffic: {
      executor:        'constant-arrival-rate',
      rate:            3,          // requests per second
      timeUnit:        '1s',
      duration:        '10m',      // default run duration; override with --duration
      preAllocatedVUs: 5,
      maxVUs:          10,
    },
  },
  thresholds: {
    http_req_failed:   ['rate<0.05'],   // less than 5% errors
    http_req_duration: ['p(95)<2000'],  // 95% of requests under 2s
  },
};

// ─── Seed data assumptions (match db/seed.sql) ────────────────────────────────
const FARM_IDS  = [1, 2, 3];
const FIELD_IDS = [1, 2, 3, 4, 5, 6];

// ─── Helpers ─────────────────────────────────────────────────────────────────
const headers = { 'Content-Type': 'application/json' };

function get(path) {
  const res = http.get(`${BASE_URL}${path}`);
  check(res, { [`GET ${path} → 200`]: r => r.status === 200 });
  return res;
}

function post(path, body) {
  const res = http.post(`${BASE_URL}${path}`, JSON.stringify(body), { headers });
  check(res, { [`POST ${path} → 201`]: r => r.status === 201 });
  return res;
}

function patch(path) {
  const res = http.patch(`${BASE_URL}${path}`, null, { headers });
  // 200 = resolved, 404 = already resolved — both acceptable
  check(res, { [`PATCH ${path} → 2xx/404`]: r => r.status === 200 || r.status === 404 });
  return res;
}

// ─── Weighted scenario pool ───────────────────────────────────────────────────
// Each entry: [weight, fn]. Total weight = 100.
const scenarios = [
  // ── Reads (heavy) ──────────────────────────────────────────────────────────
  [20, () => get('/api/dashboard')],
  [15, () => get('/api/fields')],
  [12, () => get('/api/farms')],
  [10, () => get(`/api/fields/${randomItem(FIELD_IDS)}/readings?limit=20`)],
  [10, () => get(`/api/farms/${randomItem(FARM_IDS)}/fields`)],
  [8,  () => get('/api/alerts')],
  [5,  () => get('/api/alerts?open=false')],

  // ── Writes (light) ─────────────────────────────────────────────────────────
  [15, () => {
    const fieldId = randomItem(FIELD_IDS);
    post('/api/readings', {
      field_id:           fieldId,
      health_score:       randomIntBetween(40, 98),
      ndvi:               parseFloat((Math.random() * 1.2 - 0.2).toFixed(3)),
      soil_moisture:      randomIntBetween(10, 55),
      soil_ph:            parseFloat((6.0 + Math.random() * 1.5).toFixed(1)),
      soil_temp_c:        randomIntBetween(12, 30),
      air_temp_c:         randomIntBetween(15, 38),
      humidity_pct:       randomIntBetween(30, 80),
      rainfall_mm:        randomIntBetween(0, 15),
      pest_risk_level:    randomIntBetween(0, 3),
      disease_risk_level: randomIntBetween(0, 2),
    });
  }],

  // ── Resolve a random open alert occasionally ───────────────────────────────
  [5, () => {
    const res = get('/api/alerts');
    if (res.status !== 200) return;
    try {
      const alerts = JSON.parse(res.body);
      if (alerts.length > 0) {
        const alert = randomItem(alerts);
        patch(`/api/alerts/${alert.id}/resolve`);
      }
    } catch (_) { /* ignore parse errors */ }
  }],
];

// Build cumulative weight table once
const cumulative = [];
let total = 0;
for (const [w, fn] of scenarios) {
  total += w;
  cumulative.push([total, fn]);
}

function pickScenario() {
  const roll = randomIntBetween(1, total);
  for (const [threshold, fn] of cumulative) {
    if (roll <= threshold) return fn;
  }
  return cumulative[cumulative.length - 1][1];
}

// ─── Main ─────────────────────────────────────────────────────────────────────
export default function () {
  pickScenario()();
  sleep(randomIntBetween(0, 1)); // small jitter to spread requests naturally
}
