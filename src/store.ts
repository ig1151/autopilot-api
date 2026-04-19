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
