-- Run this in the Supabase SQL Editor. Safe to re-run.

-- Trigram extension for fuzzy text matching
create extension if not exists pg_trgm;

-- ---------------------------------------------------------------
-- Incidents table
-- ---------------------------------------------------------------
create table if not exists public.incidents (
  id           uuid primary key default gen_random_uuid(),
  description  text not null,
  category     text not null,
  location     text,
  created_at   timestamptz not null default now()
);

-- Lock the table down: with RLS on and no policies, only the
-- service role key (used by the API) can read or write.
alter table public.incidents enable row level security;

-- ---------------------------------------------------------------
-- Normalised text: ignores capitalisation and extra spaces
-- ---------------------------------------------------------------
create or replace function public.incident_key(value text)
returns text
language sql immutable
as $$
  select lower(regexp_replace(trim(value), '\s+', ' ', 'g'));
$$;

-- Old indexes from earlier versions (no longer used)
drop index if exists public.incidents_title_trgm_idx;
drop index if exists public.incidents_description_trgm_idx;
drop index if exists public.incidents_category_created_idx;
drop index if exists public.incidents_category_location_created_idx;

-- Lookups start from the recent time window
create index if not exists incidents_created_at_idx
  on public.incidents (created_at desc);

-- ---------------------------------------------------------------
-- Similar-incident lookup, called from the API via supabase.rpc()
--
-- An incident counts as similar when, within the time window, BOTH:
--   category_score >= p_category_threshold
--     word-level similarity, so "auth" ~ "authentication" and
--     "network" ~ "networking"
--   location_score >= p_location_threshold
--     whole-string similarity, so "Melbourne office" ~
--     "Melbourne Office Level 2" or "Melb office", but not "Sydney office"
-- Scores run 0-1; an exact match (ignoring case/spaces) scores 1.
-- Set a threshold to 1 to require an exact match for that field.
-- ---------------------------------------------------------------

-- Remove older versions of the function (different signatures)
drop function if exists public.find_similar_incidents(text, text, text, text, int, real, int);
drop function if exists public.find_similar_incidents(text, text, text, int, real, int);
drop function if exists public.find_similar_incidents(text, text, text, int, real, int, real, real, real);
drop function if exists public.find_similar_incidents(text, text, int, int);
drop function if exists public.find_similar_incidents(text, text, int, int, real, real);

create function public.find_similar_incidents(
  p_category           text,
  p_location           text,
  p_window_hours       int  default 24,
  p_limit              int  default 10,
  p_category_threshold real default 0.75,
  p_location_threshold real default 0.6
)
returns table (
  id             uuid,
  description    text,
  category       text,
  location       text,
  created_at     timestamptz,
  category_score real,
  location_score real,
  total_matches  bigint
)
language sql stable
as $$
  select
    s.id, s.description, s.category, s.location, s.created_at,
    s.c_score, s.l_score,
    count(*) over () as total_matches
  from (
    select
      i.*,
      case
        when public.incident_key(i.category) = public.incident_key(p_category) then 1::real
        else greatest(
          word_similarity(public.incident_key(p_category), public.incident_key(i.category)),
          word_similarity(public.incident_key(i.category), public.incident_key(p_category))
        )
      end as c_score,
      case
        when i.location is null then 0::real
        when public.incident_key(i.location) = public.incident_key(p_location) then 1::real
        else similarity(public.incident_key(i.location), public.incident_key(p_location))
      end as l_score
    from public.incidents i
    where i.created_at >= now() - make_interval(hours => p_window_hours)
  ) s
  where s.c_score >= p_category_threshold
    and s.l_score >= p_location_threshold
  order by (s.c_score + s.l_score) desc, s.created_at desc
  limit p_limit;
$$;

-- Only the backend should call this
revoke execute on function public.find_similar_incidents(text, text, int, int, real, real)
  from public, anon, authenticated;
grant execute on function public.find_similar_incidents(text, text, int, int, real, real)
  to service_role;