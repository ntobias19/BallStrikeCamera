-- 006_geometry_backfill_pipeline.sql
-- Adds trust metadata and a server-side queue for automatic course-geometry backfill.

alter table course_geometries
    add column if not exists geometry_state text not null default 'accepted'
        check (geometry_state in ('auto_draft', 'accepted', 'rejected')),
    add column if not exists confidence double precision,
    add column if not exists schema_version integer not null default 1,
    add column if not exists generated_by text,
    add column if not exists validation_errors jsonb not null default '[]'::jsonb,
    add column if not exists imagery_source text;

update course_geometries
set geometry_state = 'accepted',
    confidence = coalesce(confidence, 1.0),
    generated_by = coalesce(generated_by, source)
where geometry_state is null or geometry_state = '';

drop policy if exists "signed-in users can read course geometry" on course_geometries;
drop policy if exists "signed-in users can insert course geometry" on course_geometries;
drop policy if exists "signed-in users can update course geometry" on course_geometries;
drop policy if exists "public can read accepted course geometry" on course_geometries;

create policy "public can read accepted course geometry"
    on course_geometries for select
    using (geometry_state = 'accepted');

-- No insert/update policies are created for course_geometries here. Server/service-role
-- jobs bypass RLS and are responsible for accepting or rejecting geometry candidates.

create table if not exists geometry_backfill_requests (
    id uuid primary key default gen_random_uuid(),
    course_id text not null unique,
    course_name text not null default '',
    city text not null default '',
    state text not null default '',
    country text not null default 'US',
    latitude double precision,
    longitude double precision,
    selected_tee_name text,
    selected_tee_yards integer,
    reason text not null default 'missing_geometry',
    status text not null default 'queued'
        check (status in ('queued', 'processing', 'completed', 'failed', 'ignored')),
    priority integer not null default 100,
    request_count integer not null default 1,
    scorecard_payload jsonb,
    last_error text,
    last_requested_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists geometry_backfill_requests_status_idx
    on geometry_backfill_requests (status, priority, updated_at);

alter table geometry_backfill_requests enable row level security;

drop policy if exists "public can queue geometry backfill" on geometry_backfill_requests;
drop policy if exists "public can refresh geometry backfill" on geometry_backfill_requests;

create policy "public can queue geometry backfill"
    on geometry_backfill_requests for insert
    with check (true);

create policy "public can refresh geometry backfill"
    on geometry_backfill_requests for update
    using (true)
    with check (true);
