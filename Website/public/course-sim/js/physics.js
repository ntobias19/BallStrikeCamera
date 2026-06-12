// Improved ball flight physics for TrueCarry_Course.
// Key upgrades over TrueCarry_Sim:
//   • True spin axis — single axis tilt drives Magnus, not two independent forces
//   • Wind gradient — stronger at altitude, with gust oscillation
//   • Elevation-adjusted distance display
//   • Slope-aware green rolling for putts

import { SURF, SURF_PROPS, heightAt, surfaceAt, slopeAt } from './terrain.js';

export { SURF };

const SUB     = 1 / 240;  // physics substep (seconds)
const BALL_R  = 0.0214;   // ball radius (meters)
const MASS    = 0.04593;  // ball mass (kg)
const AREA    = Math.PI * BALL_R * BALL_R;
const RHO     = 1.225;    // air density kg/m³
const GRAVITY = 9.80665;

// Aerodynamic coefficients
const CD_BASE = 0.240;    // drag
const CL_MAX  = 0.32;     // max Magnus lift
const AERO    = RHO * AREA * 0.5;

// Spin decay time constant (seconds)
const SPIN_DECAY = 10.0;

function scl(v, s) { return { x: v.x*s, y: v.y*s, z: v.z*s }; }
function add(a, b) { return { x: a.x+b.x, y: a.y+b.y, z: a.z+b.z }; }
function dot(a, b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
function cross(a, b) { return { x: a.y*b.z - a.z*b.y, y: a.z*b.x - a.x*b.z, z: a.x*b.y - a.y*b.x }; }
function mag(v) { return Math.sqrt(dot(v, v)); }
function norm(v) { const m = mag(v) || 1; return scl(v, 1/m); }

// ---------- Wind model ----------
// wind = { x, z, speed } — base wind vector
// altitude-dependent scaling + gust oscillation
let _windBase = { x: 0, z: 0, speed: 0 };
let _gustPhase = 0;

export function setWind(speedMph, dirDeg) {
  const rad = (dirDeg * Math.PI) / 180;
  const ms = speedMph * 0.44704;
  _windBase = { x: Math.sin(rad) * ms, z: Math.cos(rad) * ms, speed: ms };
  _gustPhase = Math.random() * Math.PI * 2;
}

function windAt(altitude, t) {
  const gradientScale = 0.7 + 0.6 * Math.min(altitude / 30, 1);
  const gust = 1 + 0.15 * Math.sin(_gustPhase + t * 0.7);
  return {
    x: _windBase.x * gradientScale * gust,
    z: _windBase.z * gradientScale * gust,
  };
}

// ---------- Spin axis model ----------
// backspin and sidespin collapse to a single spin axis vector.
// spinRate = sqrt(backspin² + sidespin²)
// axisTilt = atan2(sidespin, backspin)  → 0 = pure backspin, π/2 = pure sidespin
function makeSpinAxis(backspin, sidespin, shotHeading) {
  const spinRate = Math.hypot(backspin, sidespin);
  const axisTilt = Math.atan2(sidespin, backspin);
  // Spin axis in ball frame (perpendicular to shot direction, tilted by sidespin)
  // For a shot heading along +z in world: backspin axis is (+x), sidespin adds tilt
  const headRad = shotHeading;
  const cosH = Math.cos(headRad), sinH = Math.sin(headRad);
  // World-space spin axis: rotated to match shot heading
  return {
    axis: {
      x:  cosH * Math.cos(axisTilt),
      y:  Math.sin(axisTilt),
      z: -sinH * Math.cos(axisTilt),
    },
    rate: spinRate,
  };
}

// ---------- Shot creation ----------
export function createShot(opts) {
  const {
    ballSpeedMph, vlaDegrees, backspin = 2500, sidespin = 0,
    hlaDegrees = 0, windSpeedMph = 0, windDirDeg = 0,
    clubIdx = 0, lie = 'tee',
    startX = 0, startY = 0, startZ = 0,
    course,     // { waterLevel, waterAt(x,z), surfaceAt, heightAt }
    stimp = 10,
  } = opts;

  setWind(windSpeedMph, windDirDeg);

  const speedMs  = ballSpeedMph * 0.44704;
  const vla      = vlaDegrees * Math.PI / 180;
  const hla      = hlaDegrees * Math.PI / 180;
  const cosVla   = Math.cos(vla), sinVla = Math.sin(vla);

  const shotHeading = hla;

  const vx = Math.sin(hla) * cosVla * speedMs;
  const vy = sinVla * speedMs;
  const vz = Math.cos(hla) * cosVla * speedMs;

  // Terrain height at start
  const groundY = heightAt(startX, startZ);

  const sim = {
    pos: { x: startX, y: groundY + startY + BALL_R, z: startZ },
    vel: { x: vx, y: vy, z: vz },
    time: 0,
    spin: makeSpinAxis(backspin, sidespin, shotHeading),
    carryPos: null,
    totalPos: null,
    inFlight: true,
    events: [],
    apexY: groundY,
    apexFt: 0,
  };

  return sim;
}

// ---------- Per-substep physics ----------
export function stepFly(sim, course) {
  const spd = mag(sim.vel);
  if (spd < 0.01 && !sim.inFlight) return;

  sim.time += SUB;
  const t = sim.time;

  // Spin decay
  sim.spin.rate *= (1 - SUB / SPIN_DECAY);

  // Wind at current altitude
  const w = windAt(sim.pos.y, t);

  // Velocity relative to air
  const vRel = { x: sim.vel.x - w.x, y: sim.vel.y, z: sim.vel.z - w.z };
  const vRelSpd = mag(vRel) || 0.001;
  const vRelNorm = norm(vRel);

  // Drag
  const Cd = CD_BASE;
  const Fdrag = AERO * Cd * vRelSpd * vRelSpd;
  const drag = scl(vRelNorm, -Fdrag / MASS);

  // Magnus lift: F = cross(spinAxis, velRelNorm) × CL × spinRate_factor
  const spinFactor = Math.min(sim.spin.rate / 3000, 1) * CL_MAX;
  const magnus = cross(sim.spin.axis, vRelNorm);
  const lift = scl(magnus, spinFactor * AERO * vRelSpd * vRelSpd / MASS);

  // Integrate
  const ax = drag.x + lift.x;
  const ay = drag.y + lift.y - GRAVITY;
  const az = drag.z + lift.z;

  sim.vel.x += ax * SUB;
  sim.vel.y += ay * SUB;
  sim.vel.z += az * SUB;

  sim.pos.x += sim.vel.x * SUB;
  sim.pos.y += sim.vel.y * SUB;
  sim.pos.z += sim.vel.z * SUB;

  // Track apex
  if (sim.pos.y > sim.apexY) {
    sim.apexY = sim.pos.y;
    const groundHere = heightAt(sim.pos.x, sim.pos.z);
    sim.apexFt = (sim.pos.y - groundHere) * 3.28084;
  }

  // Water intercept (surface-level)
  if (course?.waterLevel != null && sim.pos.y - BALL_R <= course.waterLevel) {
    const surf = surfaceAt(sim.pos.x, sim.pos.z);
    if (surf === SURF.WATER) {
      sim.events.push({ type: 'water', pos: { ...sim.pos } });
      sim.vel = { x: 0, y: 0, z: 0 };
      sim.inFlight = false;
      return;
    }
  }

  // Tree collision (from terrain.js course.trees if provided)
  if (course?.trees?.length && sim.pos.y < 25) {
    for (const tree of course.trees) {
      const hdx = Math.abs(sim.pos.x - tree.x);
      const hdz = Math.abs(sim.pos.z - tree.z);
      const maxR = 5.0 * (tree.r / 3.5);
      if (hdx > maxR || hdz > maxR) continue;
      const canopyCY = heightAt(tree.x, tree.z) + 5.2 * (tree.r / 3.5) + tree.r;
      const canopyR  = tree.r;
      const dx = sim.pos.x - tree.x, dy = sim.pos.y - canopyCY, dz2 = sim.pos.z - tree.z;
      const dist2 = dx*dx + dy*dy + dz2*dz2;
      if (dist2 < canopyR * canopyR) {
        const dist = Math.sqrt(dist2) || 0.01;
        const nx = dx/dist, ny = dy/dist, nz2 = dz2/dist;
        const vn = sim.vel.x*nx + sim.vel.y*ny + sim.vel.z*nz2;
        if (vn >= 0) break;
        const depth = (canopyR - dist) / canopyR;
        const passChance = depth < 0.20 ? 0.60 : depth < 0.50 ? 0.25 : 0;
        if (passChance > 0 && Math.random() < passChance) {
          sim.vel.x *= 0.97; sim.vel.y *= 0.97; sim.vel.z *= 0.97;
          sim.events.push({ type: 'tree', graze: true, pos: { ...sim.pos } });
          break;
        }
        const pen = canopyR - dist + 0.02;
        sim.pos.x += nx*pen; sim.pos.y += ny*pen; sim.pos.z += nz2*pen;
        const energyRetain = depth < 0.35 ? 0.70 : depth < 0.65 ? 0.60 : 0.52;
        const rest = depth < 0.35 ? 0.50 : depth < 0.65 ? 0.38 : 0.28;
        sim.vel.x -= (1+rest)*vn*nx; sim.vel.y -= (1+rest)*vn*ny; sim.vel.z -= (1+rest)*vn*nz2;
        sim.vel.x *= energyRetain; sim.vel.y *= energyRetain; sim.vel.z *= energyRetain;
        sim.vel.x += (Math.random()-0.5)*2.0; sim.vel.z += (Math.random()-0.5)*2.0;
        sim.events.push({ type: 'tree', pos: { ...sim.pos } });
        break;
      }
    }
  }

  // Ground collision
  const h = heightAt(sim.pos.x, sim.pos.z);
  if (sim.pos.y <= h + BALL_R) {
    sim.pos.y = h + BALL_R;
    const surf = surfaceAt(sim.pos.x, sim.pos.z);

    if (!sim.carryPos) {
      sim.carryPos = { ...sim.pos };
      sim.events.push({ type: 'land', pos: { ...sim.pos }, surface: surf });
    }

    if (surf === SURF.WATER) {
      sim.events.push({ type: 'water', pos: { ...sim.pos } });
      sim.vel = { x: 0, y: 0, z: 0 };
      sim.inFlight = false;
      return;
    }

    const props = SURF_PROPS[surf] || SURF_PROPS[SURF.ROUGH];

    // Ground normal (slope-aware for putting on greens)
    const slope = slopeAt(sim.pos.x, sim.pos.z);
    const n = { x: slope.nx, y: slope.ny, z: slope.nz };
    const vn = dot(sim.vel, n);
    if (vn < 0) {
      const imp = -(1 + props.restitution) * vn;
      sim.vel.x += imp * n.x;
      sim.vel.y += imp * n.y;
      sim.vel.z += imp * n.z;
    }

    // Friction
    const vLen = mag(sim.vel) || 0.001;
    const tangential = { x: sim.vel.x - n.x * dot(sim.vel, n),
                         y: sim.vel.y - n.y * dot(sim.vel, n),
                         z: sim.vel.z - n.z * dot(sim.vel, n) };
    const tangLen = mag(tangential) || 0.001;
    const frictionForce = -props.friction * Math.abs(vn);
    sim.vel.x += (tangential.x / tangLen) * frictionForce * SUB;
    sim.vel.y += (tangential.y / tangLen) * frictionForce * SUB;
    sim.vel.z += (tangential.z / tangLen) * frictionForce * SUB;

    // Bunker deceleration
    if (surf === SURF.BUNKER) {
      const impact = mag(sim.vel);
      if (impact > 5) {
        sim.vel = { x: 0, y: 0, z: 0 };
        sim.events.push({ type: 'plugged', pos: { ...sim.pos } });
        sim.inFlight = false;
        return;
      }
      sim.vel.x *= 0.85; sim.vel.z *= 0.85;
    }

    // Stimp effect on green rolling speed
    if (surf === SURF.GREEN) {
      const stimpFactor = (stimp || 10) / 10;
      // Slope adds velocity component downhill
      const slopeVel = 0.15 * stimpFactor;
      sim.vel.x -= slope.nx * slopeVel * SUB;
      sim.vel.z -= slope.nz * slopeVel * SUB;
      sim.vel.x *= (1 - 0.07 / stimpFactor);
      sim.vel.z *= (1 - 0.07 / stimpFactor);
    } else {
      sim.vel.x *= (1 - 0.04 * props.friction);
      sim.vel.z *= (1 - 0.04 * props.friction);
    }

    // Stop threshold
    const spd2 = Math.hypot(sim.vel.x, sim.vel.z);
    if (spd2 < 0.08) {
      sim.vel = { x: 0, y: 0, z: 0 };
      if (!sim.totalPos) sim.totalPos = { ...sim.pos };
      sim.inFlight = false;
      return;
    }
    sim.inFlight = false; // rolling — not in the air
  } else {
    sim.inFlight = true;
  }
}

// ---------- Elevation-adjusted yardage display ----------
// Plays-like yardage: flat_yards ± 1 yard per 3 feet of elevation change
export function playsLike(flatMeters, fromY, toY) {
  const elevFt = (toY - fromY) * 3.28084;
  const adjustedYards = Math.round(flatMeters * 1.09361 + elevFt / 3);
  return adjustedYards;
}
