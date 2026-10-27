import { createClient } from '@supabase/supabase-js';
import { config } from './config.js';

// Server-side client using the service role key. Never expose this key to browsers.
export const supabase = createClient(config.supabaseUrl, config.supabaseKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
