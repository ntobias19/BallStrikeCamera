// Full-course terrain: loads course JSON, builds one world mesh covering all 18 holes,
// surface splat-map texture, tree instances, water, and physics helpers.

import * as THREE from 'three';

const SURF = {
  ROUGH:   'rough',
  FAIRWAY: 'fairway',
  GREEN:   'green',
  BUNKER:  'bunker',
  WATER:   'water',
  OOB:     'oob',
};
export { SURF };

// Colors for canvas splat map
const SURF_COLOR = {
  [SURF.ROUGH]:   '#2e5a1a',
  [SURF.FAIRWAY]: '#4a8a22',
  [SURF.GREEN]:   '#3db84c',
  [SURF.BUNKER]:  '#d4b96a',
  [SURF.WATER]:   '#2060a8',
  [SURF.OOB]:     '#1a3010',
};

// Physics properties per surface (same shape as TrueCarry_Sim SURF_PROPS)
export const SURF_PROPS = {
  [SURF.ROUGH]:   { restitution: 0.22, friction: 0.72, spin: 0.45, run: 0.5 },
  [SURF.FAIRWAY]: { restitution: 0.32, friction: 0.58, spin: 0.82, run: 1.6 },
  [SURF.GREEN]:   { restitution: 0.18, friction: 0.88, spin: 1.00, run: 1.0 },
  [SURF.BUNKER]:  { restitution: 0.03, friction: 0.95, spin: 0.40, run: 0.2 },
  [SURF.WATER]:   { restitution: 0.00, friction: 1.00, spin: 0.00, run: 0.0 },
  [SURF.OOB]:     { restitution: 0.20, friction: 0.70, spin: 0.40, run: 0.5 },
};

// ---------- Point-in-polygon (ray casting) ----------
function pip(px, pz, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, zi] = poly[i], [xj, zj] = poly[j];
    if ((zi > pz) !== (zj > pz) && px < ((xj - xi) * (pz - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}

// ---------- Heightmap bilinear interpolation ----------
function makeHeightmap(hm) {
  const minElev = Math.min(...hm.data);
  const norm = hm.data.map(e => e - minElev);

  function heightAt(x, z) {
    const col = (x - hm.originX) / hm.cellSize;
    const row = (z - hm.originZ) / hm.cellSize;
    if (col < 0 || col > hm.cols - 1 || row < 0 || row > hm.rows - 1) return 0;
    const c0 = Math.floor(col), c1 = Math.min(c0 + 1, hm.cols - 1);
    const r0 = Math.floor(row), r1 = Math.min(r0 + 1, hm.rows - 1);
    const fc = col - c0, fr = row - r0;
    const h00 = norm[r0 * hm.cols + c0];
    const h10 = norm[r0 * hm.cols + c1];
    const h01 = norm[r1 * hm.cols + c0];
    const h11 = norm[r1 * hm.cols + c1];
    return h00 * (1-fc)*(1-fr) + h10 * fc*(1-fr) + h01 * (1-fc)*fr + h11 * fc*fr;
  }
  return { heightAt, minElev };
}

// ---------- Surface lookup structure (quad-tree would be better; grid is fine for our size) ----------
function makeSurfaceMap(courseData, hmOriginX, hmOriginZ, hmWidth, hmDepth) {
  // Build a lookup grid of surface types
  const RES = 4;  // meters per surface cell
  const cols = Math.ceil(hmWidth / RES) + 1;
  const rows = Math.ceil(hmDepth / RES) + 1;
  const grid = new Uint8Array(cols * rows); // 0=rough,1=fairway,2=green,3=bunker,4=water

  const ROUGH=0, FAIRWAY=1, GREEN=2, BUNKER=3, WATER=4;

  // Paint order: fairway first, then bunker/water on top, green on top of those
  function paint(poly, val) {
    if (!poly || poly.length < 3) return;
    const xs = poly.map(p => p[0]), zs = poly.map(p => p[1]);
    const minXi = Math.max(0, Math.floor((Math.min(...xs) - hmOriginX) / RES));
    const maxXi = Math.min(cols-1, Math.ceil((Math.max(...xs) - hmOriginX) / RES));
    const minZi = Math.max(0, Math.floor((Math.min(...zs) - hmOriginZ) / RES));
    const maxZi = Math.min(rows-1, Math.ceil((Math.max(...zs) - hmOriginZ) / RES));
    for (let r = minZi; r <= maxZi; r++) {
      for (let c = minXi; c <= maxXi; c++) {
        const wx = hmOriginX + c * RES;
        const wz = hmOriginZ + r * RES;
        if (pip(wx, wz, poly)) grid[r * cols + c] = val;
      }
    }
  }

  for (const hole of courseData.holes) {
    paint(hole.fairway, FAIRWAY);
  }
  for (const hole of courseData.holes) {
    for (const b of hole.bunkers) paint(b, BUNKER);
    for (const w of hole.water) paint(w, WATER);
  }
  for (const hole of courseData.holes) {
    if (hole.green.polygon) paint(hole.green.polygon, GREEN);
  }

  function surfaceAt(x, z) {
    const col = Math.round((x - hmOriginX) / RES);
    const row = Math.round((z - hmOriginZ) / RES);
    if (col < 0 || col >= cols || row < 0 || row >= rows) return SURF.OOB;
    const v = grid[row * cols + col];
    return [SURF.ROUGH, SURF.FAIRWAY, SURF.GREEN, SURF.BUNKER, SURF.WATER][v] || SURF.OOB;
  }
  return { surfaceAt, grid, cols, rows };
}

// ---------- Canvas splat texture ----------
function buildSplatTexture(courseData, hmOriginX, hmOriginZ, hmWidth, hmDepth) {
  const TEX_W = 1024, TEX_H = Math.round(1024 * hmDepth / hmWidth);
  const scaleX = TEX_W / hmWidth;
  const scaleZ = TEX_H / hmDepth;

  const canvas = document.createElement('canvas');
  canvas.width = TEX_W; canvas.height = TEX_H;
  const ctx = canvas.getContext('2d');

  function toCanvas(x, z) {
    return [(x - hmOriginX) * scaleX, (z - hmOriginZ) * scaleZ];
  }

  function fillPoly(poly, color) {
    if (!poly || poly.length < 3) return;
    ctx.beginPath();
    ctx.fillStyle = color;
    const [cx, cz] = toCanvas(poly[0][0], poly[0][1]);
    ctx.moveTo(cx, cz);
    for (let i = 1; i < poly.length; i++) {
      const [px, pz] = toCanvas(poly[i][0], poly[i][1]);
      ctx.lineTo(px, pz);
    }
    ctx.closePath();
    ctx.fill();
  }

  // Background: rough
  ctx.fillStyle = SURF_COLOR[SURF.ROUGH];
  ctx.fillRect(0, 0, TEX_W, TEX_H);

  // Course boundary slightly lighter
  if (courseData.boundary?.length > 2) {
    fillPoly(courseData.boundary, '#356c1e');
  }

  // Fairways
  for (const hole of courseData.holes) {
    fillPoly(hole.fairway, SURF_COLOR[SURF.FAIRWAY]);
  }

  // Water hazards
  for (const hole of courseData.holes) {
    for (const w of hole.water) fillPoly(w, SURF_COLOR[SURF.WATER]);
  }

  // Bunkers
  for (const hole of courseData.holes) {
    for (const b of hole.bunkers) fillPoly(b, SURF_COLOR[SURF.BUNKER]);
  }

  // Greens
  for (const hole of courseData.holes) {
    if (hole.green.polygon) fillPoly(hole.green.polygon, SURF_COLOR[SURF.GREEN]);
  }

  // Tee box markers (small white rects) — approximate
  ctx.fillStyle = '#d8ead0';
  for (const hole of courseData.holes) {
    const [tx, tz] = toCanvas(hole.tee[0], hole.tee[1]);
    ctx.fillRect(tx - 3, tz - 3, 6, 6);
  }

  return new THREE.CanvasTexture(canvas);
}

// ---------- Terrain mesh ----------
function buildTerrainMesh(courseData, heightAt, hmOriginX, hmOriginZ, hmW, hmD) {
  const SEG_SIZE = 10; // 10m between vertices
  const cols = Math.floor(hmW / SEG_SIZE) + 1;
  const rows = Math.floor(hmD / SEG_SIZE) + 1;

  const positions = new Float32Array(cols * rows * 3);
  const uvs       = new Float32Array(cols * rows * 2);
  const indices   = [];

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const idx = r * cols + c;
      const x = hmOriginX + c * SEG_SIZE;
      const z = hmOriginZ + r * SEG_SIZE;
      const y = heightAt(x, z);
      positions[idx*3]   = x;
      positions[idx*3+1] = y;
      positions[idx*3+2] = z;
      uvs[idx*2]   = c / (cols-1);
      uvs[idx*2+1] = r / (rows-1);
    }
  }

  for (let r = 0; r < rows-1; r++) {
    for (let c = 0; c < cols-1; c++) {
      const a = r*cols+c, b=a+1, d=(r+1)*cols+c, e=d+1;
      indices.push(a, d, b, b, d, e);
    }
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('uv',       new THREE.BufferAttribute(uvs, 2));
  geo.setIndex(indices);
  geo.computeVertexNormals();

  const splatTex = buildSplatTexture(courseData, hmOriginX, hmOriginZ, hmW, hmD);
  splatTex.wrapS = splatTex.wrapT = THREE.ClampToEdgeWrapping;

  const mat = new THREE.MeshLambertMaterial({ map: splatTex });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.name = 'terrain';
  return mesh;
}

// ---------- Tree instances ----------
const TREE_FAR = 200; // beyond this, only billboard (TODO: LOD)

function buildTrees(trees, heightAt, scene) {
  if (!trees?.length) return;

  // Two types: deciduous and pine
  const geoTrunkD = new THREE.CylinderGeometry(0.22, 0.28, 4.0, 5);
  const geoCanopyD = new THREE.SphereGeometry(3.2, 5, 4);
  const geoTrunkP = new THREE.CylinderGeometry(0.18, 0.24, 5.0, 5);
  const geoCanopyP = new THREE.ConeGeometry(2.4, 6.0, 6);

  const matTrunk  = new THREE.MeshLambertMaterial({ color: 0x5c3a1e });
  const matLeaves = new THREE.MeshLambertMaterial({ color: 0x2d5a18 });
  const matPine   = new THREE.MeshLambertMaterial({ color: 0x1e4012 });

  const deciduous = trees.filter(t => !t.isPine);
  const pines     = trees.filter(t =>  t.isPine);

  function instanceGroup(list, geoTrunk, geoCan, matT, matC, tunkH, canOffset) {
    if (!list.length) return;
    const instTrunk = new THREE.InstancedMesh(geoTrunk, matT, list.length);
    const instCan   = new THREE.InstancedMesh(geoCan,   matC, list.length);
    instTrunk.castShadow = instCan.castShadow = true;

    const dummy = new THREE.Object3D();
    list.forEach((t, i) => {
      const y = heightAt(t.x, t.z);
      const s = (t.r / 3.2);

      dummy.position.set(t.x, y + tunkH * s * 0.5, t.z);
      dummy.scale.set(s, s, s);
      dummy.updateMatrix();
      instTrunk.setMatrixAt(i, dummy.matrix);

      dummy.position.set(t.x, y + tunkH * s + canOffset * s, t.z);
      dummy.scale.set(s, s, s);
      dummy.updateMatrix();
      instCan.setMatrixAt(i, dummy.matrix);
    });

    instTrunk.instanceMatrix.needsUpdate = true;
    instCan.instanceMatrix.needsUpdate = true;
    scene.add(instTrunk, instCan);
  }

  instanceGroup(deciduous, geoTrunkD, geoCanopyD, matTrunk, matLeaves, 4.0, 3.2);
  instanceGroup(pines,     geoTrunkP, geoCanopyP, matTrunk, matPine,   5.0, 3.0);
}

// ---------- Water planes (animated in main.js) ----------
function buildWaterPlanes(courseData, heightAt, scene) {
  const planes = [];
  for (const hole of courseData.holes) {
    for (const w of hole.water) {
      if (w.length < 3) continue;
      const xs = w.map(p => p[0]), zs = w.map(p => p[1]);
      const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
      const cz = (Math.min(...zs) + Math.max(...zs)) / 2;
      const rx = (Math.max(...xs) - Math.min(...xs)) / 2;
      const rz = (Math.max(...zs) - Math.min(...zs)) / 2;
      const y = heightAt(cx, cz) + 0.05;

      const geo = new THREE.PlaneGeometry(rx * 2 + 1, rz * 2 + 1);
      geo.rotateX(-Math.PI / 2);
      const mat = new THREE.MeshStandardMaterial({
        color: 0x1a4a88, roughness: 0.1, metalness: 0.6, transparent: true, opacity: 0.85,
      });
      const mesh = new THREE.Mesh(geo, mat);
      mesh.position.set(cx, y, cz);
      mesh.receiveShadow = true;
      scene.add(mesh);
      planes.push(mesh);
    }
  }
  return planes;
}

// ---------- Main export ----------
let _heightAt, _surfaceAt, _hm;

export function buildWorld(courseData, scene) {
  const hm = courseData.heightmap;
  const { heightAt, minElev } = makeHeightmap(hm);
  _heightAt = heightAt;
  _hm = hm;

  const hmOriginX = hm.originX;
  const hmOriginZ = hm.originZ;
  const hmWidth   = (hm.cols - 1) * hm.cellSize;
  const hmDepth   = (hm.rows - 1) * hm.cellSize;

  const surfMap = makeSurfaceMap(courseData, hmOriginX, hmOriginZ, hmWidth, hmDepth);
  _surfaceAt = surfMap.surfaceAt;

  const terrain = buildTerrainMesh(courseData, heightAt, hmOriginX, hmOriginZ, hmWidth, hmDepth);
  scene.add(terrain);

  buildTrees(courseData.trees, heightAt, scene);
  const waterPlanes = buildWaterPlanes(courseData, heightAt, scene);

  // Hole number markers on greens
  buildHoleMarkers(courseData, heightAt, scene);

  return { terrain, waterPlanes };
}

function buildHoleMarkers(courseData, heightAt, scene) {
  for (const hole of courseData.holes) {
    const [gx, gz] = hole.green.center;
    const y = heightAt(gx, gz) + 2.8;
    // Flagstick
    const stickGeo = new THREE.CylinderGeometry(0.05, 0.05, 2.8, 4);
    const stickMat = new THREE.MeshLambertMaterial({ color: 0xffffff });
    const stick = new THREE.Mesh(stickGeo, stickMat);
    stick.position.set(gx, y - 1.4, gz);

    // Flag
    const flagGeo = new THREE.PlaneGeometry(0.8, 0.5);
    const flagMat = new THREE.MeshLambertMaterial({ color: 0xff2222, side: THREE.DoubleSide });
    const flag = new THREE.Mesh(flagGeo, flagMat);
    flag.position.set(gx + 0.4, y, gz);
    scene.add(stick, flag);
  }
}

export function heightAt(x, z) {
  return _heightAt ? _heightAt(x, z) : 0;
}

export function surfaceAt(x, z) {
  return _surfaceAt ? _surfaceAt(x, z) : SURF.ROUGH;
}

// Slope (normal) at a point — used by putting physics
export function slopeAt(x, z) {
  const eps = 0.5;
  const h0  = heightAt(x, z);
  const hpx = heightAt(x + eps, z) - h0;
  const hpz = heightAt(x, z + eps) - h0;
  // Normal: cross product of (eps, hpx, 0) and (0, hpz, eps)
  const len = Math.hypot(-hpx, eps, -hpz) || 1;
  return { nx: -hpx / len, ny: eps / len, nz: -hpz / len };
}

// Camera position for teeing up on a hole
export function holeCameraPos(hole, behindMeters = 18) {
  const [tx, tz] = hole.tee;
  const [gx, gz] = hole.green.center;
  const dx = tx - gx, dz = tz - gz;
  const len = Math.hypot(dx, dz) || 1;
  return {
    cx: tx + (dx / len) * behindMeters,
    cy: heightAt(tx, tz) + 2.2,
    cz: tz + (dz / len) * behindMeters,
    tx: gx, ty: heightAt(gx, gz) + 0.5, tz: gz,
  };
}

// Minimap: draw all holes on a canvas
export function drawMinimapBase(courseData, canvas) {
  const ctx = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height;
  const bbox = courseData.bbox;
  const scaleX = W / (bbox.maxX - bbox.minX);
  const scaleZ = H / (bbox.maxZ - bbox.minZ);

  function toC(x, z) {
    return [(x - bbox.minX) * scaleX, (z - bbox.minZ) * scaleZ];
  }

  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = '#1e3a10';
  ctx.fillRect(0, 0, W, H);

  function drawPoly(poly, color) {
    if (!poly?.length) return;
    ctx.beginPath();
    ctx.fillStyle = color;
    ctx.strokeStyle = color;
    const [px, pz] = toC(poly[0][0], poly[0][1]);
    ctx.moveTo(px, pz);
    for (let i = 1; i < poly.length; i++) {
      const [qx, qz] = toC(poly[i][0], poly[i][1]);
      ctx.lineTo(qx, qz);
    }
    ctx.closePath();
    ctx.fill();
  }

  for (const hole of courseData.holes) {
    drawPoly(hole.fairway, '#3a6a18');
    for (const b of hole.bunkers) drawPoly(b, '#c8a84a');
    for (const w of hole.water) drawPoly(w, '#2060a8');
    if (hole.green.polygon) drawPoly(hole.green.polygon, '#50cc60');
  }

  // Hole paths (thin lines)
  for (const hole of courseData.holes) {
    if (hole.path?.length > 1) {
      ctx.strokeStyle = 'rgba(255,255,255,0.25)';
      ctx.lineWidth = 0.5;
      ctx.beginPath();
      const [px, pz] = toC(hole.path[0][0], hole.path[0][1]);
      ctx.moveTo(px, pz);
      for (let i = 1; i < hole.path.length; i++) {
        const [qx, qz] = toC(hole.path[i][0], hole.path[i][1]);
        ctx.lineTo(qx, qz);
      }
      ctx.stroke();
    }
  }

  return { toC, scaleX, scaleZ };
}
