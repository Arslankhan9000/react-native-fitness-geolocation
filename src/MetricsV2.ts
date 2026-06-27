import { getFitnessGeolocationNative } from './native/getNativeModule';
import type { MetricsV2Point, MetricsV2Summary } from './metrics/computeMetricsV2';
import { computeMetricsV2 } from './metrics/computeMetricsV2';

/**
 * MetricsV2 — corrected distance / pacing pipeline (JS-side reference implementation).
 *
 * This module is designed to be:
 * - deterministic (replay-friendly)
 * - profile-aware (future: activity profiles)
 * - offline-first (operates on persisted points from native storage)
 *
 * NOTE: The long-term target is to run the same pipeline natively for maximum reliability.
 * This JS implementation ships now as a stable API and as a test oracle for native parity.
 */

const Native = getFitnessGeolocationNative();

export { computeMetricsV2 } from './metrics/computeMetricsV2';

export const MetricsV2 = {
  /**
   * Compute MetricsV2 for a stored session using native persisted points.
   * Works offline.
   */
  async getSessionSummary(sessionId: string): Promise<MetricsV2Summary | null> {
    const session = await Native.getSessionForUpload?.(sessionId);
    if (!session) return null;
    const points = (session.points ?? []) as any[];
    const mapped: MetricsV2Point[] = points.map(p => ({
      latitude: Number(p.latitude),
      longitude: Number(p.longitude),
      accuracy: p.accuracy != null ? Number(p.accuracy) : undefined,
      altitude: p.altitude != null ? Number(p.altitude) : undefined,
      timestamp: Number(p.timestamp),
      speed: p.speed != null ? Number(p.speed) : undefined,
    }));
    return computeMetricsV2(sessionId, mapped);
  },
};

export default MetricsV2;

