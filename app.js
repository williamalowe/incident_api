import express from 'express';
import incidentsRouter from './routes/incidents.js';
import { requireApiKey } from './middleware/auth.js';
import { errorHandler } from './middleware/errorHandler.js';

export const app = express();

app.use(express.json({ limit: '100kb' }));

app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.use('/incidents', requireApiKey, incidentsRouter);

app.use((req, res) => res.status(404).json({ error: 'Not found' }));
app.use(errorHandler); // Express 5 forwards async errors here automatically
