// Combines OSM + backend + elevation data into the final course JSON.

import {
  makeProjector, ringToXZ, centroidXZ, dist2D,
  corridorPolygon, randomPointsInPoly, polyArea, pointInPolygon,
} from './geoUtils.js';

// Half-width of generated fairway corridors per par
const FAIRWAY_HW = { 3: 12, 4: 20, 5: 24 };

// Generate a simple corridor fairway from tee to green
function buildFairwayCorridor(teeXZ, greenXZ, par) {
  const hw = FAIRWAY_HW[par] ?? 18;
  const dx = greenXZ[0] - teeXZ[0];
  const dz = greenXZ[1] - teeXZ[1];
  const len = Math.hypot(dx, dz) || 1;
  const nx = dx / len, nz = dz / len;
  // Start 5m past tee, stop 12m short of green
  const start = [teeXZ[0] + nx * 5, teeXZ[1] + nz * 5];
  const end   = [greenXZ[0] - nx * 12, greenXZ[1] - nz * 12];
  return corridorPolygon([start, end], hw);
}

// Build tree instances from wood polygons, avoiding greens/bunkers
function buildTrees(woods, globalBunkers, globalGreens, treeNodes, proj, rng) {
  const trees = [];

  // Explicit OSM tree nodes
  for (const [lat, lng] of treeNodes) {
    const { x, z } = proj.toXZ(lat, lng);
    trees.push({ x, z, r: 2.8 + rng() * 1.6, isPine: rng() < 0.25 });
  }

  // Random fill inside wood polygons
  const exclusions = [...globalBunkers, ...globalGreens];
  for (const poly of woods) {
    if (!poly.length) continue;
    const polyXZ = ringToXZ(poly, proj);
    const area = polyArea(polyXZ);
    const count = Math.floor(area / 48); // ~1 tree per 48m²
    const pts = randomPointsInPoly(polyXZ, count);
    for (const [x, z] of pts) {
      const blocked = exclusions.some(ex => pointInPolygon(x, z, ex));
      if (!blocked) trees.push({ x, z, r: 2.5 + rng() * 2.0, isPine: rng() < 0.3 });
    }
  }
  return trees;
}

// Seeded pseudo-random (simple LCG so output is deterministic)
function makeRNG(seed) {
  let s = seed | 0;
  return () => {
    s = (s * 1664525 + 1013904223) & 0xffffffff;
    return (s >>> 0) / 0xffffffff;
  };
}

export function mergeCourse(osmData, backendData, elevData) {
  const proj = makeProjector(backendData.lat, backendData.lng);

  // Course boundary in local coords
  const boundary = osmData.boundary.length
    ? ringToXZ(osmData.boundary, proj)
    : [];

  // Compute bbox from boundary or holeLines
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  const allPts = [
    ...osmData.boundary,
    ...osmData.holeLines.map(h => h.teeLatLng),
    ...osmData.holeLines.map(h => h.greenLatLng),
  ];
  for (const [lat, lng] of allPts) {
    const { x, z } = proj.toXZ(lat, lng);
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
  }

  // Build holes
  const holes = [];
  const allGreenPolys = [];
  const allBunkerPolys = [];

  let totalPar = 0;

  for (const hl of osmData.holeLines) {
    const ref = hl.ref;
    const par = hl.par;
    totalPar += par;

    const teeXZ   = [proj.toXZ(hl.teeLatLng[0],   hl.teeLatLng[1]).x,
                     proj.toXZ(hl.teeLatLng[0],   hl.teeLatLng[1]).z];
    const greenXZ = [proj.toXZ(hl.greenLatLng[0], hl.greenLatLng[1]).x,
                     proj.toXZ(hl.greenLatLng[0], hl.greenLatLng[1]).z];

    const greenRingGeo  = osmData.holeGreenRings.get(ref);
    const greenPoly     = greenRingGeo ? ringToXZ(greenRingGeo, proj) : null;
    if (greenPoly) allGreenPolys.push(greenPoly);

    const bunkerRings = (osmData.holeBunkers.get(ref) || []).map(r => ringToXZ(r, proj));
    const waterRings  = (osmData.holeWater.get(ref) || []).map(r => ringToXZ(r, proj));

    for (const b of bunkerRings) allBunkerPolys.push(b);

    // Fairway: use OSM if available, otherwise generate corridor
    const osmFw = osmData.holeFairways.get(ref);
    const fairway = osmFw
      ? ringToXZ(osmFw, proj)
      : buildFairwayCorridor(teeXZ, greenXZ, par);

    const pathXZ = hl.path.length > 2
      ? hl.path.map(p => [proj.toXZ(p[0], p[1]).x, proj.toXZ(p[0], p[1]).z])
      : [teeXZ, greenXZ];

    holes.push({
      number:  ref,
      par,
      tee:     teeXZ,
      green: {
        center:  greenXZ,
        polygon: greenPoly || null,
        undulationSeed: ref * 37,
      },
      path:    pathXZ,
      fairway,
      bunkers: bunkerRings,
      water:   waterRings,
    });
  }

  // Global trees
  const rng = makeRNG(9999);
  const trees = buildTrees(osmData.woods, allBunkerPolys, allGreenPolys, osmData.treeNodes, proj, rng);

  // Global water (hazards not attributed to a single hole)
  const globalWater = [];

  const meta = {
    name:    backendData.name,
    city:    backendData.city,
    state:   backendData.state,
    country: backendData.country,
    par:     totalPar,
    stimp:   10,
    built:   new Date().toISOString().slice(0, 10),
  };

  return {
    meta,
    origin: { lat: backendData.lat, lng: backendData.lng },
    bbox:   { minX, maxX, minZ, maxZ },
    boundary,
    heightmap: elevData,
    holes,
    trees,
    globalWater,
  };
}
