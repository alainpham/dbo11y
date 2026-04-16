require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// ─── Database ─────────────────────────────────────────────────────────────────
const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'crophealth',
  user:     process.env.DB_USER     || 'farmapp',
  password: process.env.DB_PASSWORD || 'farmapp_password',
});

pool.connect()
  .then(client => { console.log('Connected to PostgreSQL'); client.release(); })
  .catch(err => console.warn('Initial DB connection failed (will retry on first request):', err.message));

// ─── Middleware ───────────────────────────────────────────────────────────────
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ─── Routes: Farms ────────────────────────────────────────────────────────────
app.get('/api/farms', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT * FROM farms ORDER BY name'
    );
    res.json(rows);
  } catch (err) {
    console.error('GET /api/farms:', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/farms', async (req, res) => {
  try {
    const { name, location, owner, latitude, longitude } = req.body;
    if (!name) return res.status(400).json({ error: 'name is required' });
    const { rows } = await pool.query(
      'INSERT INTO farms (name, location, owner, latitude, longitude) VALUES ($1,$2,$3,$4,$5) RETURNING *',
      [name, location, owner, latitude, longitude]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error('POST /api/farms:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Routes: Fields ───────────────────────────────────────────────────────────
app.get('/api/farms/:farmId/fields', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT * FROM fields WHERE farm_id = $1 ORDER BY name',
      [req.params.farmId]
    );
    res.json(rows);
  } catch (err) {
    console.error('GET /api/farms/:farmId/fields:', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/fields', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT f.*, fa.name AS farm_name
      FROM fields f
      JOIN farms fa ON fa.id = f.farm_id
      ORDER BY fa.name, f.name
    `);
    res.json(rows);
  } catch (err) {
    console.error('GET /api/fields:', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/fields', async (req, res) => {
  try {
    const { farm_id, name, area_hectares, crop_type, planting_date, expected_harvest } = req.body;
    if (!farm_id || !name) return res.status(400).json({ error: 'farm_id and name are required' });
    const { rows } = await pool.query(
      `INSERT INTO fields (farm_id, name, area_hectares, crop_type, planting_date, expected_harvest)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [farm_id, name, area_hectares, crop_type, planting_date, expected_harvest]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error('POST /api/fields:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Routes: Readings ────────────────────────────────────────────────────────
app.get('/api/fields/:fieldId/readings', async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit || '30'), 200);
    const { rows } = await pool.query(
      `SELECT * FROM crop_health_readings
       WHERE field_id = $1
       ORDER BY recorded_at DESC
       LIMIT $2`,
      [req.params.fieldId, limit]
    );
    res.json(rows);
  } catch (err) {
    console.error('GET /api/fields/:fieldId/readings:', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/readings', async (req, res) => {
  try {
    const {
      field_id, sensor_id, health_score, ndvi,
      soil_moisture, soil_ph, soil_temp_c,
      air_temp_c, humidity_pct, rainfall_mm,
      pest_risk_level, disease_risk_level, notes
    } = req.body;

    if (!field_id) return res.status(400).json({ error: 'field_id is required' });

    const { rows } = await pool.query(
      `INSERT INTO crop_health_readings
         (field_id, sensor_id, health_score, ndvi,
          soil_moisture, soil_ph, soil_temp_c,
          air_temp_c, humidity_pct, rainfall_mm,
          pest_risk_level, disease_risk_level, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       RETURNING *`,
      [field_id, sensor_id, health_score, ndvi,
       soil_moisture, soil_ph, soil_temp_c,
       air_temp_c, humidity_pct, rainfall_mm,
       pest_risk_level, disease_risk_level, notes]
    );

    // Auto-generate alerts based on thresholds
    const reading = rows[0];
    const autoAlerts = [];

    if (reading.soil_moisture !== null && reading.soil_moisture < 15) {
      autoAlerts.push([field_id, 'drought', 'critical', `Soil moisture critically low at ${reading.soil_moisture}%`]);
    } else if (reading.soil_moisture !== null && reading.soil_moisture < 25) {
      autoAlerts.push([field_id, 'drought', 'medium', `Soil moisture below recommended threshold: ${reading.soil_moisture}%`]);
    }
    if (reading.pest_risk_level >= 3) {
      autoAlerts.push([field_id, 'pest', reading.pest_risk_level === 4 ? 'critical' : 'high', `High pest risk detected (level ${reading.pest_risk_level})`]);
    }
    if (reading.disease_risk_level >= 3) {
      autoAlerts.push([field_id, 'disease', reading.disease_risk_level === 4 ? 'critical' : 'high', `High disease risk detected (level ${reading.disease_risk_level})`]);
    }

    for (const [fid, type, severity, message] of autoAlerts) {
      await pool.query(
        'INSERT INTO alerts (field_id, type, severity, message) VALUES ($1,$2,$3,$4)',
        [fid, type, severity, message]
      );
    }

    res.status(201).json({ reading: rows[0], alerts_generated: autoAlerts.length });
  } catch (err) {
    console.error('POST /api/readings:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Routes: Alerts ───────────────────────────────────────────────────────────
app.get('/api/alerts', async (req, res) => {
  try {
    const onlyOpen = req.query.open !== 'false';
    const { rows } = await pool.query(`
      SELECT a.*, fi.name AS field_name, fa.name AS farm_name
      FROM alerts a
      JOIN fields fi ON fi.id = a.field_id
      JOIN farms fa ON fa.id = fi.farm_id
      ${onlyOpen ? 'WHERE a.resolved = FALSE' : ''}
      ORDER BY
        CASE a.severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
        a.created_at DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error('GET /api/alerts:', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.patch('/api/alerts/:id/resolve', async (req, res) => {
  try {
    const { rows } = await pool.query(
      `UPDATE alerts SET resolved = TRUE, resolved_at = NOW()
       WHERE id = $1 AND resolved = FALSE
       RETURNING *`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Alert not found or already resolved' });
    res.json(rows[0]);
  } catch (err) {
    console.error('PATCH /api/alerts/:id/resolve:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Routes: Dashboard ───────────────────────────────────────────────────────
app.get('/api/dashboard', async (req, res) => {
  try {
    const [farmCount, fieldCount, openAlerts, avgHealth, recentReadings] = await Promise.all([
      pool.query('SELECT COUNT(*) FROM farms'),
      pool.query('SELECT COUNT(*) FROM fields'),
      pool.query(`
        SELECT severity, COUNT(*) AS count
        FROM alerts WHERE resolved = FALSE
        GROUP BY severity
      `),
      pool.query(`
        SELECT fi.id, fi.name AS field_name, fi.crop_type, fa.name AS farm_name,
               r.health_score, r.ndvi, r.soil_moisture, r.pest_risk_level, r.disease_risk_level, r.recorded_at
        FROM fields fi
        JOIN farms fa ON fa.id = fi.farm_id
        LEFT JOIN LATERAL (
          SELECT * FROM crop_health_readings
          WHERE field_id = fi.id
          ORDER BY recorded_at DESC LIMIT 1
        ) r ON TRUE
        ORDER BY r.health_score ASC NULLS LAST
      `),
      pool.query(`
        SELECT r.*, fi.name AS field_name, fa.name AS farm_name
        FROM crop_health_readings r
        JOIN fields fi ON fi.id = r.field_id
        JOIN farms fa ON fa.id = fi.farm_id
        ORDER BY r.recorded_at DESC
        LIMIT 10
      `)
    ]);

    const alertCounts = { critical: 0, high: 0, medium: 0, low: 0 };
    for (const row of openAlerts.rows) alertCounts[row.severity] = parseInt(row.count);

    res.json({
      farm_count:      parseInt(farmCount.rows[0].count),
      field_count:     parseInt(fieldCount.rows[0].count),
      open_alerts:     alertCounts,
      field_health:    avgHealth.rows,
      recent_readings: recentReadings.rows,
    });
  } catch (err) {
    console.error('GET /api/dashboard:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Start ────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`Smart Farming dashboard running at http://localhost:${PORT}`);
});
