import { timingSafeEqual } from 'node:crypto';
import { config } from '../config.js';

export function requireApiKey(req, res, next) {
  if (!config.apiKey) return next(); // auth disabled

  const provided = Buffer.from(req.get('x-api-key') ?? '');
  const expected = Buffer.from(config.apiKey);

  if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) {
    return res.status(401).json({ error: 'Invalid or missing API key' });
  }
  next();
}
