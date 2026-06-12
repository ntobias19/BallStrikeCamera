// Per-club shot dispersion tracker. Persists to localStorage.
// Tracks landing position offsets from the pin.

const PREFIX = 'tc_disp_';
const MAX_SHOTS = 60;

export function recordLanding(clubName, dx, dz) {
  const key = PREFIX + clubName.replace(/\s+/g, '_');
  let arr = [];
  try { arr = JSON.parse(localStorage.getItem(key) || '[]'); } catch {}
  arr.push({ dx: Math.round(dx * 10) / 10, dz: Math.round(dz * 10) / 10 });
  if (arr.length > MAX_SHOTS) arr.splice(0, arr.length - MAX_SHOTS);
  localStorage.setItem(key, JSON.stringify(arr));
}

export function getDispersion(clubName) {
  const key = PREFIX + clubName.replace(/\s+/g, '_');
  try { return JSON.parse(localStorage.getItem(key) || '[]'); } catch { return []; }
}

export function clearDispersion(clubName) {
  localStorage.removeItem(PREFIX + clubName.replace(/\s+/g, '_'));
}

// Draw dispersion cloud on minimap canvas context
// scale: pixels per meter
export function drawDispersion(ctx, clubName, pinX, pinZ, toCanvasFn, alpha = 0.65) {
  const shots = getDispersion(clubName);
  if (shots.length < 3) return;

  shots.forEach(({ dx, dz }) => {
    const [cx, cz] = toCanvasFn(pinX + dx, pinZ + dz);
    const age = shots.indexOf({ dx, dz }) / shots.length; // newer = more opaque
    const r = Math.min(2.5, shots.length / 30 * 2.5);
    ctx.beginPath();
    ctx.arc(cx, cz, r, 0, Math.PI * 2);
    ctx.fillStyle = `rgba(255,220,60,${alpha * 0.7})`;
    ctx.fill();
  });

  // Tendency: average offset label
  if (shots.length >= 5) {
    const avgX = shots.reduce((s, p) => s + p.dx, 0) / shots.length;
    const avgZ = shots.reduce((s, p) => s + p.dz, 0) / shots.length;
    const mag = Math.hypot(avgX, avgZ);
    if (mag > 1) {
      const dir = avgX > 0 ? 'R' : 'L';
      const [ax, az] = toCanvasFn(pinX + avgX, pinZ + avgZ);
      ctx.beginPath();
      ctx.arc(ax, az, 4, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(255,200,0,0.9)';
      ctx.fill();
    }
  }
}

// Summarize tendency across all shots for a club
export function getTendency(clubName) {
  const shots = getDispersion(clubName);
  if (shots.length < 5) return null;
  const avgX = shots.reduce((s, p) => s + p.dx, 0) / shots.length;
  const avgZ = shots.reduce((s, p) => s + p.dz, 0) / shots.length;
  const mag = Math.round(Math.hypot(avgX, avgZ) * 1.09361);
  if (mag < 2) return null;
  const side = avgX > 0.5 ? 'right' : avgX < -0.5 ? 'left' : null;
  const fwd  = avgZ < -1 ? 'short' : avgZ > 1 ? 'long' : null;
  if (!side && !fwd) return null;
  const parts = [];
  if (mag) parts.push(`${mag}y`);
  if (side) parts.push(side);
  if (fwd)  parts.push(fwd);
  return parts.join(' ');
}

// All clubs that have dispersion data
export function clubsWithData() {
  const keys = Object.keys(localStorage).filter(k => k.startsWith(PREFIX));
  return keys.map(k => k.slice(PREFIX.length).replace(/_/g, ' '));
}
