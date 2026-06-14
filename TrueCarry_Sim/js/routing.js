// Course routing: lays every hole out in ONE shared world coordinate system.
//
// Each hole in holes.js is authored in its own local space (tee at the origin,
// green out along +z). On its own that makes the 18 holes feel like separate
// islands. Here we arrange them as a real course does — two returning loops
// (front nine, back nine) curling around a central clubhouse — so the property
// reads as one cohesive golf course.
//
// `buildRouting(holes)` returns a parallel array of holes whose path / green /
// pin / bunkers / water are all transformed into world coordinates, plus the
// `place` ({ox, oz, rot}) that produced them. Everything downstream (terrain
// field, physics, minimap) then works in one continuous world space.

import { makeRng } from './noise.js';

// Rotate a local point by `rot` (radians, measured from +z) and offset to a
// world origin. Local +z maps to the world direction (sin rot, cos rot).
export function toWorld(place, lx, lz) {
  const c = Math.cos(place.rot), s = Math.sin(place.rot);
  return { x: place.ox + lx * c + lz * s, z: place.oz - lx * s + lz * c };
}

function xform(place, p, extra = {}) {
  const w = toWorld(place, p.x, p.z);
  return { ...p, ...extra, x: w.x, z: w.z };
}

// Transform an ellipse-shaped feature ({cx, cz, rot}) into world space.
function xformEllipse(place, e) {
  const w = toWorld(place, e.cx, e.cz);
  return { ...e, cx: w.x, cz: w.z, rot: (e.rot || 0) + place.rot };
}

function transformHole(hole, place) {
  const path = hole.path.map(p => {
    const w = toWorld(place, p.x, p.z);
    return { x: w.x, z: w.z };
  });
  const green = xformEllipse(place, hole.green);
  const pinW = toWorld(place, hole.pin.x, hole.pin.z);
  const bunkers = (hole.bunkers || []).map(b => xformEllipse(place, b));
  const water = (hole.water || []).map(w => {
    if (w.type === 'pond') return xformEllipse(place, w);
    return { ...w, pts: w.pts.map(p => { const q = toWorld(place, p.x, p.z); return { x: q.x, z: q.z }; }) };
  });
  return {
    ...hole,
    place,
    path,
    green,
    pin: { x: pinW.x, z: pinW.z },
    bunkers,
    water,
  };
}

// Playing length of a hole along its (local or world) path, meters.
function pathLength(path) {
  let L = 0;
  for (let i = 1; i < path.length; i++) {
    L += Math.hypot(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z);
  }
  return L;
}

// Pack a set of holes into one block of tight parallel lanes — the way real
// courses run several holes side by side. Holes alternate playing direction (up
// one lane, back down the next), all confined to a band so the fairways merge
// into a dense, connected mass. `angle` orients the block; two blocks at
// different angles read as an organic course rather than a grid.
function placeBlock(holes, placed, cfg) {
  const { ox, oz, angle, idxs, lane = 46, band = 430, jitter } = cfg;
  const fwd = { x: Math.sin(angle), z: Math.cos(angle) };          // "up" the lane
  const side = { x: Math.cos(angle), z: -Math.sin(angle) };        // lane-to-lane step
  idxs.forEach((i, k) => {
    const up = (k % 2 === 0);
    const jl = jitter ? (jitter(i * 5) - 0.5) * 18 : 0;             // small lane jitter
    const baseX = ox + side.x * (lane * k + jl);
    const baseZ = oz + side.z * (lane * k + jl);
    const rot = angle + (up ? 0 : Math.PI) + (jitter ? (jitter(i * 7) - 0.5) * 0.18 : 0);
    // down-lane holes start at the far end of the band and play back into it
    const tx = up ? baseX : baseX + fwd.x * band;
    const tz = up ? baseZ : baseZ + fwd.z * band;
    placed[i] = transformHole(holes[i], { ox: tx, oz: tz, rot });
  });
}

// Lay the course out as two packed blocks of parallel fairways set at different
// angles around a shared clubhouse — front nine in one block, back nine in the
// other. Densely packed lanes merge into one connected course body, reading as a
// real, compact golf course. (Holes needn't touch the next tee: advancing
// teleports the ball to the next tee.)
export function buildRouting(holes) {
  const n = holes.length;
  const placed = new Array(n);
  const jitter = makeRng ? makeRng(20240613) : null;

  if (n <= 1) {                                   // range / single-hole: identity
    placed[0] = transformHole(holes[0], { ox: 0, oz: 0, rot: 0 });
    return placed;
  }

  const half = Math.ceil(n / 2);
  const front = Array.from({ length: half }, (_, k) => k);
  const back = Array.from({ length: n - half }, (_, k) => k + half);

  // Front block runs ~north; back block angles off it, sharing the clubhouse
  // corner near the origin so the two nines abut into one property.
  placeBlock(holes, placed, { ox: 0,   oz: 0,   angle: -0.16, idxs: front, lane: 78, band: 440, jitter });
  placeBlock(holes, placed, { ox: 430, oz: 200, angle:  1.02, idxs: back,  lane: 78, band: 440, jitter });
  return placed;
}

export { pathLength };
