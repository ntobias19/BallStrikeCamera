#!/usr/bin/env node
// transform-geometry.mjs — convert geometry-bearing courses from courses_combined.jsonl into the
// app's GolfCourse JSON, gzip each, and (optionally) upload to Supabase Storage as
// course-geometry/<course_id>.json.gz. The iOS app fetches + gunzips + decodes on course load.
//
// Pass 1 (measure): node transform-geometry.mjs <jsonl> --measure
// Pass 2 (upload):  SUPABASE_URL=.. SUPABASE_KEY=.. node transform-geometry.mjs <jsonl> --upload [--limit N]

import fs from "node:fs";
import readline from "node:readline";
import zlib from "node:zlib";
import crypto from "node:crypto";

// Deterministic UUIDv5 from the slug — MUST match upload-courses.mjs so the Storage key equals
// the course's `id` in the catalog (and is always an ASCII-safe key).
const NS = "6f9619ff-8b86-d011-b42d-00cf4fc964ff";
function uuidv5(name, ns = NS) {
  const nsBytes = Buffer.from(ns.replace(/-/g, ""), "hex");
  const hash = crypto.createHash("sha1").update(Buffer.concat([nsBytes, Buffer.from(name)])).digest();
  const b = Buffer.from(hash.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50; b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.toString("hex");
  return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}

const input = process.argv[2];
const MEASURE = process.argv.includes("--measure");
const UPLOAD = process.argv.includes("--upload");
const limArg = process.argv.indexOf("--limit");
const LIMIT = limArg > -1 ? parseInt(process.argv[limArg + 1], 10) : Infinity;
if (!input) { console.error("usage: node transform-geometry.mjs <jsonl> --measure|--upload [--limit N]"); process.exit(1); }

let supabase = null, BUCKET = "course-geometry";
if (UPLOAD) {
  const { createClient } = await import("@supabase/supabase-js");
  supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY, { auth: { persistSession: false } });
}

const co = (p) => (p && (p.latitude ?? p.lat) != null) ? { latitude: p.latitude ?? p.lat, longitude: p.longitude ?? p.lng ?? p.long } : null;
const ring = (arr) => Array.isArray(arr) && arr.length >= 3 ? { coordinates: arr.map(co).filter(Boolean) } : null;
const clean = (o) => { for (const k of Object.keys(o)) if (o[k] === null) delete o[k]; return o; };

// Map one combined-feed course → app GolfCourse JSON (snake_case to match the decoder).
function toGolfCourse(o) {
  const c = o.course || {};
  const holesIn = o.holes || [];
  // Aggregate tee sets from per-hole tees.
  const teeAgg = new Map(); // tee_set_id -> {name,color,yards}
  for (const h of holesIn) for (const t of h.tees || []) {
    const k = t.tee_set_id || t.tee_name || "tee";
    const a = teeAgg.get(k) || { id: k, name: t.tee_name || "Tee", color: "White", total_yards: 0 };
    a.total_yards += t.yards || 0;
    teeAgg.set(k, a);
  }
  for (const ts of o.tee_sets || []) {
    const a = teeAgg.get(ts.id || ts.tee_set_id || ts.name);
    if (a) { a.rating = ts.rating ?? a.rating; a.slope = ts.slope ?? a.slope; if (ts.color) a.color = ts.color; }
  }
  const teeBoxes = [...teeAgg.values()];
  if (!teeBoxes.length) teeBoxes.push({ id: "gps", name: "Course GPS", color: "Gray", total_yards: 0 });

  const holes = holesIn.map((h) => {
    const g = h.green || {};
    const teeYards = {}; const teeCoordByBox = {};
    let teeCoord = null;
    for (const t of h.tees || []) {
      const k = t.tee_set_id || t.tee_name || "tee";
      if (t.yards) teeYards[k] = t.yards;
      const tc = co(t.coordinate);
      if (tc) { teeCoordByBox[k] = tc; teeCoord = teeCoord || tc; }
    }
    return clean({
      id: h.hole_id || `${o.course_id}-hole-${h.number}`,
      course_id: o.course_id,
      number: h.number,
      par: h.par || 4,
      handicap: h.handicap ?? h.stroke_index ?? null,
      tee_yards_by_tee_box: teeYards,
      green_front_coordinate: co(g.front),
      green_center_coordinate: co(g.center),
      green_back_coordinate: co(g.back),
      tee_coordinate_by_tee_box: Object.keys(teeCoordByBox).length ? teeCoordByBox : null,
      path_coordinates: (h.path || []).map(co).filter(Boolean),
      hazards: (h.hazards || []).map((z, i) => clean({
        id: `${o.course_id}-${h.number}-hz-${i}`,
        type: (z.kind || z.type || "other").toLowerCase().includes("water") ? "water"
            : (z.kind || z.type || "").toLowerCase().includes("bunker") ? "bunker" : "other",
        coordinate: co(z.coordinate || z.center),
      })).filter(z => z.coordinate),
      tee_coordinate: teeCoord,
      green_polygon: ring(g.polygon),
      fairway_polygon: ring(h.fairway_polygon),
      bunker_polygons: (h.hazards || []).filter(z => (z.kind || z.type || "").toLowerCase().includes("bunker") && Array.isArray(z.polygon)).map(z => ring(z.polygon)).filter(Boolean),
      water_polygons: (h.hazards || []).filter(z => (z.kind || z.type || "").toLowerCase().includes("water") && Array.isArray(z.polygon)).map(z => ring(z.polygon)).filter(Boolean),
    });
  });

  const now = new Date().toISOString();
  return {
    id: o.course_id,
    name: c.name || c.club_name || "Golf Course",
    city: c.city || "", state: c.state || "", country: c.country || "US",
    latitude: c.latitude ?? null, longitude: c.longitude ?? null,
    holes, tee_boxes: teeBoxes,
    source: "openStreetMap", cached_at: now,
    geometry_metadata: { state: "accepted", confidence: 1.0, source: "osm", schema_version: 3, generated_by: "combined_feed", validation_errors: [], updated_at: now },
  };
}

function hasGeometry(o) {
  return (o.holes || []).some(h => h?.green?.center && (h.green.center.latitude ?? h.green.center.lat) != null);
}

const rl = readline.createInterface({ input: fs.createReadStream(input), crlfDelay: Infinity });
let n = 0, geom = 0, gzTotal = 0, rawTotal = 0, uploaded = 0;
for await (const line of rl) {
  if (!line.trim()) continue;
  let o; try { o = JSON.parse(line); } catch { continue; }
  n++;
  if (!hasGeometry(o)) continue;
  geom++;
  if (geom > LIMIT) break;
  const gc = toGolfCourse(o);
  const json = JSON.stringify(gc);
  const gz = zlib.gzipSync(json, { level: 9 });
  rawTotal += Buffer.byteLength(json);
  gzTotal += gz.length;
  if (UPLOAD) {
    const key = `${uuidv5(o.course_id || o.slug)}.json.gz`;   // = courses.id, ASCII-safe
    const { error } = await supabase.storage.from(BUCKET).upload(key, gz, {
      contentType: "application/json", contentEncoding: "gzip", upsert: true,
    });
    if (error) { console.error(`upload failed (${o.course_id}): ${error.message}`); process.exit(1); }
    uploaded++;
    if (uploaded % 500 === 0) console.log(`  uploaded ${uploaded}`);
  }
}
const mb = (x) => (x / 1048576).toFixed(1) + "MB";
console.log(`scanned ${n} | geometry courses ${geom}`);
console.log(`raw JSON total ${mb(rawTotal)} | gzipped total ${mb(gzTotal)} | avg gz/course ${(gzTotal/geom/1024).toFixed(1)}KB`);
if (UPLOAD) console.log(`uploaded ${uploaded} files to Storage bucket "${BUCKET}"`);
