import { z } from 'zod';

const category = z.string().trim().min(1).max(100);
const location = z.string().trim().min(1).max(200);

export const createIncidentSchema = z.object({
  description: z.string().trim().min(5).max(5000),
  category,
  location,
});

// Matching uses category + location only; any other fields sent are ignored
export const checkIncidentSchema = z.object({
  category,
  location,
  window_hours: z.number().int().min(1).max(720).optional(),
  limit: z.number().int().min(1).max(50).optional(),
  category_threshold: z.number().min(0).max(1).optional(),
  location_threshold: z.number().min(0).max(1).optional(),
});