import { z } from 'zod';

const description = z.string().trim().min(5).max(5000);
const category = z.string().trim().min(1).max(100);
const location = z.string().trim().max(200).optional();

export const createIncidentSchema = z.object({
  description,
  category,
  location,
});

export const checkIncidentSchema = z.object({
  description,
  category,
  location,
  window_hours: z.number().int().min(1).max(720).optional(),
  threshold: z.number().min(0).max(1).optional(),
  limit: z.number().int().min(1).max(50).optional(),
});