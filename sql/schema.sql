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

-- ---------------------------------------------------------------
-- Street key: the location with house/unit numbers removed and
-- common street abbreviations expanded, so "123 Fake street",
-- "456 Fake St" and "Unit 4/456 Fake Street" all become "fake street".
-- ---------------------------------------------------------------
create or replace function public.street_key(value text)
returns text
language plpgsql immutable
as $$
declare
  result text := ' ' || lower(coalesce(value, '')) || ' ';
  pair text[];
  abbreviations text[][] := array[
    ['st', 'street'], ['rd', 'road'], ['ave', 'avenue'], ['av', 'avenue'],
    ['dr', 'drive'], ['ct', 'court'], ['pl', 'place'], ['cres', 'crescent'],
    ['cr', 'crescent'], ['hwy', 'highway'], ['pde', 'parade'], ['tce', 'terrace'],
    ['blvd', 'boulevard'], ['ln', 'lane'], ['cl', 'close'], ['gr', 'grove'],
    ['sq', 'square'], ['esp', 'esplanade'], ['cct', 'circuit'], ['pkwy', 'parkway']
  ];
begin
  -- Punctuation (commas, slashes, hyphens, full stops) becomes spaces
  result := regexp_replace(result, '[^a-z0-9 ]', ' ', 'g');
  -- Drop any word containing a digit: 123, 4, 12a, 3rd
  result := regexp_replace(result, '\m\S*[0-9]\S*\M', ' ', 'g');
  -- Drop unit/level designators
  result := regexp_replace(result, '\m(unit|units|apt|apartment|suite|shop|level|lvl|flat|lot|no)\M', ' ', 'g');
  -- Expand street-type abbreviations
  foreach pair slice 1 in array abbreviations loop
    result := regexp_replace(result, '\m' || pair[1] || '\M', pair[2], 'g');
  end loop;
  return trim(regexp_replace(result, '\s+', ' ', 'g'));
end;
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
--     word-level similarity, so "water leak" ~ "Water leaks"
--   location_score >= p_location_threshold
--     the better of two comparisons:
--       - the full location text ("Melbourne office" ~ "Melb office")
--       - the street key, ignoring house/unit numbers and abbreviations
--         ("123 Fake street" = "456 Fake St" = "Unit 4/456 Fake Street")
-- Scores run 0-1; an exact match (ignoring case/spaces) scores 1.
-- location_match says which comparison matched:
--   'exact', 'same street' (only the numbers differ) or 'similar'.
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
  location_match text,
  total_matches  bigint
)
language sql stable
as $$
  with input as (
    select
      public.incident_key(p_category) as cat,
      public.incident_key(p_location) as loc,
      public.street_key(p_location)   as street
  ),
  scored as (
    select
      i.*,
      case
        when public.incident_key(i.category) = inp.cat then 1::real
        else greatest(
          word_similarity(inp.cat, public.incident_key(i.category)),
          word_similarity(public.incident_key(i.category), inp.cat)
        )
      end as c_score,
      case
        when i.location is null then 0::real
        when public.incident_key(i.location) = inp.loc then 1::real
        else similarity(public.incident_key(i.location), inp.loc)
      end as full_score,
      case
        when i.location is null or inp.street = '' or public.street_key(i.location) = '' then 0::real
        when public.street_key(i.location) = inp.street then 1::real
        else similarity(public.street_key(i.location), inp.street)
      end as street_score,
      public.incident_key(i.location) = inp.loc as exact_loc,
      public.street_key(i.location) = inp.street and inp.street <> '' as same_street
    from public.incidents i
    cross join input inp
    where i.created_at >= now() - make_interval(hours => p_window_hours)
  )
  select
    s.id, s.description, s.category, s.location, s.created_at,
    s.c_score,
    greatest(s.full_score, s.street_score) as l_score,
    case
      when s.exact_loc then 'exact'
      when s.same_street then 'same street'
      else 'similar'
    end,
    count(*) over () as total_matches
  from scored s
  where s.c_score >= p_category_threshold
    and greatest(s.full_score, s.street_score) >= p_location_threshold
  order by (s.c_score + greatest(s.full_score, s.street_score)) desc, s.created_at desc
  limit p_limit;
$$;

-- Only the backend should call this
revoke execute on function public.find_similar_incidents(text, text, int, int, real, real)
  from public, anon, authenticated;
grant execute on function public.find_similar_incidents(text, text, int, int, real, real)
  to service_role;