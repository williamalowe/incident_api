function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

// Accept the base project URL even if a REST endpoint or trailing slash was pasted in
function supabaseUrl() {
  const raw = required('SUPABASE_URL').trim();
  let url;
  try {
    url = new URL(raw);
  } catch {
    throw new Error(`SUPABASE_URL is not a valid URL: ${raw}`);
  }
  if (url.pathname !== '/' && url.pathname !== '') {
    console.warn(`SUPABASE_URL should be just the project URL; ignoring path "${url.pathname}"`);
  }
  return url.origin; // e.g. https://abcd1234.supabase.co
}

const num = (name, fallback) => Number(process.env[name] ?? fallback);

export const config = {
  port: num('PORT', 3000),
  supabaseUrl: supabaseUrl(),
  supabaseKey: required('SUPABASE_SERVICE_ROLE_KEY'),
  apiKey: process.env.API_KEY || null,
  similarity: {
    windowHours: num('SIMILARITY_WINDOW_HOURS', 24),
    limit: num('SIMILARITY_LIMIT', 10),
    categoryThreshold: num('CATEGORY_MATCH_THRESHOLD', 0.75),
    locationThreshold: num('LOCATION_MATCH_THRESHOLD', 0.6),
  },
};