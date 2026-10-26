-- Run this in the Supabase SQL Editor. Safe to re-run.

-- Trigram extension for fuzzy text similarity
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

-- Lookups always start from the recent time window
create index if not exists incidents_created_at_idx
  on public.incidents (created_at desc);

-- Lock the table down: with RLS on and no policies, only the
-- service role key (used by the API) can read or write.
alter table public.incidents enable row level security;

-- ---------------------------------------------------------------
-- Similarity lookup, called from the API via supabase.rpc()
--
-- Each recent incident gets a combined score between 0 and 1:
--   description: fuzzy text similarity (0-1)
--   category:    1 if it matches (case-insensitive), else 0
--   location:    fuzzy text similarity (0-1), 0 if either is missing
-- weighted by the p_weight_* parameters (which should add up to 1).
-- ---------------------------------------------------------------

-- Remove older versions of the function (different signatures)
drop function if exists public.find_similar_incidents(text, text, text, text, int, real, int);
drop function if exists public.find_similar_incidents(text, text, text, int, real, int);
drop function if exists public.find_similar_incidents(text, text, text, int, real, int, real, real, real);

create function public.find_similar_incidents(
  p_description        text,
  p_category           text,
  p_location           text default null,
  p_window_hours       int  default 24,
  p_threshold          real default 0.5,
  p_limit              int  default 5,
  p_weight_description real default 0.6,
  p_weight_category    real default 0.2,
  p_weight_location    real default 0.2
)
returns table (
  id                uuid,
  description       text,
  category          text,
  location          text,
  created_at        timestamptz,
  description_score real,
  category_match    boolean,
  location_score    real,
  similarity_score  real
)
language sql stable
as $$
  select * from (
    select
      s.id, s.description, s.category, s.location, s.created_at,
      s.d_score, s.c_match, s.l_score,
      (  p_weight_description * s.d_score
       + p_weight_category    * (case when s.c_match then 1 else 0 end)
       + p_weight_location    * s.l_score
      )::real as total_score
    from (
      select
        i.*,
        similarity(i.description, p_description) as d_score,
        lower(trim(i.category)) = lower(trim(p_category)) as c_match,
        case
          when i.location is null or p_location is null then 0::real
          else similarity(i.location, p_location)
        end as l_score
      from public.incidents i
      where i.created_at >= now() - make_interval(hours => p_window_hours)
    ) s
  ) t
  where t.total_score >= p_threshold
  order by t.total_score desc, t.created_at desc
  limit p_limit;
$$;

-- Only the backend should call this
revoke execute on function public.find_similar_incidents(text, text, text, int, real, int, real, real, real)
  from public, anon, authenticated;
grant execute on function public.find_similar_incidents(text, text, text, int, real, int, real, real, real)
  to service_role;