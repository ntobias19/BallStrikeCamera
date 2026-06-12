// Green system: undulated mesh, slope break arrows, putting mechanic.

import * as THREE from 'three';
import { heightAt, slopeAt } from './terrain.js';

const UNDULATION_AMP = 0.45; // max height deviation in meters

// Seeded LCG random for deterministic undulation
function lcg(seed) {
  let s = (seed * 1664525 + 1013904223) & 0xffffffff;
  return () => { s = (s * 1664525 + 1013904223) & 0xffffffff; return (s >>> 0) / 0xffffffff; };
}

// 2D value noise seeded per green
function makeNoise2D(seed) {
  const rng = lcg(seed);
  const N = 16;
  const table = Array.from({ length: N*N }, () => rng() * 2 - 1);
  function lerp(a, b, t) { return a + (b - a) * (t * t * (3 - 2 * t)); }
  return function(x, z) {
    const fx = ((x % N) + N) % N, fz = ((z % N) + N) % N;
    const ix = Math.floor(fx), iz = Math.floor(fz);
    const tx = fx - ix, tz = fz - iz;
    const a = table[(iz % N) * N + (ix % N)];
    const b = table[(iz % N) * N + ((ix+1) % N)];
    const c = table[((iz+1) % N) * N + (ix % N)];
    const d = table[((iz+1) % N) * N + ((ix+1) % N)];
    return lerp(lerp(a, b, tx), lerp(c, d, tx), tz);
  };
}

// Build a high-res undulated green mesh on top of the terrain
export function buildGreenMesh(hole, scene) {
  const poly = hole.green.polygon;
  if (!poly || poly.length < 3) return null;

  const xs = poly.map(p => p[0]), zs = poly.map(p => p[1]);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minZ = Math.min(...zs), maxZ = Math.max(...zs);
  const cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
  const rx = (maxX - minX) / 2 + 0.5, rz = (maxZ - minZ) / 2 + 0.5;

  const SEG = 2; // 2m subdivisions
  const cols = Math.max(4, Math.ceil(rx * 2 / SEG));
  const rows = Math.max(4, Math.ceil(rz * 2 / SEG));

  const noise = makeNoise2D(hole.green.undulationSeed || hole.number * 37);
  const positions = new Float32Array((cols+1) * (rows+1) * 3);
  const uvs       = new Float32Array((cols+1) * (rows+1) * 2);
  const indices   = [];

  for (let r = 0; r <= rows; r++) {
    for (let c = 0; c <= cols; c++) {
      const idx = r * (cols+1) + c;
      const wx = cx - rx + c * (rx * 2 / cols);
      const wz = cz - rz + r * (rz * 2 / rows);
      const baseY = heightAt(wx, wz) + 0.04;
      // Low-frequency undulation: two noise octaves at different scales
      const n1 = noise(wx * 0.08, wz * 0.08) * UNDULATION_AMP;
      const n2 = noise(wx * 0.22, wz * 0.22) * UNDULATION_AMP * 0.4;
      positions[idx*3]   = wx;
      positions[idx*3+1] = baseY + n1 + n2;
      positions[idx*3+2] = wz;
      uvs[idx*2] = c / cols; uvs[idx*2+1] = r / rows;
    }
  }

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const a = r*(cols+1)+c, b=a+1, d=(r+1)*(cols+1)+c, e=d+1;
      indices.push(a, d, b, b, d, e);
    }
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('uv',       new THREE.BufferAttribute(uvs, 2));
  geo.setIndex(indices);
  geo.computeVertexNormals();

  const mat = new THREE.MeshLambertMaterial({ color: 0x40c858, side: THREE.FrontSide });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.name = `green_${hole.number}`;
  scene.add(mesh);
  return { mesh, cx, cz, rx, rz, noise };
}

// Build break-line arrows on a green — shown when in putting mode
const ARROW_SPACING = 2.5; // meters between arrows
let _arrowGroup = null;

export function buildBreakArrows(hole, scene) {
  removeBreakArrows(scene);

  const poly = hole.green.polygon;
  if (!poly || poly.length < 3) return;

  const xs = poly.map(p => p[0]), zs = poly.map(p => p[1]);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minZ = Math.min(...zs), maxZ = Math.max(...zs);

  const group = new THREE.Group();
  group.name = 'break_arrows';

  const arrowMat = new THREE.MeshLambertMaterial({ color: 0xffffaa, transparent: true, opacity: 0.75 });

  function pip(px, pz) {
    let inside = false;
    for (let i = 0, j = poly.length-1; i < poly.length; j=i++) {
      const [xi,zi]=[poly[i][0],poly[i][1]], [xj,zj]=[poly[j][0],poly[j][1]];
      if ((zi>pz)!==(zj>pz) && px<((xj-xi)*(pz-zi))/(zj-zi)+xi) inside=!inside;
    }
    return inside;
  }

  const shaftGeo = new THREE.CylinderGeometry(0.04, 0.04, 0.6, 4);
  const headGeo  = new THREE.ConeGeometry(0.12, 0.28, 4);

  for (let x = minX; x <= maxX; x += ARROW_SPACING) {
    for (let z = minZ; z <= maxZ; z += ARROW_SPACING) {
      if (!pip(x, z)) continue;

      const sl = slopeAt(x, z);
      const downX = -sl.nx, downZ = -sl.nz; // slope runs downhill
      const magnitude = Math.hypot(downX, downZ);
      if (magnitude < 0.001) continue;

      const angle = Math.atan2(downX, downZ);
      const y = heightAt(x, z) + 0.06;

      const shaft = new THREE.Mesh(shaftGeo, arrowMat);
      shaft.position.set(x, y + 0.3, z);
      shaft.rotation.y = angle;

      const head = new THREE.Mesh(headGeo, arrowMat);
      head.position.set(x + downX/magnitude*0.45, y + 0.14, z + downZ/magnitude*0.45);
      head.rotation.y = angle;
      head.rotation.z = -Math.PI / 2;
      head.rotation.order = 'YZX';

      group.add(shaft, head);
    }
  }

  scene.add(group);
  _arrowGroup = group;
}

export function removeBreakArrows(scene) {
  if (_arrowGroup) { scene.remove(_arrowGroup); _arrowGroup = null; }
}

// Putting power bar: a simple fill bar (0-100% pace)
// Returns controls for showing/hiding/reading
export function createPuttingBar(container) {
  const wrap = document.createElement('div');
  wrap.id = 'putt-bar';
  wrap.innerHTML = `
    <div class="putt-label">PACE</div>
    <div class="putt-track">
      <div class="putt-fill" id="putt-fill"></div>
      <div class="putt-line" id="putt-line"></div>
    </div>
    <div class="putt-pct" id="putt-pct">0%</div>
  `;
  container.appendChild(wrap);

  let _power = 0, _holding = false, _startTime = 0;
  const MAX_HOLD = 1.4; // seconds for full power

  function update(t) {
    if (!_holding) return;
    const elapsed = (Date.now() / 1000) - _startTime;
    _power = Math.min(elapsed / MAX_HOLD, 1);
    document.getElementById('putt-fill').style.width = `${_power * 100}%`;
    document.getElementById('putt-pct').textContent = `${Math.round(_power * 100)}%`;
  }

  function onPress() { _holding = true; _startTime = Date.now() / 1000; _power = 0; }
  function onRelease() { _holding = false; return _power; }
  function show() { wrap.classList.remove('hidden'); }
  function hide() { wrap.classList.add('hidden'); _power = 0; }

  return { update, onPress, onRelease, show, hide, getPower: () => _power };
}
