// Course construction: a single analytic height/surface field per hole
// drives BOTH the rendered mesh and the physics, so what you see is what
// the ball plays off.
//
// Visuals: PBR texture splatting (real grass/rough/sand photos re-tinted by
// designed vertex colors), photo branch-card trees, reflective water, and a
// tree-line backdrop. Visual construction is gated on `document` + loaded
// assets so the field logic also runs headless (jsc/Node) for testing.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { Water } from 'three/addons/objects/Water.js';
import { makeFbm, makeRng } from './noise.js';
import { SURF } from './physics.js';

const VISUAL = typeof document !== 'undefined';

const sstep = (e0, e1, x) => {
  const t = Math.min(Math.max((x - e0) / (e1 - e0), 0), 1);
  return t * t * (3 - 2 * t);
};
const lerp = (a, b, t) => a + (b - a) * t;

// ---------- shape helpers ----------

function ellipseVal(s, x, z) {
  const dx = x - s.cx, dz = z - s.cz;
  const c = Math.cos(s.rot || 0), sn = Math.sin(s.rot || 0);
  const lx = dx * c + dz * sn;
  const lz = -dx * sn + dz * c;
  return (lx / s.rx) ** 2 + (lz / s.rz) ** 2;
}

function distToPolyline(pts, x, z) {
  let best = Infinity, bestAlong = 0, along = 0;
  for (let i = 0; i < pts.length - 1; i++) {
    const ax = pts[i].x, az = pts[i].z, bx = pts[i + 1].x, bz = pts[i + 1].z;
    const abx = bx - ax, abz = bz - az;
    const L2 = abx * abx + abz * abz;
    const t = L2 ? Math.min(Math.max(((x - ax) * abx + (z - az) * abz) / L2, 0), 1) : 0;
    const px = ax + abx * t, pz = az + abz * t;
    const d = Math.hypot(x - px, z - pz);
    const segLen = Math.sqrt(L2);
    if (d < best) { best = d; bestAlong = along + segLen * t; }
    along += segLen;
  }
  return { dist: best, along: bestAlong, total: along };
}

// ---------- splatted PBR ground material ----------
// vertex colors carry the designed hue (stripes, depth tints); the photo
// textures are normalized by their mean so they contribute structure only.

function splatMaterial(assets) {
  const g = assets.ground;
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1.0, metalness: 0 });
  mat.envMapIntensity = 0.3;   // tame grazing-angle sky reflection washout
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, {
      uGrassD: { value: g.grassD }, uGrassN: { value: g.grassN },
      uRoughD: { value: g.roughD }, uRoughN: { value: g.roughN },
      uSandD: { value: g.sandD }, uSandN: { value: g.sandN },
      uGrassMean: { value: g.grassMean },
      uRoughMean: { value: g.roughMean },
      uSandMean: { value: g.sandMean },
      uTime: { value: 0 },
      uWindVec: { value: new THREE.Vector2(1, 0) },
    });
    mat.userData.shader = shader;
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', `#include <common>
        attribute vec4 splat;
        varying vec4 vSplat;
        varying vec3 vWPos;`)
      .replace('#include <begin_vertex>', `#include <begin_vertex>
        vSplat = splat;
        vWPos = (modelMatrix * vec4(transformed, 1.0)).xyz;`);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>
        varying vec4 vSplat;
        varying vec3 vWPos;
        uniform sampler2D uGrassD, uGrassN, uRoughD, uRoughN, uSandD, uSandN;
        uniform vec3 uGrassMean, uRoughMean, uSandMean;
        uniform float uTime;
        uniform vec2 uWindVec;
        vec2 uvFair() { return vWPos.xz * 0.27; }
        vec2 uvGreen() { return vWPos.xz * 0.9; }
        vec2 uvRough() { return vWPos.xz * 0.16; }
        vec2 uvSand() { return vWPos.xz * 0.3; }`)
      .replace('#include <color_fragment>', `#include <color_fragment>
        {
          vec3 gA = texture2D(uGrassD, uvFair()).rgb / uGrassMean;
          vec3 gB = texture2D(uGrassD, uvGreen()).rgb / uGrassMean;
          vec3 grassC = mix(gA, gB, vSplat.w);
          vec3 roughC = texture2D(uRoughD, uvRough()).rgb / uRoughMean;
          vec3 sandC  = texture2D(uSandD, uvSand()).rgb / uSandMean;
          vec3 structure = grassC * vSplat.x + roughC * vSplat.y + sandC * vSplat.z;
          structure = mix(vec3(1.0), structure, 0.85);   // soften photo contrast
          diffuseColor.rgb *= clamp(structure, 0.25, 1.9);

          // drifting cloud shadows
          vec2 cuv = vWPos.xz * 0.0011 + uWindVec * uTime * 0.0022 + vec2(0.0, uTime * 0.0006);
          float cn = texture2D(uRoughD, cuv).g * 0.62
                   + texture2D(uRoughD, cuv * 2.7 + 0.41).g * 0.38;
          diffuseColor.rgb *= 1.0 - 0.24 * smoothstep(0.48, 0.78, cn);
        }`)
      .replace('#include <normal_fragment_maps>', `
        {
          vec3 nT = texture2D(uGrassN, uvFair()).xyz * (vSplat.x * (1.0 - vSplat.w * 0.7))
                  + texture2D(uGrassN, uvGreen()).xyz * (vSplat.x * vSplat.w * 0.7)
                  + texture2D(uRoughN, uvRough()).xyz * vSplat.y
                  + texture2D(uSandN, uvSand()).xyz * vSplat.z;
          vec3 mapN = nT * 2.0 - 1.0;
          mapN.xy *= 0.8;
          mapN = normalize(mapN);
          vec3 eyePos = -vViewPosition;
          vec3 q0 = dFdx(eyePos);
          vec3 q1 = dFdy(eyePos);
          vec2 st0 = dFdx(uvFair());
          vec2 st1 = dFdy(uvFair());
          vec3 Nn = normalize(normal);
          vec3 Tt = normalize(q0 * st1.t - q1 * st0.t);
          vec3 Bb = -normalize(cross(Nn, Tt));
          normal = normalize(mat3(Tt, Bb, Nn) * mapN);
        }`);
  };
  return mat;
}

// ---------- branch-card trees ----------
// Trees are built the way games do it: a bark-textured trunk plus dozens of
// alpha-tested cards cut from real photographed branch textures.

// sub-rectangles of usable sprigs/clusters inside the Poly Haven atlases
const PINE_SPRIG = { u0: 0.030, v0: 0.550, u1: 0.225, v1: 0.985 };
const LEAF_RECT_A = { u0: 0.010, v0: 0.270, u1: 0.440, v1: 0.740 };
const LEAF_RECT_B = { u0: 0.040, v0: 0.005, u1: 0.420, v1: 0.460 };

function cardGeo(w, h, rect) {
  const g = new THREE.PlaneGeometry(w, h);
  g.translate(0, h / 2, 0);              // pivot at the stem
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) {
    uv.setXY(i,
      rect.u0 + uv.getX(i) * (rect.u1 - rect.u0),
      rect.v0 + uv.getY(i) * (rect.v1 - rect.v0));
  }
  return g;
}

const _m4 = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _eu = new THREE.Euler();
function placed(geo, px, py, pz, rx, ry, rz, s = 1) {
  const g = geo.clone();
  _eu.set(rx, ry, rz, 'YXZ');
  _q.setFromEuler(_eu);
  _m4.compose(new THREE.Vector3(px, py, pz), _q, new THREE.Vector3(s, s, s));
  g.applyMatrix4(_m4);
  return g;
}

function normalsUp(geo) {
  const n = geo.attributes.normal;
  for (let i = 0; i < n.count; i++) n.setXYZ(i, 0, 1, 0);
  return geo;
}

function pineCanopy(seed) {
  const rng = makeRng(seed);
  const sprig = cardGeo(1.9, 3.2, PINE_SPRIG);
  const cards = [];
  for (let y = 2.4; y <= 8.2; y += 0.92) {
    const t = (y - 2.4) / 5.8;
    const n = Math.round(6 - 3 * t);
    const s = 1.15 - 0.62 * t;
    for (let i = 0; i < n; i++) {
      const yaw = (i / n) * Math.PI * 2 + rng() * 1.2;
      const pitch = -(Math.PI / 2) + 0.38 + rng() * 0.25;  // fan out, slight droop
      cards.push(placed(sprig, 0, y + (rng() - 0.5) * 0.3, 0, pitch, yaw, 0, s * (0.85 + rng() * 0.3)));
    }
  }
  // upright crown
  cards.push(placed(sprig, 0, 8.0, 0, -0.06, rng() * Math.PI, 0, 0.8));
  cards.push(placed(sprig, 0, 8.0, 0, -0.06, rng() * Math.PI + Math.PI / 2, 0, 0.72));
  return normalsUp(mergeGeometries(cards));
}

function leafCanopy(seed) {
  const rng = makeRng(seed);
  const a = cardGeo(3.1, 3.1, LEAF_RECT_A);
  const b = cardGeo(2.8, 3.0, LEAF_RECT_B);
  const cards = [];
  const CY = 5.2;
  for (let i = 0; i < 26; i++) {
    const az = rng() * Math.PI * 2;
    const elev = (rng() - 0.32) * 1.9;
    const r = 0.7 + rng() * 1.9;
    const px = Math.cos(az) * Math.cos(elev) * r;
    const pz = Math.sin(az) * Math.cos(elev) * r;
    const py = CY + Math.sin(elev) * r * 0.8;
    cards.push(placed(
      rng() < 0.5 ? a : b,
      px, py - 1.4, pz,
      (rng() - 0.6) * 1.1, rng() * Math.PI * 2, (rng() - 0.5) * 0.7,
      0.8 + rng() * 0.5,
    ));
  }
  return normalsUp(mergeGeometries(cards));
}

function trunkGeo(rTop, rBot, h, vRepeat) {
  const g = new THREE.CylinderGeometry(rTop, rBot, h, 8, 1, true);
  g.translate(0, h / 2, 0);
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setY(i, uv.getY(i) * vRepeat);
  return g;
}

let _treeKit = null;
function treeKit(assets) {
  if (_treeKit) return _treeKit;
  const t = assets.trees;
  const swayShaders = [];
  // gentle wind sway: displace canopy vertices, phase keyed off the
  // instance's world position so the forest doesn't move in lockstep
  const addSway = (mat) => {
    mat.onBeforeCompile = (shader) => {
      shader.uniforms.uTime = { value: 0 };
      shader.uniforms.uWind = { value: 1 };
      swayShaders.push(shader);
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', `#include <common>
          uniform float uTime;
          uniform float uWind;`)
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          {
            #ifdef USE_INSTANCING
              float ph = instanceMatrix[3].x * 0.73 + instanceMatrix[3].z * 1.11;
            #else
              float ph = 0.0;
            #endif
            float reach = max(transformed.y - 1.5, 0.0);
            float sway = sin(uTime * (0.9 + 0.25 * sin(ph)) + ph)
                       * (0.006 + 0.004 * uWind) * reach;
            transformed.x += sway;
            transformed.z += sway * 0.6;
            transformed.y += sin(uTime * 1.7 + ph * 1.3) * 0.008 * reach;
          }`);
    };
    return mat;
  };
  const canopyMat = (map, cut) => addSway(new THREE.MeshLambertMaterial({
    map, alphaTest: cut, side: THREE.DoubleSide,
  }));
  const depthMat = (map, cut) => new THREE.MeshDepthMaterial({
    depthPacking: THREE.RGBADepthPacking, map, alphaTest: cut,
  });
  _treeKit = {
    canopies: [
      { geo: pineCanopy(11), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pine' },
      { geo: pineCanopy(47), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pine' },
      { geo: leafCanopy(23), mat: canopyMat(t.leafCard, 0.4), depth: depthMat(t.leafCard, 0.4), trunk: 'leaf' },
      { geo: leafCanopy(89), mat: canopyMat(t.leafCard, 0.4), depth: depthMat(t.leafCard, 0.4), trunk: 'leaf' },
    ],
    trunks: {
      pine: { geo: trunkGeo(0.07, 0.30, 8.6, 3), mat: new THREE.MeshLambertMaterial({ map: t.pineBark }) },
      leaf: { geo: trunkGeo(0.14, 0.36, 4.8, 2), mat: new THREE.MeshLambertMaterial({ map: t.leafBark }) },
    },
    swayShaders,
  };
  return _treeKit;
}

// ---------- course field + meshes ----------

// `holes` is the full world-space routing; `focusIdx` is the hole being played.
// The field is evaluated over every hole whose footprint overlaps the rendered
// region (see `active` below) so neighbours blend into one continuous course.
// (For the range, pass a single-hole array: buildCourse([RANGE], 0, assets).)
export function buildCourse(holes, focusIdx, assets) {
  const focus = holes[focusIdx];
  const hole = focus;                 // focus-hole alias used throughout visuals
  const isRange = !!focus.isRange;

  const fbmBase = makeFbm(focus.seed, 4);
  const fbmDetail = makeFbm(focus.seed * 7 + 3, 3);
  const fbmGreen = makeFbm(focus.seed * 13 + 5, 3);

  // Elevation is sampled in the FOCUS hole's LOCAL frame, so the hole you play
  // sits on exactly the terrain it was tuned for — yet it's still one continuous
  // field across the whole rendered region (neighbours included, no seams),
  // because the region is only ever a single focus hole's neighbourhood.
  const place = focus.place || { ox: 0, oz: 0, rot: 0 };
  const pc = Math.cos(place.rot), ps = Math.sin(place.rot);
  const toLocal = (x, z) => {                 // inverse of routing's toWorld
    const dx = x - place.ox, dz = z - place.oz;
    return { lx: dx * pc - dz * ps, lz: dx * ps + dz * pc };
  };

  const path = hole.path;
  const tee = path[0];
  const fhw = hole.fairwayHalf;

  const baseAt = isRange
    ? (x, z) => { const l = toLocal(x, z); return fbmBase(l.lx * 0.003, l.lz * 0.003) * 0.35; }
    : (x, z) => {
        const l = toLocal(x, z);
        return fbmBase(l.lx * 0.0065, l.lz * 0.0065) * 4.5 + fbmBase(l.lx * 0.018 + 50, l.lz * 0.018) * 1.1;
      };

  // focusSet drives physics/lie (the hole you're playing only); active is the
  // set of neighbours that also get RENDERED (assigned once region bounds known).
  const focusSet = [focus];
  let active = [focus];

  // water level: relative to terrain near the water features
  let waterLevel = -100;
  let hasWater = hole.water.length > 0;
  if (hasWater) {
    let minBase = Infinity;
    for (const w of hole.water) {
      if (w.type === 'pond') minBase = Math.min(minBase, baseAt(w.cx, w.cz));
      else for (const p of w.pts) minBase = Math.min(minBase, baseAt(p.x, p.z));
    }
    waterLevel = minBase - 0.45;
  }
  const bedH = waterLevel - 1.1;

  function waterMask(x, z) {
    let m = 0, core = false;
    for (const w of hole.water) {
      if (w.type === 'pond') {
        const v = ellipseVal(w, x, z);
        m = Math.max(m, sstep(1.45, 0.8, v));
        if (v < 1.0) core = true;
      } else {
        const half = w.width / 2;
        const { dist } = distToPolyline(w.pts, x, z);
        m = Math.max(m, sstep(half + 8, half - 1, dist));
        if (dist < half) core = true;
      }
    }
    return { m, core };
  }

  // `set` selects which holes contribute. Physics/lie use the focus hole only
  // (so each hole plays exactly as designed, regardless of how tightly packed
  // its neighbours are); the mesh passes `active` so neighbours render too.
  function heightAt(x, z, set = focusSet) {
    const l = toLocal(x, z);   // focus-local sample coords for the noise fields

    // nearest fairway across the set → continuous fairway/rough blend
    let fairMask = 0;
    for (const ho of set) {
      const d = distToPolyline(ho.path, x, z).dist;
      fairMask = Math.max(fairMask, sstep(ho.fairwayHalf + 20, ho.fairwayHalf - 5, d));
    }

    let h = baseAt(x, z);
    h += fbmDetail(l.lx * 0.05, l.lz * 0.05) * 0.85 * (1 - fairMask);  // bumpy rough
    h += fbmGreen(l.lx * 0.034 + 700, l.lz * 0.034) * 0.5;            // gentle micro-undulation everywhere
    h += fairMask * 0.15;                                             // slight fairway crown

    // green plateaus with gentle internal contours
    for (const ho of set) {
      const g = ho.green;
      const gv = ellipseVal(g, x, z);
      if (gv < 3.2) {
        const gm = 1 - sstep(1.05, 2.6, gv);
        const greenH = baseAt(g.cx, g.cz) + 0.4 + fbmGreen(l.lx * 0.028, l.lz * 0.028) * 0.13;
        h = lerp(h, greenH, gm);
      }
    }

    // tee pads
    for (const ho of set) {
      const t = ho.path[0];
      const td = Math.hypot(x - t.x, z - t.z);
      if (td < 16) {
        const tm = 1 - sstep(7, 15, td);
        h = lerp(h, baseAt(t.x, t.z) + 0.45, tm);
      }
    }

    // bunkers: dished bowl + a raised lip/face on the rim, so the trap reads as
    // a real 3D hazard the ball must climb out of (not a painted patch).
    for (const ho of set) {
      for (const b of ho.bunkers) {
        const bv = ellipseVal(b, x, z);
        if (bv < 2.4) {
          const t = Math.max(0, 1 - bv);
          h -= b.depth * Math.pow(t, 1.15);                       // steeper wall, flatter floor
          h += 0.22 * Math.exp(-((bv - 1.12) ** 2) / 0.02);       // pronounced grass lip
        }
      }
    }

    // water carve (focus hole only — after fairway so the creek cuts through)
    if (hasWater) {
      const { m } = waterMask(x, z);
      if (m > 0) h = lerp(h, bedH, m * 0.95);
    }
    return h;
  }

  function surfaceAt(x, z, set = focusSet) {
    if (hasWater) {
      const { core } = waterMask(x, z);
      if (core && heightAt(x, z, set) <= waterLevel + 0.06) return SURF.WATER;
    }
    for (const ho of set) {
      for (const b of ho.bunkers) {
        if (ellipseVal(b, x, z) < 1) return SURF.SAND;
      }
    }
    for (const ho of set) { if (ellipseVal(ho.green, x, z) <= 1.0) return SURF.GREEN; }
    for (const ho of set) { if (ellipseVal(ho.green, x, z) <= 1.6) return SURF.FRINGE; }
    for (const ho of set) {
      const t = ho.path[0];
      if (Math.hypot(x - t.x, z - t.z) < 7) return SURF.TEE;
    }
    for (const ho of set) {
      if (distToPolyline(ho.path, x, z).dist < ho.fairwayHalf) return SURF.FAIRWAY;
    }
    return SURF.ROUGH;
  }

  function normalAt(x, z) {
    const e = 0.4;
    const hx = heightAt(x + e, z) - heightAt(x - e, z);
    const hz = heightAt(x, z + e) - heightAt(x, z - e);
    const inv = 1 / Math.hypot(hx / (2 * e), 1, hz / (2 * e));
    return { x: -hx / (2 * e) * inv, y: inv, z: -hz / (2 * e) * inv };
  }

  // point at distance s along the playing line
  function pointAtAlong(s) {
    let acc = 0;
    for (let i = 0; i < path.length - 1; i++) {
      const a = path[i], b = path[i + 1];
      const L = Math.hypot(b.x - a.x, b.z - a.z);
      if (acc + L >= s) {
        const t = (s - acc) / L;
        return { x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t };
      }
      acc += L;
    }
    return { ...path[path.length - 1] };
  }

  const pathInfo = (x, z) => distToPolyline(path, x, z);

  // out of bounds: a white-stake corridor around the playing line.
  // Judged where the ball comes to rest, like the real rule.
  const obDist = fhw + (hole.obMargin ?? 55);
  const isOB = (x, z) => distToPolyline(path, x, z).dist > obDist;

  // ---------- bounds ----------
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  const stretch = (x, z, m) => {
    minX = Math.min(minX, x - m); maxX = Math.max(maxX, x + m);
    minZ = Math.min(minZ, z - m); maxZ = Math.max(maxZ, z + m);
  };
  for (const p of path) stretch(p.x, p.z, 0);
  for (const b of hole.bunkers) stretch(b.cx, b.cz, Math.max(b.rx, b.rz));
  for (const w of hole.water) {
    if (w.type === 'pond') stretch(w.cx, w.cz, Math.max(w.rx, w.rz));
    else for (const p of w.pts) stretch(p.x, p.z, w.width);
  }
  const MARGIN = 90;
  minX -= MARGIN; maxX += MARGIN; minZ -= MARGIN; maxZ += MARGIN;

  // Holes whose footprint overlaps this region render + feed the field too,
  // so neighbours appear as part of one continuous course (not islands).
  active = holes.filter((h) => {
    let hx0 = Infinity, hx1 = -Infinity, hz0 = Infinity, hz1 = -Infinity;
    const ext = (x, z, m) => {
      hx0 = Math.min(hx0, x - m); hx1 = Math.max(hx1, x + m);
      hz0 = Math.min(hz0, z - m); hz1 = Math.max(hz1, z + m);
    };
    for (const p of h.path) ext(p.x, p.z, h.fairwayHalf);
    ext(h.green.cx, h.green.cz, Math.max(h.green.rx, h.green.rz));
    for (const b of h.bunkers) ext(b.cx, b.cz, Math.max(b.rx, b.rz));
    return hx1 >= minX && hx0 <= maxX && hz1 >= minZ && hz0 <= maxZ;
  });
  if (!active.includes(focus)) active.push(focus);

  const pinPos = {
    x: hole.pin.x,
    z: hole.pin.z,
    y: heightAt(hole.pin.x, hole.pin.z),
  };
  const teeH = heightAt(tee.x, tee.z);

  // ---------- visuals (browser only) ----------
  let group = null;
  let updateFlag = () => {};
  let updateWater = () => {};
  let spots = [];

  if (VISUAL && assets) {
    group = new THREE.Group();

    // terrain mesh: vertex colors (hue design) + splat weights (texture mix)
    const CELL = 1.7;
    const nx = Math.min(440, Math.ceil((maxX - minX) / CELL));
    const nz = Math.min(480, Math.ceil((maxZ - minZ) / CELL));
    const geo = new THREE.BufferGeometry();
    const positions = new Float32Array((nx + 1) * (nz + 1) * 3);
    const colors = new Float32Array((nx + 1) * (nz + 1) * 3);
    const splats = new Float32Array((nx + 1) * (nz + 1) * 4);

    const C = {
      fairA: new THREE.Color(0x5fa047), fairB: new THREE.Color(0x437d2c),  // mower light/dark
      firstCut: new THREE.Color(0x4c8237),
      fringe: new THREE.Color(0x57954a),
      greenA: new THREE.Color(0x79c25e), greenB: new THREE.Color(0x6cb451), // bright, fine-mown
      tee: new THREE.Color(0x60a44b),
      rough: new THREE.Color(0x3b662e), deep: new THREE.Color(0x2c4f22),
      sand: new THREE.Color(0xe6d6a8),
      bed: new THREE.Color(0x31464a),
    };
    const tmp = new THREE.Color();

    let vi = 0;
    for (let iz = 0; iz <= nz; iz++) {
      for (let ix = 0; ix <= nx; ix++) {
        const x = minX + (maxX - minX) * (ix / nx);
        const z = minZ + (maxZ - minZ) * (iz / nz);
        const h = heightAt(x, z, active);
        positions[vi * 3] = x;
        positions[vi * 3 + 1] = h;
        positions[vi * 3 + 2] = z;

        const surf = surfaceAt(x, z, active);
        const p = pathInfo(x, z);
        let sg = 0, sr = 0, ss = 0, sw = 0;   // grass, rough, sand, tight-mow

        if (hasWater && h < waterLevel + 0.05 && waterMask(x, z).m > 0.45) {
          tmp.copy(C.bed); sr = 1;
        } else if (surf === SURF.SAND) {
          // bright dry sand in the middle, darker damp/shadowed sand at the rim
          let depthT = 0;
          for (const ho of active) for (const b of ho.bunkers) depthT = Math.max(depthT, 1 - ellipseVal(b, x, z));
          tmp.copy(C.sand).multiplyScalar(0.82 + 0.18 * Math.max(0, depthT));
          tmp.multiplyScalar(1 + Math.sin((x * 0.9 + z * 1.3)) * 0.02);  // faint rake lines
          ss = 1;
        } else if (surf === SURF.GREEN || surf === SURF.TEE) {
          // fine cross-mown checker, aligned to the hole's own orientation
          const lg = toLocal(x, z);
          const checker = (Math.floor(lg.lx / 1.7) + Math.floor(lg.lz / 1.7)) % 2 === 0;
          tmp.copy(surf === SURF.TEE ? C.tee : (checker ? C.greenA : C.greenB));
          sg = 1; sw = 1;
        } else if (surf === SURF.FRINGE) {
          tmp.copy(C.fringe); sg = 1; sw = 0.6;
        } else {
          // fairway ↔ first-cut ↔ rough as a smooth, noise-warped blend so the
          // boundaries wander organically instead of tracing polygon edges.
          let fd = Infinity, falong = 0, fhwN = fhw;
          for (const ho of active) {
            const pi = distToPolyline(ho.path, x, z);
            if (pi.dist < fd) { fd = pi.dist; falong = pi.along; fhwN = ho.fairwayHalf; }
          }
          const edge = fbmDetail(x * 0.05 + 500, z * 0.05) * 3.6 + fbmDetail(x * 0.15 + 22, z * 0.15) * 1.3;
          const dd = fd + edge;                                   // wavy effective distance
          const fairT = sstep(fhwN + 5, fhwN - 3, dd);            // 1 fairway → 0 rough
          const stripe = Math.floor(falong / 8) % 2 === 0;       // mower bands
          tmp.copy(C.firstCut)
            .lerp(C.rough, sstep(fhwN + 3, fhwN + 13, dd))
            .lerp(C.deep, sstep(fhwN + 12, fhwN + 46, dd) * 0.8);
          tmp.lerp(stripe ? C.fairA : C.fairB, fairT);
          sg = fairT; sr = 1 - 0.65 * fairT;
        }
        const vmod = 1 + fbmDetail(x * 0.11 + 31, z * 0.11) * 0.07;
        colors[vi * 3] = tmp.r * vmod;
        colors[vi * 3 + 1] = tmp.g * vmod;
        colors[vi * 3 + 2] = tmp.b * vmod;
        splats[vi * 4] = sg; splats[vi * 4 + 1] = sr;
        splats[vi * 4 + 2] = ss; splats[vi * 4 + 3] = sw;
        vi++;
      }
    }

    const indices = [];
    for (let iz = 0; iz < nz; iz++) {
      for (let ix = 0; ix < nx; ix++) {
        const a = iz * (nx + 1) + ix;
        const b = a + 1;
        const c = a + (nx + 1);
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geo.setAttribute('splat', new THREE.BufferAttribute(splats, 4));
    geo.setIndex(indices);
    geo.computeVertexNormals();

    const terrain = new THREE.Mesh(geo, splatMaterial(assets));
    terrain.receiveShadow = true;
    group.add(terrain);

    // ---------- reflective water ----------
    const waters = [];
    for (const w of hole.water) {
      let cx, cz, sx, sz;
      if (w.type === 'pond') {
        cx = w.cx; cz = w.cz;
        sx = Math.max(w.rx, w.rz) * 2 + 24; sz = sx;
      } else {
        let wMinX = Infinity, wMaxX = -Infinity, wMinZ = Infinity, wMaxZ = -Infinity;
        for (const p of w.pts) {
          wMinX = Math.min(wMinX, p.x); wMaxX = Math.max(wMaxX, p.x);
          wMinZ = Math.min(wMinZ, p.z); wMaxZ = Math.max(wMaxZ, p.z);
        }
        cx = (wMinX + wMaxX) / 2; cz = (wMinZ + wMaxZ) / 2;
        sx = wMaxX - wMinX + w.width * 2 + 20;
        sz = wMaxZ - wMinZ + w.width * 2 + 20;
      }
      const water = new Water(new THREE.PlaneGeometry(sx, sz), {
        textureWidth: 512,
        textureHeight: 512,
        waterNormals: assets.waterN,
        sunDirection: assets.sunDir.clone(),
        sunColor: 0xffffff,
        waterColor: 0x0e3526,
        distortionScale: 2.6,
        fog: true,
      });
      water.rotation.x = -Math.PI / 2;
      water.position.set(cx, waterLevel, cz);
      group.add(water);
      waters.push(water);
    }
    // (combined animation hook assigned after trees/birds are built)

    // ---------- trees: instanced branch-card trees ----------
    const rng = makeRng(hole.seed * 31 + 7);
    spots = [];
    // Dense, tree-LINED corridors: trees crowd the rough just off the fairway
    // edges so each hole reads as an enclosed avenue, screening neighbours.
    const candidates = Math.floor(3800 * (hole.treeDensity || 1));
    for (let i = 0; i < candidates && spots.length < 1000; i++) {
      const x = minX + 14 + rng() * (maxX - minX - 28);
      const z = minZ + 14 + rng() * (maxZ - minZ - 28);
      // wavy forest edge — the tree line wanders in and out, never a straight wall
      const edgeWobble = fbmDetail(x * 0.08 + 401, z * 0.08) * 7;
      let nearPlay = false;
      for (const ho of active) {
        if (distToPolyline(ho.path, x, z).dist < ho.fairwayHalf + 13 + edgeWobble) { nearPlay = true; break; }
        if (ellipseVal(ho.green, x, z) < 3.0) { nearPlay = true; break; }
        if (Math.hypot(x - ho.path[0].x, z - ho.path[0].z) < 18) { nearPlay = true; break; }
      }
      if (nearPlay) continue;
      if (hasWater && waterMask(x, z).m > 0.05) continue;
      // copse clustering: trees gather into stands with natural clearings between
      const clump = fbmDetail(x * 0.035 + 90, z * 0.035) * 0.5 + 0.5;
      if (rng() > clump * 1.15) continue;
      const u = rng();
      spots.push({
        x, z, h: heightAt(x, z, active),
        s: 0.45 + Math.pow(rng(), 1.6) * 1.4,                       // many small/understory, few tall
        ry: rng() * Math.PI * 2,                                    // random facing
        tilt: (rng() - 0.5) * 0.17,                                 // varied lean
        kind: u < 0.5 ? (rng() < 0.5 ? 0 : 1)                       // mixed species
            : u < 0.85 ? (rng() < 0.5 ? 2 : 3)
            : (rng() < 0.5 ? 0 : 2),
        tint: [0.72 + rng() * 0.48, 0.76 + rng() * 0.46, 0.70 + rng() * 0.36],  // wider colour spread
      });
    }

    const kit = treeKit(assets);
    const m4 = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const eu = new THREE.Euler();
    const v3 = new THREE.Vector3();
    const s3 = new THREE.Vector3();
    const col = new THREE.Color();

    function setInstances(im, mine, tinted) {
      mine.forEach((t, i) => {
        eu.set(t.tilt, t.ry, t.tilt * 0.7);
        q.setFromEuler(eu);
        v3.set(t.x, t.h - 0.12, t.z);
        s3.set(t.s, t.s, t.s);
        m4.compose(v3, q, s3);
        im.setMatrixAt(i, m4);
        if (tinted) {
          col.setRGB(t.tint[0], t.tint[1], t.tint[2]);
          im.setColorAt(i, col);
        }
      });
      im.instanceMatrix.needsUpdate = true;
      if (im.instanceColor) im.instanceColor.needsUpdate = true;
      group.add(im);
    }

    for (let k = 0; k < kit.canopies.length; k++) {
      const mine = spots.filter(t => t.kind === k);
      if (!mine.length) continue;
      const c = kit.canopies[k];
      const im = new THREE.InstancedMesh(c.geo, c.mat, mine.length);
      im.customDepthMaterial = c.depth;
      im.castShadow = true;
      setInstances(im, mine, true);
    }
    for (const species of ['pine', 'leaf']) {
      const mine = spots.filter(t => kit.canopies[t.kind].trunk === species);
      if (!mine.length) continue;
      const tk = kit.trunks[species];
      const im = new THREE.InstancedMesh(tk.geo, tk.mat, mine.length);
      im.castShadow = true;
      setInstances(im, mine, false);
    }

    // ---------- backdrop tree line (the HDRI supplies the far horizon) ----------
    // unlit + vertex gradient: lit Lambert showed its backfaces as a black
    // wall; an unlit hazy gradient reads as distant forest instead
    const ccx = (minX + maxX) / 2, ccz = (minZ + maxZ) / 2;
    const fbmBack = makeFbm(hole.seed + 77, 3);
    {
      const radius = Math.max(maxX - ccx, maxZ - ccz) + 170;
      const rgeo = new THREE.CylinderGeometry(radius, radius, 1, 140, 1, true);
      const rpos = rgeo.attributes.position;
      const rcol = new Float32Array(rpos.count * 3);
      const lo = new THREE.Color(0x2f4d28);
      const hi = new THREE.Color(0x5d7a55).lerp(new THREE.Color(0xaebfd0), 0.45);
      for (let i = 0; i < rpos.count; i++) {
        const x = rpos.getX(i), z = rpos.getZ(i);
        const top = rpos.getY(i) > 0;
        const a = Math.atan2(z, x);
        const n = fbmBack(Math.cos(a) * 2.4 + 4, Math.sin(a) * 2.4) * 0.5 + 0.5;
        rpos.setY(i, top ? 10 + n * 9 : -6);
        const c = top ? hi : lo;
        rcol[i * 3] = c.r; rcol[i * 3 + 1] = c.g; rcol[i * 3 + 2] = c.b;
      }
      rgeo.setAttribute('color', new THREE.BufferAttribute(rcol, 3));
      const rm = new THREE.Mesh(rgeo, new THREE.MeshBasicMaterial({
        vertexColors: true, side: THREE.BackSide, fog: true,
      }));
      rm.position.set(ccx, 0, ccz);
      group.add(rm);
    }

    // ---------- birds: distant circling silhouettes ----------
    const birds = [];
    {
      const bgeo = new THREE.PlaneGeometry(1.6, 0.5);
      const bcv = document.createElement('canvas');
      bcv.width = 64; bcv.height = 20;
      const bctx = bcv.getContext('2d');
      bctx.strokeStyle = 'rgba(20,24,20,0.9)';
      bctx.lineWidth = 3;
      bctx.lineCap = 'round';
      bctx.beginPath();
      bctx.moveTo(4, 16); bctx.quadraticCurveTo(20, 2, 32, 14);
      bctx.quadraticCurveTo(44, 2, 60, 16);
      bctx.stroke();
      const btex = new THREE.CanvasTexture(bcv);
      const bmat = new THREE.MeshBasicMaterial({
        map: btex, transparent: true, depthWrite: false, side: THREE.DoubleSide,
      });
      for (let i = 0; i < 5; i++) {
        const b = new THREE.Mesh(bgeo, bmat);
        b.rotation.x = -Math.PI / 2;
        b.userData = { i, r: 90 + i * 18, h: 42 + i * 5, ph: i * 1.37 };
        group.add(b);
        birds.push(b);
      }
    }

    // everything that breathes, drifts, or sways
    updateWater = (t, wind) => {
      for (const w of waters) w.material.uniforms.time.value = t * 0.5;
      const sh = terrain.material.userData.shader;
      if (sh) {
        sh.uniforms.uTime.value = t;
        if (wind) sh.uniforms.uWindVec.value.set(wind.x, wind.z);
      }
      for (const s of kit.swayShaders) {
        s.uniforms.uTime.value = t;
        if (wind) s.uniforms.uWind.value = wind.speed;
      }
      for (const b of birds) {
        const u = b.userData;
        const ang = t * 0.045 + u.ph;
        b.position.set(
          ccx + Math.cos(ang) * u.r * 1.5,
          u.h + Math.sin(t * 0.5 + u.ph) * 3,
          ccz + Math.sin(ang) * u.r,
        );
        b.rotation.set(-Math.PI / 2, 0, -ang);
        b.scale.y = 1 + Math.sin(t * 8 + u.ph * 3) * 0.35;  // wing-beat shimmer
      }
    };

    // ---------- flags + cups (one per nearby green) ----------
    const flags = [];
    const poleGeo = new THREE.CylinderGeometry(0.018, 0.02, 2.3, 8);
    const poleMat = new THREE.MeshLambertMaterial({ color: 0xf6f3ea });
    const finialGeo = new THREE.SphereGeometry(0.05, 12, 10);
    const finialMat = new THREE.MeshStandardMaterial({ color: 0xd8b15a, metalness: 0.7, roughness: 0.35 });
    const cupGeo = new THREE.CylinderGeometry(0.054, 0.054, 0.16, 18, 1, true);  // sunk liner
    const cupMat = new THREE.MeshBasicMaterial({ color: 0x0c120b, side: THREE.DoubleSide });
    const cupRimGeo = new THREE.RingGeometry(0.05, 0.066, 22);
    const cupRimMat = new THREE.MeshBasicMaterial({ color: 0xf3f1e7 });
    const flagMat = new THREE.MeshLambertMaterial({ color: 0xd23528, side: THREE.DoubleSide });
    for (const ho of active) {
      const fg = new THREE.Group();
      const pole = new THREE.Mesh(poleGeo, poleMat);
      pole.position.y = 1.15;
      pole.castShadow = true;
      fg.add(pole);

      const finial = new THREE.Mesh(finialGeo, finialMat);
      finial.position.y = 2.32;
      fg.add(finial);

      const fGeo = new THREE.PlaneGeometry(0.66, 0.42, 10, 4);
      fGeo.translate(0.33, 0, 0);
      const fBase = fGeo.attributes.position.array.slice();
      const fl = new THREE.Mesh(fGeo, flagMat);
      fl.position.y = 2.04;
      fg.add(fl);

      const cup = new THREE.Mesh(cupGeo, cupMat);
      cup.position.y = -0.08;
      fg.add(cup);
      const cupRim = new THREE.Mesh(cupRimGeo, cupRimMat);
      cupRim.rotation.x = -Math.PI / 2;
      cupRim.position.y = 0.012;
      fg.add(cupRim);

      fg.position.set(ho.pin.x, heightAt(ho.pin.x, ho.pin.z, active), ho.pin.z);
      group.add(fg);
      flags.push({ geo: fGeo, base: fBase });
    }

    // ---------- green-reading grid (slope colored: blue low → red high) ----------
    {
      const gdef = hole.green;
      const R = Math.max(gdef.rx, gdef.rz) * 1.3;
      const SUB = 0.6, STEP = 1.2;
      const inside = (x, z) => ellipseVal(gdef, x, z) <= 1.3;
      let hMin = Infinity, hMax = -Infinity;
      for (let gx = -R; gx <= R; gx += SUB) {
        for (let gz = -R; gz <= R; gz += SUB) {
          const x = gdef.cx + gx, z = gdef.cz + gz;
          if (!inside(x, z)) continue;
          const hh = heightAt(x, z);
          hMin = Math.min(hMin, hh); hMax = Math.max(hMax, hh);
        }
      }
      const span = Math.max(hMax - hMin, 0.01);
      const lowC = new THREE.Color(0x58a7e8), highC = new THREE.Color(0xe8645f);
      const cc = new THREE.Color();
      const pos = [], col = [];
      const pushPt = (x, z) => {
        const hh = heightAt(x, z);
        pos.push(x, hh + 0.035, z);
        cc.copy(lowC).lerp(highC, (hh - hMin) / span);
        col.push(cc.r, cc.g, cc.b);
      };
      const walk = (alongX) => {
        for (let a = -R; a <= R; a += STEP) {
          let prevIn = false;
          for (let b = -R; b <= R; b += SUB) {
            const x = gdef.cx + (alongX ? a : b);
            const z = gdef.cz + (alongX ? b : a);
            const isIn = inside(x, z);
            if (isIn && prevIn) {
              const px = gdef.cx + (alongX ? a : b - SUB);
              const pz = gdef.cz + (alongX ? b - SUB : a);
              pushPt(px, pz); pushPt(x, z);
            }
            prevIn = isIn;
          }
        }
      };
      walk(true); walk(false);
      const ggeo = new THREE.BufferGeometry();
      ggeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(pos), 3));
      ggeo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(col), 3));
      const grid = new THREE.LineSegments(ggeo, new THREE.LineBasicMaterial({
        vertexColors: true, transparent: true, opacity: 0.55, depthWrite: false,
      }));
      grid.visible = false;
      group.add(grid);
      group.userData.greenGrid = grid;
    }

    // ---------- OB stakes along the corridor ----------
    {
      const stakes = [];
      let L = 0;
      for (let i = 1; i < path.length; i++) {
        L += Math.hypot(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z);
      }
      for (let s = 0; s <= L; s += 24) {
        const p = pointAtAlong(s);
        const p2 = pointAtAlong(Math.min(s + 2, L));
        let tx = p2.x - p.x, tz = p2.z - p.z;
        const tl = Math.hypot(tx, tz) || 1;
        tx /= tl; tz /= tl;
        for (const side of [-1, 1]) {
          const sx = p.x + -tz * side * (obDist - 2);
          const sz = p.z + tx * side * (obDist - 2);
          if (hasWater && waterMask(sx, sz).m > 0.05) continue;
          stakes.push({ x: sx, z: sz, h: heightAt(sx, sz, active) });
        }
      }
      if (stakes.length) {
        const sgeo = new THREE.CylinderGeometry(0.045, 0.045, 1.15, 6);
        const smat = new THREE.MeshLambertMaterial({ color: 0xf5f2e8 });
        const im = new THREE.InstancedMesh(sgeo, smat, stakes.length);
        const sm4 = new THREE.Matrix4();
        stakes.forEach((st, i) => {
          sm4.makeTranslation(st.x, st.h + 0.55, st.z);
          im.setMatrixAt(i, sm4);
        });
        im.instanceMatrix.needsUpdate = true;
        im.castShadow = true;
        group.add(im);
      }
    }

    const teeMarkMat = new THREE.MeshBasicMaterial({ color: 0xe8e3d2 });
    for (const side of [-1, 1]) {
      const mark = new THREE.Mesh(new THREE.SphereGeometry(0.1, 10, 8), teeMarkMat);
      mark.position.set(tee.x + side * 2.2, teeH + 0.1, tee.z);
      group.add(mark);
    }

    updateFlag = function (t, windSpeed = 4) {
      const amp = 0.03 + windSpeed * 0.012;
      for (const f of flags) {
        const arr = f.geo.attributes.position.array;
        for (let i = 0; i < arr.length; i += 3) {
          const bx = f.base[i];
          arr[i + 2] = Math.sin(bx * 9 - t * (3 + windSpeed * 0.7)) * amp * bx;
        }
        f.geo.attributes.position.needsUpdate = true;
        f.geo.computeVertexNormals();
      }
    };
  }

  function dispose() {
    if (!group) return;
    group.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material && !o.isWater) {
        if (Array.isArray(o.material)) o.material.forEach(m => m.dispose());
        else o.material.dispose();
      }
    });
  }

  return {
    group, heightAt, surfaceAt, normalAt, waterLevel,
    pinPos, teePos: { x: tee.x, y: teeH, z: tee.z },
    path, holeDef: focus,
    pointAtAlong, pathInfo, isOB, updateFlag, updateWater, dispose,
    greenGrid: group ? group.userData.greenGrid : null,
    bounds: { minX, maxX, minZ, maxZ },
    trees: spots.map(t => ({ x: t.x, z: t.z, h: t.h, s: t.s, isPine: t.kind <= 1 })),
  };
}
