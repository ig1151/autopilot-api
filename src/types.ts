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
