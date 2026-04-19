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
