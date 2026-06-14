# Unified Course + Hole Jump Menu — Design

**Date:** 2026-06-13
**Status:** Approved

## Problem

Every hole in the golf sim is authored in its own local coordinate space with
the tee at `{x:0, z:0}`. `startHole(idx)` disposes the current hole's terrain and
builds the next one from scratch via `buildCourse(def)`. Only one hole ever
exists at a time, with no spatial relationship to its neighbors. The result
reads as 18 disconnected "islands" rather than one continuous course.

## Goals

- All 18 holes occupy **one shared world coordinate system** arranged as a real
  routing (hole N's green near hole N+1's tee; nines loop back toward a clubhouse).
- Terrain is **continuous across hole boundaries** — shared rough, no seams; when
  playing a hole you can see neighboring fairways/greens, not an island edge.
- A **hole jump menu** lets the player transport to any hole's tee at any time.
- Hole-out continues to auto-advance to the next tee, now within the shared world.
- The minimap reflects the **whole routing**, not a single floating hole.

## Non-goals

- Rendering all 18 holes at once (the "fully continuous mesh" option was declined).
  We render a region around the hole being played; neighbors that fall in-region
  render too.
- Free-roam walking between holes. Transport is via the jump menu + auto-advance.

## Architecture

### 1. World routing layer — `holes.js` + new `routing.js`
- Holes keep their local geometry (path/green/bunkers/water, tee at origin).
- Each hole gets a world placement `{ ox, oz, rot }`.
- `routing.js` chains the 18 holes into one property: walk holes in order,
  placing each tee a short gap from the previous green with an authored turn
  bearing so the front/back nines loop back toward a clubhouse and stay within a
  bounded plot.
- Exposes `toWorld(hole, localPt)` and precomputed **world-space** copies of each
  hole's path/green/bunkers/water for the terrain field to consume.

### 2. Global continuous terrain field — `terrain.js`
- `buildCourse(hole)` → `buildWorld(holes, focusIdx, assets)`.
- `heightAt/surfaceAt/normalAt` run in **world coordinates** and consider all
  holes overlapping the sampled region (spatially culled to ~2–4 holes), on one
  continuous base-elevation noise field so elevation is coherent course-wide.
- Mesh + trees + water + flags are built for the **region around the focus hole**
  (focus bounds + margin). Neighboring features inside the region render too.
- `pathInfo/pointAtAlong/isOB/pinPos/teePos` are computed for the focus hole, in
  world coords (scoring/aiming semantics unchanged).
- Transport rebuilds the region around the new focus hole (dispose + build), same
  cost profile as today's per-hole build.

### 3. Hole jump menu — `main.js` + `ui.js`
- HUD panel listing holes 1–18 with par/yardage, bound to a key and a button.
- `transportTo(idx)`: set focus, rebuild region, drop ball on that hole's world
  tee, reset strokes for that hole. Skips (or briefly plays) the flyover.
- Auto-advance on hole-out unchanged.

### 4. Course-wide minimap — `ui.js`
- `mapSetHole/mapDraw` updated to draw all holes' world paths with the current
  hole highlighted plus ball/pin markers.

## Data flow

`routing.js` produces world placements → `buildWorld` consumes world-space hole
features to build the global field + focus-region meshes → `main.js` reads
`heightAt/surfaceAt/isOB/pinPos/teePos` exactly as before (now world-space) →
minimap draws the full routing.

## Performance

Field evaluation is O(holes-in-region) per sample. Because only the focus region
is meshed/sampled, only holes whose world bounds overlap that region are
considered (typically 2–4). Mesh cell counts and tree budgets stay at today's
caps.

## Delivery

- Build and verify in `TrueCarry_Sim/` (clean; no merge conflicts).
- Sync changed JS to `Website/public/sim/` and `Website/public/sim-app/` after the
  in-progress merge is resolved by the user. No git commits until the merge state
  is resolved (committing now would finalize the unresolved merge).

## Risks

- Routing overlap: a 18-hole serpentine in a bounded plot may overlap fairways.
  Mitigation: per-hole turn bearings tuned to spread holes; acceptable if it reads
  as one property (zero-overlap not required).
- Performance regression from multi-hole field eval. Mitigation: region-based
  spatial culling.
