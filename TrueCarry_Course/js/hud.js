// HUD management for TrueCarry_Course.

export class HUD {
  constructor() {
    this._toast   = document.getElementById('hud-toast');
    this._toastTimer = null;
  }

  // Hole card
  setHole(num, par, yardage, name) {
    setText('hc-hole',   `HOLE ${num}`);
    setText('hc-par',    `PAR ${par}`);
    setText('hc-yds',    `${yardage} YDS`);
    setText('hc-name',   name || '');
  }

  setStroke(n, scoreStr) {
    setText('hc-stroke', `STROKE ${n}`);
    setText('hc-total',  scoreStr || 'E');
  }

  // Pin / distance
  setPin(flatYards, playsYards, lie) {
    setText('pin-num',   String(flatYards));
    setText('pin-plays', playsYards && playsYards !== flatYards ? `plays ${playsYards}y` : '');
    setText('lie-chip',  (lie || 'TEE').toUpperCase());
  }

  setPinLabel(label) { setText('pin-label', label); }
  setPinNum(n)       { setText('pin-num', String(n)); }

  // Club
  setClub(name, carryYards) {
    setText('club-name', name);
    setText('club-carry', carryYards ? `${carryYards}y CARRY` : '');
  }

  // Wind
  setWind(speedMph, dirDeg) {
    setText('wind-speed', String(Math.round(speedMph)));
    const arrow = document.getElementById('wind-arrow');
    if (arrow) arrow.style.transform = `rotate(${dirDeg}deg)`;
  }

  // Shot data panel (post-shot)
  showShotData(data) {
    const panel = document.getElementById('shot-data');
    if (!panel) return;
    setVal('sd-speed', data.speed  ? `${data.speed} mph`  : '—');
    setVal('sd-launch', data.launch ? `${data.launch}°`    : '—');
    setVal('sd-spin',   data.spin   ? `${data.spin} rpm`   : '—');
    setVal('sd-apex',   data.apex   ? `${data.apex} ft`    : '—');
    setVal('sd-carry',  data.carry  ? `${data.carry}y`     : '—');
    setVal('sd-total',  data.total  ? `${data.total}y`     : '—');
    panel.classList.remove('hidden');
  }

  hideShotData() {
    const p = document.getElementById('shot-data');
    if (p) p.classList.add('hidden');
  }

  // Toast notifications
  toast(html, ms = 1400) {
    if (!this._toast) return;
    this._toast.innerHTML = html;
    this._toast.classList.remove('hidden');
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => this._toast.classList.add('hidden'), ms);
  }

  // Meter
  showMeter() { show('meter'); }
  hideMeter() { hide('meter'); }
  setMeter(pct, snapped) {
    const fill = document.getElementById('meter-fill');
    const cursor = document.getElementById('meter-cursor');
    if (fill)   fill.style.height = `${pct * 100}%`;
    if (cursor) cursor.style.bottom = `${pct * 100}%`;
    const snap = document.getElementById('meter-snapline');
    if (snap) snap.classList.toggle('snapped', !!snapped);
  }

  // Putting mode
  showPuttMode(stimp) {
    show('putt-bar');
    setText('stimp-val', `STIMP ${stimp}`);
    show('stimp-badge');
  }

  hidePuttMode() {
    hide('putt-bar');
    hide('stimp-badge');
    hide('break-btn');
  }

  showBreakArrows() { setText('break-btn', 'HIDE BREAK'); }
  hideBreakArrows() { setText('break-btn', 'SHOW BREAK'); }

  // Overlays
  showHUD()    { show('hud'); }
  hideHUD()    { hide('hud'); }
  showTitle()  { show('title-screen'); }
  hideTitle()  { hide('title-screen'); }
  showIntro(holeName, par, yardage) {
    setText('intro-name', holeName);
    setText('intro-meta', `PAR ${par} · ${yardage} YDS`);
    show('hole-intro');
  }
  hideIntro()  { hide('hole-intro'); }
  showScorecard() { show('scorecard'); }
  hideScorecard() { hide('scorecard'); }

  // Score table
  renderScorecard(holes, scores) {
    const tbl = document.getElementById('score-table');
    if (!tbl) return;
    let html = '<thead><tr><th>H</th><th>Par</th><th>Score</th><th>+/-</th></tr></thead><tbody>';
    let total = 0, totalPar = 0;
    for (let i = 0; i < holes.length; i++) {
      const h = holes[i], s = scores[i];
      const diff = s != null ? s - h.par : null;
      totalPar += h.par;
      if (s != null) total += s;
      const cls = diff == null ? '' : diff < 0 ? 'birdie' : diff === 0 ? 'par' : 'bogey';
      html += `<tr class="${cls}"><td>${h.number}</td><td>${h.par}</td><td>${s ?? '—'}</td><td>${diff != null ? toParStr(diff) : '—'}</td></tr>`;
    }
    html += `</tbody><tfoot><tr><td colspan="2">TOTAL</td><td>${total}</td><td>${toParStr(total - totalPar)}</td></tr></tfoot>`;
    tbl.innerHTML = html;
  }

  // Minimap
  updateMinimap(ballX, ballZ, toC) {
    const canvas = document.getElementById('minimap');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const [cx, cz] = toC(ballX, ballZ);
    ctx.beginPath();
    ctx.arc(cx, cz, 4, 0, Math.PI * 2);
    ctx.fillStyle = '#ffffff';
    ctx.fill();
  }
}

function setText(id, val) {
  const el = document.getElementById(id);
  if (el) el.textContent = val;
}
function setVal(id, val) {
  const el = document.getElementById(id);
  if (el) el.textContent = val;
}
function show(id) {
  const el = document.getElementById(id);
  if (el) el.classList.remove('hidden');
}
function hide(id) {
  const el = document.getElementById(id);
  if (el) el.classList.add('hidden');
}

export function toParStr(diff) {
  if (diff === 0) return 'E';
  return diff > 0 ? `+${diff}` : String(diff);
}
