import { getFitnessGeolocationNative } from '../native/getNativeModule';
import type { ActivityOptions, ActivitySummary } from '../types';
import { diagnosticsEngine } from './DiagnosticsEngine';

const Native = getFitnessGeolocationNative();

export interface CreateSessionParams {
  name: string;
  activityType: string;
  extras?: Record<string, unknown> | null;
}

/**
 * ActivityEngine (JS facade)
 *
 * Source of truth is native. This class only provides:
 * - stable typed entry points
 * - consistent diagnostics events
 * - non-breaking adaptation for older call patterns
 */
export class ActivityEngine {
  async createSession(params: CreateSessionParams): Promise<string> {
    const extras = params.extras ? JSON.stringify(params.extras) : null;
    diagnosticsEngine.log('info', 'session_create', { name: params.name, activityType: params.activityType });
    return Native.createSession(params.name, params.activityType, extras);
  }

  async endSession(sessionId: string, summary: Partial<ActivitySummary>): Promise<boolean> {
    diagnosticsEngine.log('info', 'session_end', { sessionId });
    return Native.endSession(sessionId, {
      totalDistance: summary.totalDistance ?? 0,
      totalDuration: summary.duration ?? 0,
      totalActiveDuration: summary.activeDuration ?? 0,
      maxSpeed: summary.maxSpeed ?? 0,
      elevationGain: summary.elevationGain ?? 0,
      pauseCount: (summary as any).pauseCount ?? 0,
    });
  }

  async discardSession(sessionId: string): Promise<boolean> {
    diagnosticsEngine.log('warn', 'session_discard', { sessionId });
    return Native.discardSession(sessionId);
  }

  async getPendingSessions(): Promise<ActivitySummary[]> {
    const rows = (await Native.getPendingSessions?.()) ?? [];
    return rows as ActivitySummary[];
  }

  async configure(options: ActivityOptions): Promise<void> {
    // Keep this as a single point for future native profiles / strategies.
    Native.setConfiguration?.({
      trackingMode: options.trackingMode,
    });
  }
}

export const activityEngine = new ActivityEngine();
export default activityEngine;

