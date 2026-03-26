-- Smart Farming Crop Health Tracker — Schema
-- Run: sudo -u postgres psql -d crophealth -f db/init.sql

BEGIN;

-- Grant schema permissions
GRANT ALL ON SCHEMA public TO farmapp;

-- ─── Farms ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS farms (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(120) NOT NULL,
    location    VARCHAR(200),
    owner       VARCHAR(100),
    latitude    NUMERIC(9, 6),
    longitude   NUMERIC(9, 6),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Fields ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fields (
    id              SERIAL PRIMARY KEY,
    farm_id         INTEGER NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    name            VARCHAR(120) NOT NULL,
    area_hectares   NUMERIC(8, 2),
    crop_type       VARCHAR(80),           -- e.g. 'Wheat', 'Corn', 'Soybean'
    planting_date   DATE,
    expected_harvest DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Sensors ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sensors (
    id          SERIAL PRIMARY KEY,
    field_id    INTEGER NOT NULL REFERENCES fields(id) ON DELETE CASCADE,
    serial_no   VARCHAR(60) UNIQUE NOT NULL,
    type        VARCHAR(60),               -- 'soil', 'aerial', 'weather'
    installed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    active      BOOLEAN NOT NULL DEFAULT TRUE
);

-- ─── Crop Health Readings ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crop_health_readings (
    id              SERIAL PRIMARY KEY,
    field_id        INTEGER NOT NULL REFERENCES fields(id) ON DELETE CASCADE,
    sensor_id       INTEGER REFERENCES sensors(id) ON DELETE SET NULL,
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Vegetation & growth
    health_score    NUMERIC(4, 1) CHECK (health_score BETWEEN 0 AND 100),
    ndvi            NUMERIC(5, 4) CHECK (ndvi BETWEEN -1 AND 1),  -- Normalized Difference Vegetation Index

    -- Soil conditions
    soil_moisture   NUMERIC(5, 2),    -- % volumetric water content
    soil_ph         NUMERIC(4, 2),
    soil_temp_c     NUMERIC(5, 2),

    -- Atmospheric
    air_temp_c      NUMERIC(5, 2),
    humidity_pct    NUMERIC(5, 2),
    rainfall_mm     NUMERIC(6, 2),

    -- Pest & disease risk (0=none, 1=low, 2=medium, 3=high, 4=critical)
    pest_risk_level SMALLINT CHECK (pest_risk_level BETWEEN 0 AND 4),
    disease_risk_level SMALLINT CHECK (disease_risk_level BETWEEN 0 AND 4),

    notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_readings_field_time
    ON crop_health_readings (field_id, recorded_at DESC);

-- ─── Alerts ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alerts (
    id          SERIAL PRIMARY KEY,
    field_id    INTEGER NOT NULL REFERENCES fields(id) ON DELETE CASCADE,
    type        VARCHAR(60) NOT NULL,       -- 'pest', 'disease', 'drought', 'frost', 'overwater'
    severity    VARCHAR(20) NOT NULL,       -- 'low', 'medium', 'high', 'critical'
    message     TEXT NOT NULL,
    resolved    BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alerts_open ON alerts (field_id) WHERE resolved = FALSE;

COMMIT;
