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
