import { Router } from 'express';
import { supabase } from '../supabase.js';
import { config } from '../config.js';
import { createIncidentSchema, checkIncidentSchema } from '../schemas.js';

const router = Router();

async function findSimilar(input) {
  const { data, error } = await supabase.rpc('find_similar_incidents', {
    p_description: input.description,
    p_category: input.category,
    p_location: input.location ?? null,
    p_window_hours: input.window_hours ?? config.similarity.windowHours,
    p_threshold: input.threshold ?? config.similarity.threshold,
    p_limit: input.limit ?? config.similarity.limit,
    p_weight_description: config.similarity.weights.description,
    p_weight_category: config.similarity.weights.category,
    p_weight_location: config.similarity.weights.location,
  });
  if (error) throw error;
  return data ?? [];
}

// 1. Create an incident (also reports any similar recent incidents)
router.post('/', async (req, res) => {
  const input = createIncidentSchema.parse(req.body);

  // Check before inserting so the new incident doesn't match itself
  const similar = await findSimilar(input);

  const { data: incident, error } = await supabase
    .from('incidents')
    .insert({
      description: input.description,
      category: input.category,
      location: input.location ?? null,
    })
    .select()
    .single();
  if (error) throw error;

  res.status(201).json({
    incident,
    flagged: similar.length > 0,
    similar_incidents: similar,
  });
});

// 2. Check for similar recent incidents without creating one
router.post('/check', async (req, res) => {
  const input = checkIncidentSchema.parse(req.body);
  const similar = await findSimilar(input);

  res.json({
    flagged: similar.length > 0,
    similar_incidents: similar,
  });
});

export default router;