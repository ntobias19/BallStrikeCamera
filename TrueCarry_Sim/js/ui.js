// HUD: telemetry panels, 3-click swing meter, toasts, scorecard,
// and the top-down minimap (drawn straight from the hole definition).

import { fmtYards } from './clubs.js';
import { holeLength } from './holes.js';

const $ = (id) => document.getElementById(id);

export function toParStr(n) {
  if (n === 0) return 'E';
  return n > 0 ? `+${n}` : `${n}`;
}

export class HUD {
  constructor() {
    this.el = {
      hud: $('hud'),
      hcHole: $('hc-hole'), hcPar: $('hc-par'), hcYds: $('hc-yds'),
      hcStroke: $('hc-stroke'), hcTotal: $('hc-total'), hcName: $('hc-name'),
      wind: $('wind'), windArrow: $('wind-arrow'), windSpeed: $('wind-speed'),
      toast: $('toast'),
      clubName: $('club-name'), clubCarry: $('club-carry'),
      clubPrev: $('club-prev'), clubNext: $('club-next'),
      pinNum: $('pin-num'), pinUnit: document.querySelector('.pin-unit'),
      pinLabel: $('pin-label'), lieChip: $('lie-chip'),
      shotData: $('shot-data'),
      sdSpeed: $('sd-speed'), sdLaunch: $('sd-launch'), sdSpin: $('sd-spin'),
      sdApex: $('sd-apex'), sdCarry: $('sd-carry'), sdTotal: $('sd-total'),
      meter: $('meter'), meterFill: $('meter-fill'), meterCursor: $('meter-cursor'),
      meterPowermark: $('meter-powermark'), meterReadout: $('meter-readout'),
      title: $('title-screen'), btnStart: $('btn-start'),
      intro: $('hole-intro'), introHole: $('intro-hole'),
      introName: $('intro-name'), introMeta: $('intro-meta'),
      scorecard: $('scorecard'), scoreTable: $('score-table'),
      summary: $('summary'), summaryScore: $('summary-score'),
      summaryTable: $('summary-table'), btnAgain: $('btn-again'),
      minimap: $('minimap'),
      btnHoles: $('btn-holes'),
      jumpMenu: $('jump-menu'), jumpList: $('jump-list'),
    };
    this.mapCtx = this.el.minimap.getContext('2d');
    this.toastTimer = null;

    // close the jump menu when the backdrop (not the panel) is clicked
    if (this.el.jumpMenu) {
      this.el.jumpMenu.addEventListener('click', (e) => {
        if (e.target === this.el.jumpMenu) this.jumpMenuHide();
      });
    }
  }

  show() { this.el.hud.classList.remove('hidden'); }
  hide() { this.el.hud.classList.add('hidden'); }

  setHole(num, par, yds, name) {
    this.el.hcHole.textContent = `HOLE ${num}`;
    this.el.hcPar.textContent = `PAR ${par}`;
    this.el.hcYds.textContent = `${yds} YDS`;
    this.el.hcName.textContent = name;
  }

  setStroke(stroke, totalToPar) {
    this.el.hcStroke.textContent = `STROKE ${stroke}`;
    this.el.hcTotal.textContent = `${toParStr(totalToPar)} TOTAL`;
  }

  setWind(mph, relAngleRad) {
    this.el.windSpeed.textContent = Math.round(mph);
    this.el.windArrow.style.transform = `rotate(${relAngleRad * 180 / Math.PI}deg)`;
    this.el.wind.classList.toggle('calm', mph < 1);
  }

  setClub(name, carryMeters, putter) {
    this.el.clubName.textContent = name;
    this.el.clubCarry.textContent = putter ? 'ON THE DANCE FLOOR' : `${fmtYards(carryMeters)}y CARRY`;
  }

  setPin(meters) {
    if (meters < 23) {
      this.el.pinNum.textContent = Math.round(meters * 3.28084);
      this.el.pinUnit.textContent = 'ft';
    } else {
      this.el.pinNum.textContent = fmtYards(meters);
      this.el.pinUnit.textContent = 'y';
    }
  }

  setLie(surface) {
    const label = {
      tee: 'TEE', fairway: 'FAIRWAY', fringe: 'FRINGE', rough: 'ROUGH',
      sand: 'BUNKER', green: 'GREEN', water: 'WATER',
    }[surface] || surface.toUpperCase();
    const chip = this.el.lieChip;
    chip.textContent = label;
    chip.classList.toggle('bad', surface === 'rough' || surface === 'sand');
    chip.classList.toggle('hazard', surface === 'water');
  }

  // ---------- launch monitor ----------

  shotDataShow({ speedMph, launchDeg, spinRpm }) {
    this.el.sdSpeed.textContent = `${Math.round(speedMph)} mph`;
    this.el.sdLaunch.textContent = `${launchDeg.toFixed(1)}°`;
    this.el.sdSpin.textContent = `${Math.round(spinRpm / 10) * 10} rpm`;
    this.el.sdApex.textContent = '—';
    this.el.sdCarry.textContent = '—';
    this.el.sdTotal.textContent = '—';
    this.el.shotData.classList.remove('hidden');
  }

  shotDataApex(ft) {
    this.el.sdApex.textContent = `${Math.round(ft)} ft`;
  }

  shotDataResult(carryY, totalY) {
    if (carryY != null) this.el.sdCarry.textContent = `${carryY}y`;
    if (totalY != null) this.el.sdTotal.textContent = `${totalY}y`;
  }

  shotDataHide() { this.el.shotData.classList.add('hidden'); }

  // ---------- swing meter ----------

  meterShow() { this.el.meter.classList.remove('hidden'); }
  meterHide() { this.el.meter.classList.add('hidden'); }

  meterUpdate({ cursor = 0, fill = 0, powerMark = null, text = '' }) {
    this.el.meterCursor.style.bottom = `${cursor * 100}%`;
    this.el.meterFill.style.height = `${fill * 100}%`;
    if (powerMark == null) {
      this.el.meterPowermark.classList.add('hidden');
    } else {
      this.el.meterPowermark.classList.remove('hidden');
      this.el.meterPowermark.style.bottom = `${powerMark * 100}%`;
    }
    this.el.meterReadout.textContent = text;
  }

  // ---------- toast ----------

  toast(html, ms = 2600) {
    clearTimeout(this.toastTimer);
    this.el.toast.innerHTML = html;
    this.el.toast.classList.remove('hidden');
    if (ms > 0) {
      this.toastTimer = setTimeout(() => this.el.toast.classList.add('hidden'), ms);
    }
  }
  toastHide() {
    clearTimeout(this.toastTimer);
    this.el.toast.classList.add('hidden');
  }

  // ---------- overlays ----------

  titleHide() { this.el.title.classList.add('hidden'); }

  introShow(num, name, par, yds) {
    this.el.introHole.textContent = `HOLE ${num}`;
    this.el.introName.textContent = name;
    this.el.introMeta.textContent = `PAR ${par} · ${yds} YDS`;
    this.el.intro.classList.remove('hidden');
  }
  introHide() { this.el.intro.classList.add('hidden'); }

  buildScoreRows(table, holes, scores) {
    const groups = holes.length > 9 ? [holes.slice(0, 9), holes.slice(9)] : [holes];
    let html = '';
    let runPar = 0, runScore = 0, runPlayedPar = 0;
    groups.forEach((g, gi) => {
      const offset = gi * 9;
      let head = '<tr><th></th>';
      let parRow = '<tr><td>PAR</td>';
      let scoreRow = '<tr><td>SCORE</td>';
      let gPar = 0, gScore = 0, gPlayedPar = 0;
      g.forEach((h, i) => {
        head += `<th>${h.id}</th>`;
        parRow += `<td>${h.par}</td>`;
        gPar += h.par;
        const s = scores[offset + i];
        if (s != null) {
          gPlayedPar += h.par; gScore += s;
          const cls = s < h.par ? 'under' : (s > h.par ? 'over' : '');
          scoreRow += `<td class="${cls}">${s}</td>`;
        } else {
          scoreRow += '<td>—</td>';
        }
      });
      const label = groups.length > 1 ? (gi ? 'IN' : 'OUT') : 'TOT';
      head += `<th>${label}</th>`;
      parRow += `<td>${gPar}</td>`;
      scoreRow += `<td>${gScore || '—'}</td>`;
      runPar += gPar; runScore += gScore; runPlayedPar += gPlayedPar;
      if (gi === groups.length - 1 && groups.length > 1) {
        const diff = runScore - runPlayedPar;
        head += '<th>TOT</th>';
        parRow += `<td>${runPar}</td>`;
        scoreRow += `<td>${runScore ? `${runScore} (${toParStr(diff)})` : '—'}</td>`;
      }
      html += `${head}</tr>${parRow}</tr>${scoreRow}</tr>`;
      if (gi === 0 && groups.length > 1) {
        html += '<tr class="card-gap"><td colspan="12"></td></tr>';
      }
    });
    table.innerHTML = html;
  }

  scorecardToggle(holes, scores) {
    const sc = this.el.scorecard;
    if (sc.classList.contains('hidden')) {
      this.buildScoreRows(this.el.scoreTable, holes, scores);
      sc.classList.remove('hidden');
    } else {
      sc.classList.add('hidden');
    }
  }
  scorecardHide() { this.el.scorecard.classList.add('hidden'); }

  summaryShow(holes, scores) {
    const totPar = holes.reduce((a, h) => a + h.par, 0);
    const tot = scores.reduce((a, s) => a + (s || 0), 0);
    this.el.summaryScore.textContent = toParStr(tot - totPar);
    this.buildScoreRows(this.el.summaryTable, holes, scores);
    this.el.summary.classList.remove('hidden');
  }
  summaryHide() { this.el.summary.classList.add('hidden'); }

  // ---------- minimap (whole-course overview, world coordinates) ----------

  // Fit every hole's world-space footprint into the minimap. North-up (no
  // per-hole rotation) so the routing reads as one connected course.
  mapSetCourse(holes, focusIdx) {
    this.worldHoles = holes;
    this.focusIdx = focusIdx;
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    const ext = (x, z, m = 0) => {
      minX = Math.min(minX, x - m); maxX = Math.max(maxX, x + m);
      minZ = Math.min(minZ, z - m); maxZ = Math.max(maxZ, z + m);
    };
    for (const h of holes) {
      for (const p of h.path) ext(p.x, p.z, h.fairwayHalf);
      ext(h.green.cx, h.green.cz, Math.max(h.green.rx, h.green.rz));
      for (const b of h.bunkers) ext(b.cx, b.cz, Math.max(b.rx, b.rz));
      for (const w of h.water) {
        if (w.type === 'pond') ext(w.cx, w.cz, Math.max(w.rx, w.rz));
        else for (const p of w.pts) ext(p.x, p.z, w.width);
      }
    }
    const padX = (maxX - minX) * 0.06 + 12, padZ = (maxZ - minZ) * 0.06 + 12;
    minX -= padX; maxX += padX; minZ -= padZ; maxZ += padZ;
    const W = this.el.minimap.width, H = this.el.minimap.height;
    this.mapScale = Math.min(W / (maxX - minX), H / (maxZ - minZ));
    this.mapBounds = { minX, maxX, minZ, maxZ };
    this.mapOff = {
      x: (W - (maxX - minX) * this.mapScale) / 2,
      y: (H - (maxZ - minZ) * this.mapScale) / 2,
    };
  }

  mapPt(x, z) {
    const b = this.mapBounds, sc = this.mapScale;
    return [this.mapOff.x + (x - b.minX) * sc, this.mapOff.y + (b.maxZ - z) * sc];
  }

  // Build a closed variable-width ribbon polygon (canvas points) around a hole
  // path. `halfWidthAt(t)` gives the half-width in metres at normalised position
  // t∈[0,1] along the hole, so fairways can taper and bulge organically.
  _ribbon(path, halfWidthAt) {
    const s = [];
    for (let i = 0; i < path.length - 1; i++) {
      const a = path[i], b = path[i + 1];
      const segLen = Math.hypot(b.x - a.x, b.z - a.z);
      const steps = Math.max(1, Math.round(segLen / 7));
      for (let k = 0; k < steps; k++) {
        const t = k / steps;
        s.push({ x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t });
      }
    }
    s.push(path[path.length - 1]);
    const n = s.length, L = [], R = [];
    for (let i = 0; i < n; i++) {
      const pv = s[Math.max(0, i - 1)], nx2 = s[Math.min(n - 1, i + 1)];
      let tx = nx2.x - pv.x, tz = nx2.z - pv.z;
      const tl = Math.hypot(tx, tz) || 1; tx /= tl; tz /= tl;
      const nx = -tz, nz = tx;                           // left normal
      const hw = halfWidthAt(i / (n - 1));
      L.push(this.mapPt(s[i].x + nx * hw, s[i].z + nz * hw));
      R.push(this.mapPt(s[i].x - nx * hw, s[i].z - nz * hw));
    }
    return L.concat(R.reverse());
  }

  _fillPoly(pts, style) {
    const ctx = this.mapCtx;
    ctx.fillStyle = style;
    ctx.beginPath();
    pts.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])));
    ctx.closePath();
    ctx.fill();
  }

  mapDraw(ball, aimDir, pin) {
    if (!this.worldHoles) return;
    const ctx = this.mapCtx;
    const W = this.el.minimap.width, H = this.el.minimap.height;
    const sc = this.mapScale;
    ctx.clearRect(0, 0, W, H);

    // dark ground outside the course
    ctx.fillStyle = '#0f1d10';
    ctx.beginPath();
    ctx.roundRect(0, 0, W, H, 9);
    ctx.fill();
    ctx.save();
    ctx.beginPath(); ctx.roundRect(0, 0, W, H, 9); ctx.clip();

    ctx.lineCap = 'round'; ctx.lineJoin = 'round';

    // 1) ROUGH underlay: a wide corridor per hole. Adjacent holes' corridors
    //    merge into one organic green "property" mass — the course body.
    ctx.strokeStyle = '#2f5128';
    this.worldHoles.forEach((hole) => {
      ctx.lineWidth = (hole.fairwayHalf + 30) * 2 * sc;
      ctx.beginPath();
      hole.path.forEach((p, j) => {
        const [mx, my] = this.mapPt(p.x, p.z);
        j ? ctx.lineTo(mx, my) : ctx.moveTo(mx, my);
      });
      ctx.stroke();
    });
    // tree speckle in the rough (deterministic), gives the property texture
    ctx.fillStyle = 'rgba(20,40,18,0.55)';
    let seed = 9241;
    const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
    for (const hole of this.worldHoles) {
      for (const p of hole.path) {
        for (let t = 0; t < 3; t++) {
          const ang = rnd() * Math.PI * 2, r = (hole.fairwayHalf + 12 + rnd() * 26);
          const [mx, my] = this.mapPt(p.x + Math.cos(ang) * r, p.z + Math.sin(ang) * r);
          ctx.beginPath(); ctx.arc(mx, my, 1.4, 0, Math.PI * 2); ctx.fill();
        }
      }
    }

    // 2) first-cut + fairway as variable-width ribbons (narrow off the tee and
    //    at the green, bulging through the landing zones) so holes read as
    //    organic shapes with doglegs, not uniform bars.
    const prof = (t) => 0.5 + 0.5 * Math.sin(Math.max(0, Math.min(1, t)) * Math.PI);
    this.worldHoles.forEach((hole, i) => {
      const isF = i === this.focusIdx;
      const fhw = hole.fairwayHalf;
      this._fillPoly(this._ribbon(hole.path, (t) => (fhw + 5) * (0.62 + 0.38 * prof(t))), '#3e7233');
      this._fillPoly(this._ribbon(hole.path, (t) => fhw * (0.5 + 0.5 * prof(t))), isF ? '#67ad4f' : '#4f9040');
    });

    // water — every hole
    ctx.fillStyle = '#2a5d74'; ctx.strokeStyle = '#2a5d74';
    for (const hole of this.worldHoles) {
      for (const w of hole.water) {
        if (w.type === 'pond') {
          const [mx, my] = this.mapPt(w.cx, w.cz);
          ctx.beginPath();
          ctx.ellipse(mx, my, w.rx * sc, w.rz * sc, w.rot || 0, 0, Math.PI * 2);
          ctx.fill();
        } else {
          ctx.lineWidth = w.width * sc;
          ctx.beginPath();
          w.pts.forEach((p, j) => {
            const [mx, my] = this.mapPt(p.x, p.z);
            j ? ctx.lineTo(mx, my) : ctx.moveTo(mx, my);
          });
          ctx.stroke();
        }
      }
    }

    // greens + bunkers + tee number labels — every hole
    this.worldHoles.forEach((hole, i) => {
      const isF = i === this.focusIdx;
      const g = hole.green;
      let [mx, my] = this.mapPt(g.cx, g.cz);
      ctx.fillStyle = isF ? '#8fd673' : '#6aa552';
      ctx.beginPath();
      ctx.ellipse(mx, my, ((g.rx + g.rz) / 2) * sc, ((g.rx + g.rz) / 2) * sc, 0, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = '#dcc995';
      for (const b of hole.bunkers) {
        const [bx, by] = this.mapPt(b.cx, b.cz);
        ctx.beginPath();
        ctx.ellipse(bx, by, ((b.rx + b.rz) / 2) * sc, ((b.rx + b.rz) / 2) * sc, 0, 0, Math.PI * 2);
        ctx.fill();
      }

      // hole number at the tee
      if (!hole.isRange) {
        const t = hole.path[0];
        const [tx, ty] = this.mapPt(t.x, t.z);
        ctx.fillStyle = isF ? '#f4e2a8' : 'rgba(230,232,220,0.7)';
        ctx.font = `${isF ? 'bold ' : ''}9px Rajdhani, sans-serif`;
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText(String(hole.id), tx, ty);
      }
    });

    // aim line (focus hole)
    if (ball && aimDir) {
      const [bx, by] = this.mapPt(ball.x, ball.z);
      const [ax, ay] = this.mapPt(ball.x + aimDir.x * 400, ball.z + aimDir.z * 400);
      ctx.strokeStyle = 'rgba(236, 217, 173, 0.55)';
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(ax, ay); ctx.stroke();
      ctx.setLineDash([]);
    }

    // pin
    if (pin) {
      const [px, py] = this.mapPt(pin.x, pin.z);
      ctx.fillStyle = '#e2654f';
      ctx.beginPath(); ctx.arc(px, py, 3, 0, Math.PI * 2); ctx.fill();
    }

    // ball
    if (ball) {
      const [bx, by] = this.mapPt(ball.x, ball.z);
      ctx.fillStyle = '#f7f5ec';
      ctx.strokeStyle = 'rgba(0,0,0,0.6)';
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.arc(bx, by, 3, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    }

    ctx.restore();
  }

  // ---------- hole jump menu ----------

  jumpMenuToggle(holes, currentIdx, onPick) {
    const m = this.el.jumpMenu;
    if (!m) return;
    if (!m.classList.contains('hidden')) { m.classList.add('hidden'); return; }
    const list = this.el.jumpList;
    list.innerHTML = '';
    holes.forEach((h, i) => {
      if (h.isRange) return;
      const btn = document.createElement('button');
      btn.className = 'jump-item' + (i === currentIdx ? ' current' : '');
      btn.innerHTML =
        `<span class="ji-num">${h.id}</span>` +
        `<span class="ji-name">${h.name}</span>` +
        `<span class="ji-meta">PAR ${h.par} · ${fmtYards(holeLength(h))}y</span>`;
      btn.addEventListener('click', () => onPick(i));
      list.appendChild(btn);
    });
    m.classList.remove('hidden');
  }

  jumpMenuHide() {
    if (this.el.jumpMenu) this.el.jumpMenu.classList.add('hidden');
  }
}
