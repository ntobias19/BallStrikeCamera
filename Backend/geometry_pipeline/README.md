# True Carry Geometry Pipeline

Server-side worker for automatic golf-course geometry backfill.

The iOS app never scrapes Apple/Google map tiles and never ships a service-role key. When a
course has a scorecard but no trusted geometry, the app upserts a row into
`geometry_backfill_requests`. This worker can then:

1. Pull authoritative scorecard data from GolfCourseAPI.
2. Pull maximum free geometry from OSM/Overpass, including ways, relations, pins, and boundaries.
3. For U.S. gaps, optionally fetch public NAIP imagery and run CV heuristics.
4. Validate tee-to-green distances against the scorecard.
5. Write only high-confidence geometry to `course_geometries` as `accepted`; otherwise write
   `auto_draft` for later QA.

## Environment

Required for writes:

```bash
export SUPABASE_URL="https://PROJECT.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="server-only-service-role-key"
```

Optional:

```bash
export GOLFCOURSEAPI_KEY="..."
export OVERPASS_URL="https://overpass-api.de/api/interpreter"
export NAIP_IMAGE_SERVER_URL="https://gis.apfo.usda.gov/arcgis/rest/services/NAIP/USDA_CONUS_PRIME/ImageServer/exportImage"
```

Install optional CV dependencies on the worker:

```bash
python3 -m pip install -r Backend/geometry_pipeline/requirements.txt
```

Run validation tests:

```bash
python3 -m unittest discover Backend/geometry_pipeline/tests
```

Run one request manually:

```bash
python3 Backend/geometry_pipeline/pipeline.py run \
  --course-id "9522" \
  --name "Mt. Lebanon Golf Course" \
  --city "Pittsburgh" \
  --state "PA" \
  --lat 40.37 \
  --lon -80.04
```
