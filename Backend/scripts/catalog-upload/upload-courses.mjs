#!/usr/bin/env node
// upload-courses.mjs — stream courses_combined.jsonl → Supabase `courses` (metadata catalog).
// Geometry is NOT uploaded here (handled separately); this is the searchable course directory.
//
// Usage: SUPABASE_URL=.. SUPABASE_KEY=.. node upload-courses.mjs <courses.jsonl> [--dry-run]

import fs from "node:fs";
import readline from "node:readline";
import crypto from "node:crypto";
import { createClient } from "@supabase/supabase-js";

const input = process.argv[2];
const DRY = process.argv.includes("--dry-run");
if (!input) { console.error("usage: node upload-courses.mjs <jsonl> [--dry-run]"); process.exit(1); }

const supabase = (!DRY && process.env.SUPABASE_URL && process.env.SUPABASE_KEY)
  ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY, { auth: { persistSession: false } })
  : null;
if (!DRY && !supabase) { console.error("SUPABASE_URL and SUPABASE_KEY required (or --dry-run)"); process.exit(1); }

// Deterministic UUIDv5 from the slug so re-runs are idempotent and holes/tees can link later.
const NS = "6f9619ff-8b86-d011-b42d-00cf4fc964ff";
function uuidv5(name, ns = NS) {
  const nsBytes = Buffer.from(ns.replace(/-/g, ""), "hex");
  const hash = crypto.createHash("sha1").update(Buffer.concat([nsBytes, Buffer.from(name)])).digest();
  const b = Buffer.from(hash.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50;          // version 5
  b[8] = (b[8] & 0x3f) | 0x80;          // variant
  const h = b.toString("hex");
  return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}

// Returns { tier, quality } using the DB's allowed vocabularies.
function tierOf(o) {
  const c = o.course || {};
  const holes = o.holes || [];
  const hasCenter = holes.some(h => h?.green?.center && (h.green.center.latitude ?? h.green.center.lat) != null);
  if (hasCenter) return { tier: "gps_ready", quality: "good" };
  if (holes.length) return { tier: "scorecard_ready", quality: "none" };
  return { tier: "basic", quality: "none" };  // located or name-only
}

function row(o) {
  const c = o.course || {};
  const { tier, quality } = tierOf(o);
  return {
    id: uuidv5(o.course_id || o.slug),
    source_system: c.source || "osm",
    source_id: o.course_id || o.slug,
    slug: o.slug || o.course_id,
    name: c.name || c.club_name || "Unknown Course",
    normalized_name: (c.name || c.club_name || "").toLowerCase().trim(),
    city: c.city ?? null,
    state: c.state ?? null,
    country: c.country ?? null,
    latitude: c.latitude ?? null,
    longitude: c.longitude ?? null,
    hole_count: c.hole_count ?? (o.holes?.length || null),
    status: "active",
    data_tier: tier,
    geometry_quality: quality,
    attribution: "© OpenStreetMap contributors",
    updated_at: new Date().toISOString(),
  };
}

const rl = readline.createInterface({ input: fs.createReadStream(input), crlfDelay: Infinity });
let batch = [], total = 0, ok = 0;
const counts = { gps_ready: 0, scorecard_ready: 0, basic: 0 };

async function flush() {
  if (!batch.length) return;
  if (supabase) {
    const { error } = await supabase.from("courses").upsert(batch, { onConflict: "id" });
    if (error) { console.error(`batch upsert failed at ${total}: ${error.message}`); process.exit(1); }
  }
  ok += batch.length;
  batch = [];
  if (ok % 2000 === 0 || ok === total) console.log(`  upserted ${ok}/${total}`);
}

for await (const line of rl) {
  if (!line.trim()) continue;
  total++;
  let o; try { o = JSON.parse(line); } catch { continue; }
  counts[tierOf(o).tier]++;
  batch.push(row(o));
  if (batch.length >= 500) await flush();
}
await flush();
console.log(`done. courses: ${total} | tiers:`, counts, DRY ? "(dry-run)" : "");
