#!/bin/bash
set -e

echo "🔧 Patching Autopilot API..."

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
  next_run?: string;
  last_decision?: string;
  last_confidence?: number;
  run_count: number;
  alert_on_hold: boolean;
}

export interface DecisionRecord {
  event: 'decision.triggered' | 'decision.hold';
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
const INTERVAL_MS = 5 * 60 * 1000;

function getNextRun(): string {
  return new Date(Date.now() + INTERVAL_MS).toISOString();
}

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
    const event: DecisionRecord['event'] = isActionable ? 'decision.triggered' : 'decision.hold';
    let webhookSent = false;

    if (session.webhook_url && (isActionable || session.alert_on_hold)) {
      try {
        await axios.post(
          session.webhook_url,
          {
            event,
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
      event,
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
      next_run: getNextRun(),
      last_decision: result.decision,
      last_confidence: result.confidence,
      run_count: (session.run_count ?? 0) + 1,
    });

    logger.info({ sessionId, event, decision: result.decision, confidence: result.confidence, webhookSent }, 'Autopilot run complete');
  } catch (err) {
    logger.error({ sessionId, err }, 'Autopilot run failed');
  }
}

export function startScheduler(): void {
  cron.schedule('*/5 * * * *', async () => {
    const sessions = store.getAll().filter(s => s.status === 'active');
    if (sessions.length === 0) return;
    logger.info({ count: sessions.length }, 'Scheduler tick — running active sessions');
    await Promise.allSettled(sessions.map(s => runSession(s.id)));
  });

  logger.info({}, 'Autopilot scheduler started — runs every 5 minutes');
}

export { getNextRun };
ENDSCHEDULER

cat > src/routes/autopilot.ts << 'ENDAUTOPILOT'
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { v4 as uuidv4 } from 'uuid';
import { store } from '../store';
import { logger } from '../logger';
import { AutopilotSession } from '../types';
import { getNextRun } from '../scheduler';

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

const updateSchema = Joi.object({
  portfolio: Joi.array().items(portfolioAssetSchema).min(1).max(20).optional(),
  strategy: Joi.string().valid('news_momentum', 'trend_following', 'risk_adjusted').optional(),
  risk_tolerance: Joi.string().valid('low', 'medium', 'high').optional(),
  assets: Joi.array().items(Joi.string().uppercase()).max(10).optional(),
  webhook_url: Joi.string().uri().optional(),
  alert_on_hold: Joi.boolean().optional(),
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
    next_run: getNextRun(),
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
    next_run: session.next_run,
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
  const next_run = status === 'active' ? getNextRun() : undefined;
  store.update(req.params.id, { status, next_run });
  logger.info({ id: req.params.id, status }, 'Autopilot session updated');
  res.json({ id: req.params.id, status, next_run });
});

// POST /v1/autopilot/:id/update — update session config
router.post('/:id/update', (req: Request, res: Response) => {
  const session = store.get(req.params.id);
  if (!session) {
    res.status(404).json({ error: 'Session not found' });
    return;
  }
  const { error, value } = updateSchema.validate(req.body);
  if (error) {
    res.status(400).json({ error: 'Validation failed', details: error.details[0].message });
    return;
  }
  store.update(req.params.id, value);
  logger.info({ id: req.params.id }, 'Autopilot session config updated');
  const updated = store.get(req.params.id);
  res.json({ id: req.params.id, message: 'Session updated', session: updated });
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

echo "✅ Patch applied!"
echo "Next: npm run dev"