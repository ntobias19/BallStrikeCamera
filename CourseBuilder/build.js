#!/usr/bin/env node
// CourseBuilder — generates a static course JSON for TrueCarry_Course.
// Usage: node build.js [output_path]
// Requires Node 18+ (built-in fetch).

import { fetchPinchbrookOSM }     from './src/fetchOSM.js';
import { fetchPinchbrookBackend } from './src/fetchBackend.js';
import { sampleElevationGrid }    from './src/fetchElevation.js';
import { mergeCourse }            from './src/mergeCourse.js';
import { makeProjector }          from './src/geoUtils.js';
import { writeFileSync, mkdirSync } from 'fs';
import { dirname }                  from 'path';

const OUTPUT = process.argv[2] || '../TrueCarry_Course/courses/pinchbrook.json';

async function main() {
  console.log('CourseBuilder — Pinch Brook Golf Course');
  console.log('======================================');

  // Step 1: Backend metadata
  const backendData = await fetchPinchbrookBackend();
  console.log(`  Found: ${backendData.name} (${backendData.city}, ${backendData.state})`);

  // Step 2: OSM data
  const osmData = await fetchPinchbrookOSM();
  console.log(`  OSM: ${osmData.holeLines.length} holes, ${osmData.holeGreenRings.size} greens, ${[...osmData.holeBunkers.values()].flat().length} bunkers, ${osmData.woods.length} wood areas`);

  // Step 3: Elevation grid
  const proj = makeProjector(backendData.lat, backendData.lng);
  const allCoords = [
    ...osmData.boundary,
    ...osmData.holeLines.map(h => h.teeLatLng),
    ...osmData.holeLines.map(h => h.greenLatLng),
  ];
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  for (const [lat, lng] of allCoords) {
    const { x, z } = proj.toXZ(lat, lng);
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
  }

  const elevData = await sampleElevationGrid({ minX, maxX, minZ, maxZ }, proj, 30);

  // Step 4: Merge
  console.log('  Merging data sources…');
  const course = mergeCourse(osmData, backendData, elevData);

  // Step 5: Write output
  mkdirSync(dirname(OUTPUT), { recursive: true });
  writeFileSync(OUTPUT, JSON.stringify(course, null, 2));
  const kb = Math.round(writeFileSync.toString().length / 1024);
  const stat = (await import('fs')).statSync(OUTPUT);
  console.log(`\nDone! Written to ${OUTPUT} (${(stat.size / 1024).toFixed(1)} KB)`);
  console.log(`  ${course.holes.length} holes · par ${course.meta.par} · ${course.trees.length} trees · ${course.heightmap.cols}×${course.heightmap.rows} heightmap`);
}

main().catch(err => { console.error('Build failed:', err); process.exit(1); });
