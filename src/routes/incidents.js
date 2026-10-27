import { Router } from 'express';
import { supabase } from '../supabase.js';
import { config } from '../config.js';
import { createIncidentSchema, checkIncidentSchema } from '../schemas.js';

const router = Router();

// Finds recent incidents with a matching category AND location (fuzzy)
async function findSimilar(input) {
  const { data, error } = await supabase.rpc('find_similar_incidents', {
    p_category: input.category,
    p_location: input.location,
    p_window_hours: input.window_hours ?? config.similarity.windowHours,
    p_limit: input.limit ?? config.similarity.limit,
    p_category_threshold: input.category_threshold ?? config.similarity.categoryThreshold,
    p_location_threshold: input.location_threshold ?? config.similarity.locationThreshold,
  });
  if (error) throw error;

  const rows = data ?? [];
  return {
    flagged: rows.length > 0,
    match_count: rows.length > 0 ? Number(rows[0].total_matches) : 0,
    similar_incidents: rows.map(({ total_matches, ...incident }) => incident),
  };
}

// 1. Create an incident (also reports any similar recent incidents)
router.post('/', async (req, res) => {
  const input = createIncidentSchema.parse(req.body);

  // Check before inserting so the new incident doesn't match itself
  const result = await findSimilar(input);

  const { data: incident, error } = await supabase
    .from('incidents')
    .insert({
      description: input.description,
      category: input.category,
      location: input.location,
    })
    .select()
    .single();
  if (error) throw error;

  res.status(201).json({ incident, ...result });
});

// 2. Check for similar recent incidents without creating one
router.post('/check', async (req, res) => {
  const input = checkIncidentSchema.parse(req.body);
  res.json(await findSimilar(input));
});

export default router;