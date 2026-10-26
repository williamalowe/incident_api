function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

const num = (name, fallback) => Number(process.env[name] ?? fallback);

export const config = {
  port: num('PORT', 3000),
  supabaseUrl: required('SUPABASE_URL'),
  supabaseKey: required('SUPABASE_SERVICE_ROLE_KEY'),
  apiKey: process.env.API_KEY || null,
  similarity: {
    windowHours: num('SIMILARITY_WINDOW_HOURS', 24),
    threshold: num('SIMILARITY_THRESHOLD', 0.5),
    limit: num('SIMILARITY_LIMIT', 5),
    weights: {
      description: num('WEIGHT_DESCRIPTION', 0.6),
      category: num('WEIGHT_CATEGORY', 0.2),
      location: num('WEIGHT_LOCATION', 0.2),
    },
  },
};