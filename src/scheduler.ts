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
