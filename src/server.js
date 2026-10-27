// Local development only. On Vercel, src/app.js is used directly.
import app from './app.js';
import { config } from './config.js';

app.listen(config.port, () => {
  console.log(`Incident API listening on http://localhost:${config.port}`);
});