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
