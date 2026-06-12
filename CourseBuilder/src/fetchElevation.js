// Samples USGS elevation via OpenTopoData (free, no key, batches of 99).
// Caches result to disk so subsequent builds are instant.
// Retries dropped connections with exponential backoff.

import { existsSync, readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dir = dirname(fileURLToPath(import.meta.url));
const ELEV_CACHE = join(__dir, 'elevation_grid_cache.json');

const TOPO_URL = 'https://api.opentopodata.org/v1/ned10m';
const BATCH    = 99;    // max per request
const DELAY_MS = 1100;  // polite delay between batches
const MAX_RETRIES = 4;

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function fetchBatch(locations, attempt = 0) {
  const body = locations.map(([lat, lng]) => `${lat.toFixed(6)},${lng.toFixed(6)}`).join('|');
  try {
    const res = await fetch(`${TOPO_URL}?locations=${encodeURIComponent(body)}&interpolation=bilinear`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    return (data.results || []).map(r => r.elevation ?? 0);
  } catch (e) {
    if (attempt >= MAX_RETRIES) throw e;
    const wait = 2000 * Math.pow(2, attempt);
    process.stdout.write(` [retry ${attempt + 1} in ${wait / 1000}s]`);
    await sleep(wait);
    return fetchBatch(locations, attempt + 1);
  }
}

export async function sampleElevationGrid(bbox, proj, cellSize = 10, refresh = false) {
  if (!refresh && existsSync(ELEV_CACHE)) {
    console.log('  (using cached elevation grid)');
    return JSON.parse(readFileSync(ELEV_CACHE, 'utf8'));
  }

  const margin = cellSize;
  const x0 = bbox.minX - margin, x1 = bbox.maxX + margin;
  const z0 = bbox.minZ - margin, z1 = bbox.maxZ + margin;

  const cols = Math.ceil((x1 - x0) / cellSize) + 1;
  const rows = Math.ceil((z1 - z0) / cellSize) + 1;

  console.log(`  Elevation grid: ${cols}×${rows} = ${cols * rows} points at ${cellSize}m spacing…`);

  const samples = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const x = x0 + c * cellSize;
      const z = z0 + r * cellSize;
      const { lng, lat } = proj.toLngLat(x, z);
      samples.push({ r, c, lat, lng });
    }
  }

  const elevData = new Float32Array(rows * cols);
  const totalBatches = Math.ceil(samples.length / BATCH);

  for (let i = 0; i < samples.length; i += BATCH) {
    const batch = samples.slice(i, i + BATCH);
    const batchNum = Math.ceil(i / BATCH) + 1;
    process.stdout.write(`\r  Elevation batch ${batchNum}/${totalBatches}…`);
    const elevs = await fetchBatch(batch.map(s => [s.lat, s.lng]));
    for (let j = 0; j < batch.length; j++) {
      const { r, c } = batch[j];
      elevData[r * cols + c] = elevs[j] ?? 0;
    }
    if (i + BATCH < samples.length) await sleep(DELAY_MS);
  }
  console.log(' done.');

  const result = { cols, rows, cellSize, originX: x0, originZ: z0, data: Array.from(elevData) };
  writeFileSync(ELEV_CACHE, JSON.stringify(result));
  console.log('  Elevation grid cached.');
  return result;
}
