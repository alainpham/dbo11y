-- Smart Farming Crop Health Tracker — Sample Data
-- Run: sudo -u postgres psql -d crophealth -f db/seed.sql

BEGIN;

-- Allow farmapp to use sequences and tables created by postgres
GRANT ALL ON ALL TABLES IN SCHEMA public TO farmapp;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO farmapp;

-- ─── Wipe existing data (safe for redeploy) ───────────────────────────────────
TRUNCATE alerts, crop_health_readings, sensors, fields, farms RESTART IDENTITY CASCADE;

-- ─── Farms ───────────────────────────────────────────────────────────────────
INSERT INTO farms (name, location, owner, latitude, longitude) VALUES
    ('Green Valley Farm',   'Fresno, CA',        'Maria Gonzalez',  36.7468, -119.7726),
    ('Sunrise Organics',    'Salinas, CA',        'James Okafor',    36.6777, -121.6555),
    ('Prairie Wind Ranch',  'Dodge City, KS',    'Linda Hartmann',  37.7528, -100.0171);

-- ─── Fields ──────────────────────────────────────────────────────────────────
INSERT INTO fields (farm_id, name, area_hectares, crop_type, planting_date, expected_harvest) VALUES
    (1, 'North Block',    12.5, 'Wheat',    '2026-01-10', '2026-07-15'),
    (1, 'South Block',    9.0,  'Corn',     '2026-02-01', '2026-08-20'),
    (2, 'East Slope',     7.3,  'Lettuce',  '2026-02-15', '2026-05-10'),
    (2, 'Greenhouse A',   2.1,  'Tomatoes', '2026-01-20', '2026-06-30'),
    (3, 'Field 1 - West', 20.0, 'Soybean',  '2026-03-01', '2026-09-10'),
    (3, 'Field 2 - East', 18.4, 'Sorghum',  '2026-03-05', '2026-09-25');

-- ─── Sensors ─────────────────────────────────────────────────────────────────
INSERT INTO sensors (field_id, serial_no, type) VALUES
    (1, 'SN-SOIL-001', 'soil'),
    (1, 'SN-WTH-001',  'weather'),
    (2, 'SN-SOIL-002', 'soil'),
    (3, 'SN-SOIL-003', 'soil'),
    (3, 'SN-AIR-001',  'aerial'),
    (4, 'SN-SOIL-004', 'soil'),
    (5, 'SN-SOIL-005', 'soil'),
    (5, 'SN-WTH-002',  'weather'),
    (6, 'SN-SOIL-006', 'soil');

-- ─── Crop Health Readings (last 7 days, multiple per day per field) ───────────
-- Field 1 — Wheat, generally healthy
INSERT INTO crop_health_readings
    (field_id, sensor_id, recorded_at, health_score, ndvi, soil_moisture, soil_ph, soil_temp_c, air_temp_c, humidity_pct, rainfall_mm, pest_risk_level, disease_risk_level, notes)
VALUES
    (1, 1, NOW() - INTERVAL '6 days', 82.0, 0.72, 32.1, 6.8, 18.2, 22.5, 55.0, 0.0, 1, 0, NULL),
    (1, 1, NOW() - INTERVAL '5 days', 83.5, 0.74, 30.5, 6.8, 19.0, 23.1, 52.0, 2.3, 1, 0, NULL),
    (1, 1, NOW() - INTERVAL '4 days', 81.0, 0.71, 28.9, 6.9, 19.5, 24.0, 50.0, 0.0, 1, 1, 'Slight yellowing observed on east edge'),
    (1, 1, NOW() - INTERVAL '3 days', 79.0, 0.69, 27.0, 6.9, 20.1, 25.0, 47.0, 0.0, 2, 1, NULL),
    (1, 1, NOW() - INTERVAL '2 days', 77.5, 0.67, 25.0, 7.0, 21.0, 26.5, 44.0, 0.0, 2, 1, 'Soil moisture dropping, irrigation recommended'),
    (1, 1, NOW() - INTERVAL '1 day',  75.0, 0.65, 22.5, 7.0, 21.5, 27.0, 42.0, 0.0, 2, 2, NULL),
    (1, 1, NOW(),                     76.5, 0.66, 31.0, 6.9, 20.5, 25.0, 53.0, 8.5, 1, 2, 'Irrigation applied this morning');

-- Field 2 — Corn, some pest pressure
INSERT INTO crop_health_readings
    (field_id, sensor_id, recorded_at, health_score, ndvi, soil_moisture, soil_ph, soil_temp_c, air_temp_c, humidity_pct, rainfall_mm, pest_risk_level, disease_risk_level)
VALUES
    (2, 3, NOW() - INTERVAL '6 days', 88.0, 0.80, 38.0, 6.5, 17.5, 21.0, 60.0, 5.0, 0, 0),
    (2, 3, NOW() - INTERVAL '5 days', 87.5, 0.79, 36.5, 6.5, 18.0, 22.0, 58.0, 0.0, 1, 0),
    (2, 3, NOW() - INTERVAL '4 days', 85.0, 0.77, 34.0, 6.6, 18.5, 22.5, 57.0, 0.0, 2, 0),
    (2, 3, NOW() - INTERVAL '3 days', 82.0, 0.74, 33.0, 6.6, 19.0, 23.0, 56.0, 0.0, 2, 1),
    (2, 3, NOW() - INTERVAL '2 days', 78.0, 0.70, 31.5, 6.7, 19.5, 24.0, 55.0, 0.0, 3, 1),
    (2, 3, NOW() - INTERVAL '1 day',  74.0, 0.66, 30.0, 6.7, 20.0, 25.0, 53.0, 0.0, 3, 2),
    (2, 3, NOW(),                     73.0, 0.65, 30.5, 6.8, 20.0, 24.5, 54.0, 0.0, 3, 2);

-- Field 3 — Lettuce, very healthy
INSERT INTO crop_health_readings
    (field_id, sensor_id, recorded_at, health_score, ndvi, soil_moisture, soil_ph, soil_temp_c, air_temp_c, humidity_pct, rainfall_mm, pest_risk_level, disease_risk_level)
VALUES
    (3, 4, NOW() - INTERVAL '6 days', 92.0, 0.85, 45.0, 6.2, 15.0, 18.0, 70.0, 3.0, 0, 0),
    (3, 4, NOW() - INTERVAL '5 days', 93.5, 0.86, 44.0, 6.2, 15.5, 18.5, 68.0, 0.0, 0, 0),
    (3, 4, NOW() - INTERVAL '4 days', 93.0, 0.86, 43.5, 6.3, 15.5, 19.0, 67.0, 0.0, 0, 0),
    (3, 4, NOW() - INTERVAL '3 days', 91.5, 0.84, 42.0, 6.3, 16.0, 19.5, 66.0, 1.5, 0, 0),
    (3, 4, NOW() - INTERVAL '2 days', 92.5, 0.85, 43.0, 6.2, 16.0, 19.0, 68.0, 0.0, 0, 0),
    (3, 4, NOW() - INTERVAL '1 day',  91.0, 0.84, 42.5, 6.2, 16.5, 19.5, 67.0, 0.0, 0, 0),
    (3, 4, NOW(),                     90.5, 0.83, 42.0, 6.3, 16.5, 20.0, 66.0, 0.0, 0, 0);

-- Field 4 — Tomatoes (greenhouse), optimal conditions
INSERT INTO crop_health_readings
    (field_id, sensor_id, recorded_at, health_score, ndvi, soil_moisture, soil_ph, soil_temp_c, air_temp_c, humidity_pct, rainfall_mm, pest_risk_level, disease_risk_level)
VALUES
    (4, 6, NOW() - INTERVAL '6 days', 95.0, 0.88, 40.0, 6.5, 22.0, 24.0, 65.0, 0.0, 0, 0),
    (4, 6, NOW() - INTERVAL '4 days', 94.5, 0.87, 39.5, 6.5, 22.5, 24.5, 63.0, 0.0, 0, 0),
    (4, 6, NOW() - INTERVAL '2 days', 96.0, 0.89, 41.0, 6.4, 22.0, 24.0, 64.0, 0.0, 0, 0),
    (4, 6, NOW(),                     95.5, 0.88, 40.5, 6.5, 22.5, 24.0, 64.0, 0.0, 0, 0);

-- Field 5 — Soybean, drought stress
INSERT INTO crop_health_readings
    (field_id, sensor_id, recorded_at, health_score, ndvi, soil_moisture, soil_ph, soil_temp_c, air_temp_c, humidity_pct, rainfall_mm, pest_risk_level, disease_risk_level, notes)
VALUES
    (5, 7, NOW() - INTERVAL '6 days', 85.0, 0.78, 35.0, 7.0, 20.0, 28.0, 40.0, 0.0, 1, 0, NULL),
    (5, 7, NOW() - INTERVAL '5 days', 82.0, 0.75, 28.0, 7.0, 22.0, 30.0, 36.0, 0.0, 1, 0, NULL),
    (5, 7, NOW() - INTERVAL '4 days', 77.0, 0.70, 21.0, 7.1, 24.0, 32.0, 33.0, 0.0, 1, 0, 'Heat wave began'),
    (5, 7, NOW() - INTERVAL '3 days', 70.0, 0.62, 16.0, 7.1, 26.0, 34.0, 30.0, 0.0, 1, 1, 'Critical drought stress'),
    (5, 7, NOW() - INTERVAL '2 days', 64.0, 0.55, 12.0, 7.2, 27.0, 35.0, 28.0, 0.0, 2, 1, 'Wilting visible'),
    (5, 7, NOW() - INTERVAL '1 day',  60.0, 0.50, 10.5, 7.2, 28.0, 35.5, 27.0, 0.0, 2, 2, 'Emergency irrigation activated'),
    (5, 7, NOW(),                     65.0, 0.57, 22.0, 7.1, 25.0, 32.0, 35.0, 0.0, 1, 1, 'Recovery after irrigation');

-- Field 6 — Sorghum, mild issues
INSERT INTO crop_health_readings
    (field_id, sensor_id, recorded_at, health_score, ndvi, soil_moisture, soil_ph, soil_temp_c, air_temp_c, humidity_pct, rainfall_mm, pest_risk_level, disease_risk_level)
VALUES
    (6, 9, NOW() - INTERVAL '6 days', 88.0, 0.80, 36.0, 6.8, 21.0, 27.0, 42.0, 0.0, 0, 0),
    (6, 9, NOW() - INTERVAL '4 days', 86.5, 0.78, 33.0, 6.8, 22.0, 28.5, 40.0, 0.0, 1, 0),
    (6, 9, NOW() - INTERVAL '2 days', 84.0, 0.76, 30.0, 6.9, 23.0, 30.0, 38.0, 0.0, 1, 1),
    (6, 9, NOW(),                     83.0, 0.75, 29.5, 6.9, 23.5, 30.5, 37.0, 0.0, 1, 1);

-- ─── Alerts ──────────────────────────────────────────────────────────────────
INSERT INTO alerts (field_id, type, severity, message, resolved, resolved_at) VALUES
    (2, 'pest',     'high',     'Corn earworm pressure detected. Scouting recommended immediately.', FALSE, NULL),
    (2, 'disease',  'medium',   'Early signs of northern leaf blight. Monitor closely.', FALSE, NULL),
    (5, 'drought',  'critical', 'Soil moisture critically low (< 15%). Crops at risk of irreversible stress.', TRUE, NOW() - INTERVAL '12 hours'),
    (5, 'drought',  'medium',   'Heat stress conditions persist. Monitor NDVI daily.', FALSE, NULL),
    (1, 'drought',  'medium',   'Soil moisture below threshold — irrigation recommended.', TRUE, NOW() - INTERVAL '2 hours'),
    (1, 'disease',  'low',      'Minor fungal risk due to elevated humidity. Preventative treatment optional.', FALSE, NULL);

COMMIT;
