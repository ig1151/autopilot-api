#!/bin/bash
set -e

echo "🚀 Setting up Autopilot API..."

mkdir -p src/routes

cat > package.json << 'ENDPACKAGE'
{
  "name": "autopilot-api",
  "version": "1.0.0",
  "description": "Continuous portfolio monitoring and strategy execution — set it and let it run.",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "dev": "ts-node-dev --respawn --transpile-only src/index.ts",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "compression": "^1.7.4",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "express-rate-limit": "^7.1.5",
    "helmet": "^7.1.0",
    "joi": "^17.11.0",
    "node-cron": "^3.0.3",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "@types/compression": "^1.7.5",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.0",
    "@types/node-cron": "^3.0.11",
    "@types/uuid": "^9.0.7",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.3.2"
  }
}
ENDPACKAGE

cat > tsconfig.json << 'ENDTSCONFIG'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
ENDTSCONFIG

cat > render.yaml << 'ENDRENDER'
services:
  - type: web
    name: autopilot-api
    env: node
    buildCommand: npm install && npm run build
    startCommand: node dist/index.js
    healthCheckPath: /v1/health
    envVars:
      - key: NODE_ENV
        value: production
      - key: PORT
        value: 10000
ENDRENDER

cat > .gitignore << 'ENDGITIGNORE'
node_modules/
dist/
.env
*.log
ENDGITIGNORE

cat > src/logger.ts << 'ENDLOGGER'
export const logger = {
  info: (obj: unknown, msg?: string) =>
    console.log(JSON.stringify({ level: 'info', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  warn: (obj: unknown, msg?: string) =>
    console.warn(JSON.stringify({ level: 'warn', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  error: (obj: unknown, msg?: string) =>
    console.error(JSON.stringify({ level: 'error', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
};
ENDLOGGER

cat > src/store.ts << 'ENDSTORE'
import { AutopilotSession, DecisionRecord } from './types';

const sessions = new Map<string, AutopilotSession>();
const history = new Map<string, DecisionRecord[]>();

const MAX_HISTORY = 50;

export const store = {
  create(session: AutopilotSession): void {
    sessions.set(session.id, session);
    history.set(session.id, []);
  },

  get(id: string): AutopilotSession | undefined {
    return sessions.get(id);
  },

  getAll(): AutopilotSession[] {
    return Array.from(sessions.values());
  },

  update(id: string, patch: Partial<AutopilotSession>): void {
    const session = sessions.get(id);
    if (session) sessions.set(id, { ...session, ...patch });
  },

  delete(id: string): boolean {
    history.delete(id);
    return sessions.delete(id);
  },

  addHistory(id: string, record: DecisionRecord): void {
    const records = history.get(id) ?? [];
    records.unshift(record);
    if (records.length > MAX_HISTORY) records.pop();
    history.set(id, records);
  },

  getHistory(id: string, limit = 10): DecisionRecord[] {
    return (history.get(id) ?? []).slice(0, limit);
  },

  count(): number {
    return sessions.size;
  },
};
ENDSTORE

cat > src/types.ts << 'ENDTYPES'
export type StrategyName = 'news_momentum' | 'trend_following' | 'risk_adjusted';
export type RiskTolerance = 'low' | 'medium' | 'high';
export type SessionStatus = 'active' | 'paused' | 'stopped';

export interface PortfolioAsset {
  asset: string;
  value: number;
  weight: number;
}

export interface AutopilotSession {
  id: string;
  portfolio: PortfolioAsset[];
  strategy: StrategyName;
  risk_tolerance: RiskTolerance;
  assets?: string[];
  webhook_url?: string;
  status: SessionStatus;
  created_at: string;
  last_run?: string;
  last_decision?: string;
  last_confidence?: number;
  run_count: number;
  alert_on_hold: boolean;
}

export interface DecisionRecord {
  timestamp: string;
  decision: string;
  confidence: number;
  actions: Array<{
    asset: string;
    action: string;
    amount: number;
    confidence: number;
  }>;
  reasoning: string[];
  webhook_sent: boolean;
}
ENDTYPES

cat > src/scheduler.ts << 'ENDSCHEDULER'
import cron from 'node-cron';
import axios from 'axios';
import { store } from './store';
import { logger } from './logger';
import { DecisionRecord } from './types';

const STRATEGY_API = 'https://strategy-execution-api.onrender.com';

async function runSession(sessionId: string): Promise<void> {
  const session = store.get(sessionId);
  if (!session || session.status !== 'active') return;

  try {
    const res = await axios.post(
      `${STRATEGY_API}/v1/strategy/execute`,
      {
        portfolio: session.portfolio,
        strategy: session.strategy,
        risk_tolerance: session.risk_tolerance,
        assets: session.assets,
      },
      { timeout: 15000 }
    );

    const result = res.data;
    const isActionable = result.actions?.some((a: { action: string }) => a.action !== 'hold');
    let webhookSent = false;

    if (session.webhook_url && (isActionable || session.alert_on_hold)) {
      try {
        await axios.post(
          session.webhook_url,
          {
            autopilot_id: session.id,
            strategy: result.strategy,
            decision: result.decision,
            confidence: result.confidence,
            actions: result.actions,
            reasoning: result.reasoning,
            timestamp: result.timestamp,
          },
          { timeout: 8000 }
        );
        webhookSent = true;
      } catch (err) {
        logger.warn({ sessionId, err }, 'Webhook delivery failed');
      }
    }

    const record: DecisionRecord = {
      timestamp: new Date().toISOString(),
      decision: result.decision,
      confidence: result.confidence,
      actions: result.actions,
      reasoning: result.reasoning,
      webhook_sent: webhookSent,
    };

    store.addHistory(sessionId, record);
    store.update(sessionId, {
      last_run: new Date().toISOString(),
      last_decision: result.decision,
      last_confidence: result.confidence,
      run_count: (session.run_count ?? 0) + 1,
    });

    logger.info({ sessionId, decision: result.decision, confidence: result.confidence, webhookSent }, 'Autopilot run complete');
  } catch (err) {
    logger.error({ sessionId, err }, 'Autopilot run failed');
  }
}

export function startScheduler(): void {
  // Run every 5 minutes
  cron.schedule('*/5 * * * *', async () => {
    const sessions = store.getAll().filter(s => s.status === 'active');
    if (sessions.length === 0) return;

    logger.info({ count: sessions.length }, 'Scheduler tick — running active sessions');
    await Promise.allSettled(sessions.map(s => runSession(s.id)));
  });

  logger.info({}, 'Autopilot scheduler started — runs every 5 minutes');
}
ENDSCHEDULER

cat > src/routes/autopilot.ts << 'ENDAUTOPILOT'
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { v4 as uuidv4 } from 'uuid';
import { store } from '../store';
import { logger } from '../logger';
import { AutopilotSession } from '../types';

const router = Router();

const portfolioAssetSchema = Joi.object({
  asset: Joi.string().uppercase().min(2).max(10).required(),
  value: Joi.number().positive().required(),
  weight: Joi.number().min(0).max(1).required(),
});

const createSchema = Joi.object({
  portfolio: Joi.array().items(portfolioAssetSchema).min(1).max(20).required(),
  strategy: Joi.string().valid('news_momentum', 'trend_following', 'risk_adjusted').required(),
  risk_tolerance: Joi.string().valid('low', 'medium', 'high').default('medium'),
  assets: Joi.array().items(Joi.string().uppercase()).max(10).optional(),
  webhook_url: Joi.string().uri().optional(),
  alert_on_hold: Joi.boolean().default(false),
});

// POST /v1/autopilot — create session
router.post('/', async (req: Request, res: Response) => {
  const { error, value } = createSchema.validate(req.body);
  if (error) {
    res.status(400).json({ error: 'Validation failed', details: error.details[0].message });
    return;
  }

  const session: AutopilotSession = {
    id: uuidv4(),
    portfolio: value.portfolio,
    strategy: value.strategy,
    risk_tolerance: value.risk_tolerance,
    assets: value.assets,
    webhook_url: value.webhook_url,
    alert_on_hold: value.alert_on_hold,
    status: 'active',
    created_at: new Date().toISOString(),
    run_count: 0,
  };

  store.create(session);
  logger.info({ id: session.id, strategy: session.strategy }, 'Autopilot session created');

  res.status(201).json({
    id: session.id,
    status: session.status,
    strategy: session.strategy,
    risk_tolerance: session.risk_tolerance,
    webhook_enabled: !!session.webhook_url,
    alert_on_hold: session.alert_on_hold,
    created_at: session.created_at,
    message: 'Autopilot session active — runs every 5 minutes',
  });
});

// GET /v1/autopilot/:id — get session
router.get('/:id', (req: Request, res: Response) => {
  const session = store.get(req.params.id);
  if (!session) {
    res.status(404).json({ error: 'Session not found' });
    return;
  }
  res.json(session);
});

// GET /v1/autopilot/:id/history — get decision history
router.get('/:id/history', (req: Request, res: Response) => {
  const session = store.get(req.params.id);
  if (!session) {
    res.status(404).json({ error: 'Session not found' });
    return;
  }
  const limit = Math.min(parseInt(req.query.limit as string) || 10, 50);
  const records = store.getHistory(req.params.id, limit);
  res.json({ id: req.params.id, count: records.length, history: records });
});

// PATCH /v1/autopilot/:id — pause or resume
router.patch('/:id', (req: Request, res: Response) => {
  const session = store.get(req.params.id);
  if (!session) {
    res.status(404).json({ error: 'Session not found' });
    return;
  }
  const { status } = req.body;
  if (!['active', 'paused'].includes(status)) {
    res.status(400).json({ error: 'status must be active or paused' });
    return;
  }
  store.update(req.params.id, { status });
  logger.info({ id: req.params.id, status }, 'Autopilot session updated');
  res.json({ id: req.params.id, status });
});

// DELETE /v1/autopilot/:id — stop session
router.delete('/:id', (req: Request, res: Response) => {
  const session = store.get(req.params.id);
  if (!session) {
    res.status(404).json({ error: 'Session not found' });
    return;
  }
  store.delete(req.params.id);
  logger.info({ id: req.params.id }, 'Autopilot session stopped');
  res.json({ id: req.params.id, status: 'stopped', message: 'Session deleted' });
});

export default router;
ENDAUTOPILOT

cat > src/routes/docs.ts << 'ENDDOCS'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Autopilot API</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 860px; margin: 40px auto; padding: 0 20px; background: #0f0f0f; color: #e0e0e0; }
    h1 { color: #7c3aed; } h2 { color: #a78bfa; border-bottom: 1px solid #333; padding-bottom: 8px; }
    pre { background: #1a1a1a; padding: 16px; border-radius: 8px; overflow-x: auto; font-size: 13px; }
    code { color: #c084fc; }
    .badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 12px; margin-right: 8px; color: white; }
    .get { background: #065f46; } .post { background: #7c3aed; } .delete { background: #991b1b; } .patch { background: #92400e; }
    table { width: 100%; border-collapse: collapse; } td, th { padding: 8px 12px; border: 1px solid #333; text-align: left; }
    th { background: #1a1a1a; }
  </style>
</head>
<body>
  <h1>Autopilot API</h1>
  <p>Continuous portfolio monitoring and strategy execution — set it and let it run.</p>
  <h2>Endpoints</h2>
  <table>
    <tr><th>Method</th><th>Path</th><th>Description</th></tr>
    <tr><td><span class="badge post">POST</span></td><td>/v1/autopilot</td><td>Create an autopilot session</td></tr>
    <tr><td><span class="badge get">GET</span></td><td>/v1/autopilot/:id</td><td>Get session status</td></tr>
    <tr><td><span class="badge get">GET</span></td><td>/v1/autopilot/:id/history</td><td>Get decision history</td></tr>
    <tr><td><span class="badge patch">PATCH</span></td><td>/v1/autopilot/:id</td><td>Pause or resume session</td></tr>
    <tr><td><span class="badge delete">DELETE</span></td><td>/v1/autopilot/:id</td><td>Stop and delete session</td></tr>
    <tr><td><span class="badge get">GET</span></td><td>/v1/health</td><td>Health check</td></tr>
  </table>
  <h2>Create Session</h2>
  <pre>POST /v1/autopilot
Content-Type: application/json

{
  "portfolio": [
    { "asset": "BTC", "value": 10000, "weight": 0.6 },
    { "asset": "ETH", "value": 4000, "weight": 0.3 },
    { "asset": "SOL", "value": 1000, "weight": 0.1 }
  ],
  "strategy": "news_momentum",
  "risk_tolerance": "medium",
  "webhook_url": "https://your-app.com/webhook",
  "alert_on_hold": false
}</pre>
  <h2>Strategies</h2>
  <ul>
    <li><code>news_momentum</code> — React to high-impact crypto news</li>
    <li><code>trend_following</code> — Follow strong directional signals</li>
    <li><code>risk_adjusted</code> — Rebalance to target weights</li>
  </ul>
  <p><a href="/openapi.json" style="color:#a78bfa">OpenAPI JSON</a></p>
</body>
</html>`);
});

export default router;
ENDDOCS

cat > src/routes/openapi.ts << 'ENDOPENAPI'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    openapi: '3.0.0',
    info: {
      title: 'Autopilot API',
      version: '1.0.0',
      description: 'Continuous portfolio monitoring and strategy execution — set it and let it run.',
    },
    servers: [{ url: 'https://autopilot-api.onrender.com' }],
    paths: {
      '/v1/autopilot': {
        post: {
          summary: 'Create an autopilot session',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: ['portfolio', 'strategy'],
                  properties: {
                    portfolio: { type: 'array', items: { type: 'object' } },
                    strategy: { type: 'string', enum: ['news_momentum', 'trend_following', 'risk_adjusted'] },
                    risk_tolerance: { type: 'string', enum: ['low', 'medium', 'high'], default: 'medium' },
                    assets: { type: 'array', items: { type: 'string' } },
                    webhook_url: { type: 'string', format: 'uri' },
                    alert_on_hold: { type: 'boolean', default: false },
                  },
                },
              },
            },
          },
          responses: { '201': { description: 'Session created' } },
        },
      },
      '/v1/autopilot/{id}': {
        get: { summary: 'Get session status', responses: { '200': { description: 'Session object' } } },
        patch: { summary: 'Pause or resume session', responses: { '200': { description: 'Updated status' } } },
        delete: { summary: 'Stop and delete session', responses: { '200': { description: 'Session stopped' } } },
      },
      '/v1/autopilot/{id}/history': {
        get: { summary: 'Get decision history', responses: { '200': { description: 'Decision records' } } },
      },
      '/v1/health': {
        get: { summary: 'Health check', responses: { '200': { description: 'OK' } } },
      },
    },
  });
});

export default router;
ENDOPENAPI

cat > src/index.ts << 'ENDINDEX'
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
ENDINDEX

echo "✅ All files created!"
echo "Next: npm install && npm run dev"