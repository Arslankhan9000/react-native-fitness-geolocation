import type { ActivityOptions, ActivitySummary } from './types';
import { createActivityManager } from './ActivityManager';
import { diagnosticsEngine } from './engines/DiagnosticsEngine';
import { Health } from './Health';

/**
 * Tracking — vNext foundation facade.
 *
 * Non-breaking: existing `Geolocation`, `ActivityManager`, `FitnessTrackingService` remain.
 * New apps can build on this facade for an engine-oriented architecture.
 */
export const Tracking = {
  /** Start a new tracking session (native-first). */
  async start(options: ActivityOptions): Promise<{ sessionId: string }> {
    diagnosticsEngine.log('info', 'tracking_start_request', { activityType: options.activityType });
    const mgr = createActivityManager(options);
    const sessionId = await mgr.start();
    return { sessionId };
  },

  /** Stop the current session (returns summary). */
  async stop(manager: ReturnType<typeof createActivityManager>): Promise<ActivitySummary> {
    diagnosticsEngine.log('info', 'tracking_stop_request', {});
    return manager.end();
  },

  async getHealth(): Promise<{ score: number; issues: any[]; recommendations: any[] }> {
    const health = await Health.getHealth();
    return { score: health.score, issues: health.issues, recommendations: health.recommendations };
  },

  async getDiagnosticsTimeline() {
    return diagnosticsEngine.getTimeline();
  },
};

export default Tracking;

