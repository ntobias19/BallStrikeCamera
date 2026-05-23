#!/usr/bin/env node
// export-csv.mjs — convert baked NDJSON (from `prebake.mjs --emit-all`) into flat CSV files.
// No database required. Produces a relational set you can open in Excel/Sheets or import anywhere.
//
// Usage: node export-csv.mjs <input.ndjson> <outDir>
//   node export-csv.mjs /tmp/osm_all.ndjson /tmp/osm_csv
//
// Output:
//   courses.csv      one row per course (id, name, location, holes, total par)
//   tees.csv         one row per tee box (yards, rating, slope)
//   holes.csv        one row per hole (par, handicap, key coordinates)
//   coordinates.csv  one row per point of interest (green F/C/B, tee, hazards)
//   polygons.csv     one row per polygon vertex (green/fairway/bunker/water outlines)

import fs from "node:fs";
import path from "node:path";

const [input, outDir] = process.argv.slice(2);
if (!input || !outDir) {
  console.error("usage: node export-csv.mjs <input.ndjson> <outDir>");
  process.exit(1);
}
fs.mkdirSync(outDir, { recursive: true });

const q = (v) => {
  if (v === null || v === undefined) return "";
  const s = String(v);
  return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};
const row = (arr) => arr.map(q).join(",") + "\n";

const courses = [row(["course_id", "name", "city", "state", "country", "latitude", "longitude", "holes", "total_par", "tee_count", "source"])];
const tees = [row(["course_id", "tee_id", "name", "color", "total_yards", "rating", "slope"])];
const holes = [row(["course_id", "hole", "par", "handicap", "green_center_lat", "green_center_lng", "green_front_lat", "green_front_lng", "green_back_lat", "green_back_lng", "tee_lat", "tee_lng"])];
const coords = [row(["course_id", "hole", "poi", "lat", "lng"])];
const polys = [row(["course_id", "hole", "surface", "vertex_index", "lat", "lng"])];

const c = (p) => (p ? [p.latitude, p.longitude] : ["", ""]);

let nCourses = 0, nHoles = 0;
const lines = fs.readFileSync(input, "utf8").split("\n").filter(Boolean);
for (const line of lines) {
  let course;
  try { course = JSON.parse(line); } catch { continue; }
  nCourses++;
  const id = course.id;
  const totalPar = (course.holes || []).reduce((s, h) => s + (h.par || 0), 0);
  courses.push(row([id, course.name, course.city, course.state, course.country, course.latitude, course.longitude, (course.holes || []).length, totalPar, (course.tee_boxes || []).length, course.source]));

  for (const t of course.tee_boxes || []) {
    tees.push(row([id, t.id, t.name, t.color, t.total_yards, t.rating ?? "", t.slope ?? ""]));
  }

  for (const h of course.holes || []) {
    nHoles++;
    const [gcLat, gcLng] = c(h.green_center_coordinate);
    const [gfLat, gfLng] = c(h.green_front_coordinate);
    const [gbLat, gbLng] = c(h.green_back_coordinate);
    const [tLat, tLng] = c(h.tee_coordinate);
    holes.push(row([id, h.number, h.par, h.handicap ?? "", gcLat, gcLng, gfLat, gfLng, gbLat, gbLng, tLat, tLng]));

    // POIs (one row each)
    if (h.green_center_coordinate) coords.push(row([id, h.number, "GreenCenter", h.green_center_coordinate.latitude, h.green_center_coordinate.longitude]));
    if (h.green_front_coordinate) coords.push(row([id, h.number, "GreenFront", h.green_front_coordinate.latitude, h.green_front_coordinate.longitude]));
    if (h.green_back_coordinate) coords.push(row([id, h.number, "GreenBack", h.green_back_coordinate.latitude, h.green_back_coordinate.longitude]));
    if (h.tee_coordinate) coords.push(row([id, h.number, "Tee", h.tee_coordinate.latitude, h.tee_coordinate.longitude]));
    for (const z of h.hazards || []) {
      if (z.coordinate) coords.push(row([id, h.number, z.type || "hazard", z.coordinate.latitude, z.coordinate.longitude]));
    }

    // Polygon vertices: green + fairway + bunkers + water
    const addPoly = (surface, ring) => {
      (ring?.coordinates || []).forEach((pt, i) => polys.push(row([id, h.number, surface, i, pt.latitude, pt.longitude])));
    };
    addPoly("green", h.green_polygon);
    addPoly("fairway", h.fairway_polygon);
    (h.bunker_polygons || []).forEach((bp) => addPoly("bunker", bp));
    (h.water_polygons || []).forEach((wp) => addPoly("water", wp));
  }
}

fs.writeFileSync(path.join(outDir, "courses.csv"), courses.join(""));
fs.writeFileSync(path.join(outDir, "tees.csv"), tees.join(""));
fs.writeFileSync(path.join(outDir, "holes.csv"), holes.join(""));
fs.writeFileSync(path.join(outDir, "coordinates.csv"), coords.join(""));
fs.writeFileSync(path.join(outDir, "polygons.csv"), polys.join(""));

console.log(`Wrote CSVs to ${outDir}`);
console.log(`  courses:     ${nCourses}`);
console.log(`  holes:       ${nHoles}`);
console.log(`  tee rows:    ${tees.length - 1}`);
console.log(`  POI rows:    ${coords.length - 1}`);
console.log(`  polygon pts: ${polys.length - 1}`);
