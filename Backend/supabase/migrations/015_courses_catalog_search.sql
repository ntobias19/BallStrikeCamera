-- 015_courses_catalog_search.sql
-- Search API over the `courses` catalog (40k+ OSM-derived courses loaded from courses_combined.jsonl).
-- The app pings search_courses() to find a course, then fetches its geometry from the
-- `course-geometry` Storage bucket (one gzipped GolfCourse JSON per course, keyed by courses.id).
--
-- Free-tier note: per-hole geometry (≈1.5 GB raw) lives in Storage (≈205 MB gzipped), NOT Postgres.

create extension if not exists pg_trgm;
create index if not exists courses_name_trgm_idx on courses using gin (name gin_trgm_ops);
create index if not exists courses_latlon_idx on courses (latitude, longitude);
create index if not exists courses_data_tier_idx on courses (data_tier);

-- public read so the app (anon key) can search.
alter table courses enable row level security;
drop policy if exists "public read courses" on courses;
create policy "public read courses" on courses for select using (true);

-- Optimal lookup: trigram name match + proximity ranking, one round trip.
-- only_geometry restricts to courses that have full geometry uploaded (data_tier = 'gps_ready').
create or replace function search_courses(
    q text default null,
    lat double precision default null,
    lon double precision default null,
    only_geometry boolean default false,
    lim integer default 20
) returns setof courses
language sql stable as $$
    select *
    from courses c
    where (not only_geometry or c.data_tier = 'gps_ready')
      and (q is null or q = '' or c.name % q or c.name ilike '%'||q||'%')
    order by
      (case when q is not null and q <> '' then similarity(c.name, q) else 0 end) desc,
      (case when lat is not null and c.latitude is not null
            then ((c.latitude-lat)*(c.latitude-lat) + (c.longitude-lon)*(c.longitude-lon))
            else 1e9 end) asc,
      c.name asc
    limit greatest(1, least(lim, 50));
$$;

-- Storage bucket `course-geometry` (public read) holds <courses.id>.json.gz per course.
-- Created via the storage API; objects fetched at:
--   {SUPABASE_URL}/storage/v1/object/public/course-geometry/<course_id>.json.gz
