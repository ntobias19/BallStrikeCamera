-- 005_course_geometries.sql
-- Shared golf-course geometry cache.
--
-- GolfCourseAPI supplies scorecards, but not per-hole tee/green GPS points.
-- OSM supplies geometry only when a course has been traced. This table stores
-- user-confirmed geometry so unmapped courses only need setup once.

create table if not exists course_geometries (
    course_id    text primary key,
    course_name  text not null default '',
    city         text not null default '',
    state        text not null default '',
    source       text not null default 'manual',
    payload      jsonb not null,
    submitted_by uuid references auth.users(id) on delete set null,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

create index if not exists course_geometries_name_idx
    on course_geometries using gin (to_tsvector('simple', course_name || ' ' || city || ' ' || state));

alter table course_geometries enable row level security;

create policy "signed-in users can read course geometry"
    on course_geometries for select using (auth.uid() is not null);

create policy "signed-in users can insert course geometry"
    on course_geometries for insert with check (auth.uid() is not null);

create policy "signed-in users can update course geometry"
    on course_geometries for update using (auth.uid() is not null);
