import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { logger } from './logger';
import { startScheduler } from './scheduler';
import autopilotRouter from './routes/autopilot';
import docsRouter from './routes/docs';
import openapiRouter from './routes/openapi';
import { store } from './store';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json());
app.use(rateLimit({ windowMs: 60_000, max: 60, standardHeaders: true, legacyHeaders: false }));

app.get('/v1/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'autopilot-api',
    active_sessions: store.count(),
    timestamp: new Date().toISOString(),
  });
});

app.use('/v1/autopilot', autopilotRouter);
app.use('/docs', docsRouter);
app.use('/openapi.json', openapiRouter);

app.use((req, res) => {
  res.status(404).json({ error: 'Not found', path: req.path });
});

startScheduler();

app.listen(PORT, () => {
  logger.info({ port: PORT }, 'Autopilot API running');
});
