// ─── Navigation ──────────────────────────────────────────────────────────────
document.querySelectorAll('.nav-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById(`view-${btn.dataset.view}`).classList.add('active');
    if (btn.dataset.view === 'dashboard') loadDashboard();
    if (btn.dataset.view === 'alerts')    loadAlerts();
    if (btn.dataset.view === 'fields')    loadFields();
    if (btn.dataset.view === 'log')       loadFieldSelect('lr-field-id');
  });
});

// ─── Helpers ──────────────────────────────────────────────────────────────────
async function api(path, opts = {}) {
  const res = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...opts,
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

function scoreClass(s) {
  if (s === null || s === undefined) return '';
  if (s >= 85) return 'score-great';
  if (s >= 70) return 'score-good';
  if (s >= 55) return 'score-ok';
  if (s >= 40) return 'score-poor';
  return 'score-bad';
}

function riskLabel(level) {
  return ['None', 'Low', 'Medium', 'High', 'Critical'][level] ?? '—';
}

function relativeTime(ts) {
  if (!ts) return '—';
  const diff = Date.now() - new Date(ts).getTime();
  const m = Math.floor(diff / 60000);
  if (m < 1)   return 'just now';
  if (m < 60)  return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24)  return `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

function alertIcon(type) {
  return { pest: '🐛', disease: '🍂', drought: '🌵', frost: '❄️', overwater: '💧' }[type] ?? '⚠️';
}

// ─── Dashboard ────────────────────────────────────────────────────────────────
async function loadDashboard() {
  try {
    const d = await api('/api/dashboard');

    document.getElementById('stat-farms').textContent    = d.farm_count;
    document.getElementById('stat-fields').textContent   = d.field_count;
    document.getElementById('stat-critical').textContent = d.open_alerts.critical || 0;
    document.getElementById('stat-high').textContent     = d.open_alerts.high || 0;

    // Field health table
    const tbody = document.getElementById('field-health-body');
    tbody.innerHTML = d.field_health.map(f => `
      <tr>
        <td>${esc(f.farm_name)}</td>
        <td>${esc(f.field_name)}</td>
        <td>${esc(f.crop_type || '—')}</td>
        <td>${f.health_score !== null
          ? `<span class="score-badge ${scoreClass(f.health_score)}">${parseFloat(f.health_score).toFixed(1)}</span>`
          : '—'}</td>
        <td>${f.ndvi !== null ? parseFloat(f.ndvi).toFixed(3) : '—'}</td>
        <td>${f.soil_moisture !== null ? `${parseFloat(f.soil_moisture).toFixed(1)}%` : '—'}</td>
        <td><span class="risk-pill risk-${f.pest_risk_level ?? 0}">${riskLabel(f.pest_risk_level)}</span></td>
        <td>${relativeTime(f.recorded_at)}</td>
      </tr>
    `).join('') || '<tr><td colspan="8" class="loading">No data</td></tr>';

    // Recent readings table
    const rb = document.getElementById('recent-readings-body');
    rb.innerHTML = d.recent_readings.map(r => `
      <tr>
        <td>${esc(r.farm_name)} / ${esc(r.field_name)}</td>
        <td>${r.health_score !== null
          ? `<span class="score-badge ${scoreClass(r.health_score)}">${parseFloat(r.health_score).toFixed(1)}</span>`
          : '—'}</td>
        <td>${r.ndvi !== null ? parseFloat(r.ndvi).toFixed(3) : '—'}</td>
        <td>${r.soil_moisture !== null ? `${parseFloat(r.soil_moisture).toFixed(1)}%` : '—'}</td>
        <td>${r.air_temp_c !== null ? parseFloat(r.air_temp_c).toFixed(1) : '—'}</td>
        <td>${r.humidity_pct !== null ? `${parseFloat(r.humidity_pct).toFixed(0)}%` : '—'}</td>
        <td>${relativeTime(r.recorded_at)}</td>
      </tr>
    `).join('') || '<tr><td colspan="7" class="loading">No data</td></tr>';

  } catch (err) {
    console.error(err);
  }
}

// ─── Alerts ───────────────────────────────────────────────────────────────────
async function loadAlerts() {
  const showResolved = document.getElementById('show-resolved').checked;
  const container = document.getElementById('alerts-list');
  container.innerHTML = '<p class="loading">Loading…</p>';
  try {
    const alerts = await api(`/api/alerts?open=${showResolved ? 'false' : 'true'}`);
    if (!alerts.length) {
      container.innerHTML = '<p class="loading">No alerts.</p>';
      return;
    }
    container.innerHTML = alerts.map(a => `
      <div class="alert-card ${a.severity} ${a.resolved ? 'resolved' : ''}">
        <div class="alert-icon">${alertIcon(a.type)}</div>
        <div class="alert-body">
          <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px;">
            <strong>${esc(a.field_name)}</strong>
            <span style="color:#9ca3af;font-size:12px;">${esc(a.farm_name)}</span>
            <span class="alert-severity sev-${a.severity}">${a.severity.toUpperCase()}</span>
            ${a.resolved ? '<span style="font-size:11px;color:#9ca3af;">RESOLVED</span>' : ''}
          </div>
          <div>${esc(a.message)}</div>
          <div class="alert-meta">${a.type.toUpperCase()} · ${relativeTime(a.created_at)}</div>
        </div>
        ${!a.resolved ? `
          <button class="btn btn-sm btn-resolve" data-id="${a.id}">Resolve</button>
        ` : ''}
      </div>
    `).join('');

    container.querySelectorAll('.btn-resolve').forEach(btn => {
      btn.addEventListener('click', async () => {
        btn.disabled = true;
        btn.textContent = '…';
        try {
          await api(`/api/alerts/${btn.dataset.id}/resolve`, { method: 'PATCH' });
          loadAlerts();
        } catch (e) {
          btn.disabled = false;
          btn.textContent = 'Resolve';
        }
      });
    });
  } catch (err) {
    container.innerHTML = `<p class="form-error">${err.message}</p>`;
  }
}

document.getElementById('show-resolved').addEventListener('change', loadAlerts);

// ─── Fields ───────────────────────────────────────────────────────────────────
async function loadFields() {
  const tbody = document.getElementById('fields-body');
  tbody.innerHTML = '<tr><td colspan="7" class="loading">Loading…</td></tr>';
  try {
    const fields = await api('/api/fields');
    tbody.innerHTML = fields.map(f => `
      <tr>
        <td>${esc(f.farm_name)}</td>
        <td>${esc(f.name)}</td>
        <td>${esc(f.crop_type || '—')}</td>
        <td>${f.area_hectares !== null ? parseFloat(f.area_hectares).toFixed(1) : '—'}</td>
        <td>${f.planting_date ? f.planting_date.substring(0, 10) : '—'}</td>
        <td>${f.expected_harvest ? f.expected_harvest.substring(0, 10) : '—'}</td>
        <td></td>
      </tr>
    `).join('') || '<tr><td colspan="7" class="loading">No fields found.</td></tr>';
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="7" class="form-error">${err.message}</td></tr>`;
  }
}

// Add field form toggle
document.getElementById('btn-add-field').addEventListener('click', async () => {
  const form = document.getElementById('add-field-form');
  form.classList.toggle('hidden');
  if (!form.classList.contains('hidden')) {
    await loadFarmSelect('ff-farm-id');
  }
});
document.getElementById('btn-cancel-field').addEventListener('click', () => {
  document.getElementById('add-field-form').classList.add('hidden');
});

document.getElementById('btn-save-field').addEventListener('click', async () => {
  const err = document.getElementById('ff-error');
  err.classList.add('hidden');
  const body = {
    farm_id:          document.getElementById('ff-farm-id').value,
    name:             document.getElementById('ff-name').value.trim(),
    crop_type:        document.getElementById('ff-crop').value.trim() || null,
    area_hectares:    document.getElementById('ff-area').value || null,
    planting_date:    document.getElementById('ff-plant').value || null,
    expected_harvest: document.getElementById('ff-harvest').value || null,
  };
  if (!body.name) { showError(err, 'Field name is required.'); return; }
  try {
    await api('/api/fields', { method: 'POST', body: JSON.stringify(body) });
    document.getElementById('add-field-form').classList.add('hidden');
    loadFields();
    loadFieldSelect('lr-field-id');
  } catch (e) {
    showError(err, e.message);
  }
});

// ─── Log Reading ──────────────────────────────────────────────────────────────
async function loadFieldSelect(selectId) {
  const sel = document.getElementById(selectId);
  sel.innerHTML = '<option value="">Loading…</option>';
  try {
    const fields = await api('/api/fields');
    sel.innerHTML = fields.map(f =>
      `<option value="${f.id}">${esc(f.farm_name)} — ${esc(f.name)} (${esc(f.crop_type || 'unknown')})</option>`
    ).join('');
  } catch (e) {
    sel.innerHTML = '<option value="">Error loading fields</option>';
  }
}

async function loadFarmSelect(selectId) {
  const sel = document.getElementById(selectId);
  sel.innerHTML = '<option value="">Loading…</option>';
  try {
    const farms = await api('/api/farms');
    sel.innerHTML = farms.map(f =>
      `<option value="${f.id}">${esc(f.name)}</option>`
    ).join('');
  } catch (e) {
    sel.innerHTML = '<option value="">Error loading farms</option>';
  }
}

document.getElementById('btn-submit-reading').addEventListener('click', async () => {
  const result = document.getElementById('lr-result');
  const err    = document.getElementById('lr-error');
  result.classList.add('hidden');
  err.classList.add('hidden');

  const fieldId = document.getElementById('lr-field-id').value;
  if (!fieldId) { showError(err, 'Please select a field.'); return; }

  const num = id => {
    const v = document.getElementById(id).value;
    return v !== '' ? parseFloat(v) : null;
  };

  const body = {
    field_id:           parseInt(fieldId),
    health_score:       num('lr-health'),
    ndvi:               num('lr-ndvi'),
    soil_moisture:      num('lr-soil-moisture'),
    soil_ph:            num('lr-soil-ph'),
    soil_temp_c:        num('lr-soil-temp'),
    air_temp_c:         num('lr-air-temp'),
    humidity_pct:       num('lr-humidity'),
    rainfall_mm:        num('lr-rainfall'),
    pest_risk_level:    parseInt(document.getElementById('lr-pest-risk').value),
    disease_risk_level: parseInt(document.getElementById('lr-disease-risk').value),
    notes:              document.getElementById('lr-notes').value.trim() || null,
  };

  try {
    const res = await api('/api/readings', { method: 'POST', body: JSON.stringify(body) });
    const msg = res.alerts_generated > 0
      ? `Reading saved. ${res.alerts_generated} alert(s) generated automatically.`
      : 'Reading saved successfully.';
    result.textContent = msg;
    result.classList.remove('hidden');
    // Clear numeric inputs
    ['lr-health','lr-ndvi','lr-soil-moisture','lr-soil-ph','lr-soil-temp',
     'lr-air-temp','lr-humidity','lr-rainfall','lr-notes'].forEach(id => {
      document.getElementById(id).value = '';
    });
    document.getElementById('lr-pest-risk').value = '0';
    document.getElementById('lr-disease-risk').value = '0';
  } catch (e) {
    showError(err, e.message);
  }
});

// ─── Utilities ────────────────────────────────────────────────────────────────
function esc(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function showError(el, msg) {
  el.textContent = msg;
  el.classList.remove('hidden');
}

// ─── Init ─────────────────────────────────────────────────────────────────────
loadDashboard();
