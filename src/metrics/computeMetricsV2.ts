export interface MetricsV2Point {
  latitude: number;
  longitude: number;
  accuracy?: number;
  altitude?: number;
  timestamp: number; // ms
  speed?: number; // m/s
}

export interface MetricsV2Summary {
  sessionId: string;
  pointCount: number;
  totalDistance2d: number;
  correctedDistance2d: number;
  movingDistance2d: number;
  maxSpeedMps: number;
  averageSpeedMps: number;
  droppedPoints: number;
  notes: string[];
}

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

/**
 * Haversine distance (2D) in meters.
 * Complexity: O(1)
 */
export function distance2dMeters(a: MetricsV2Point, b: MetricsV2Point): number {
  const R = 6371000;
  const dLat = toRad(b.latitude - a.latitude);
  const dLon = toRad(b.longitude - a.longitude);
  const lat1 = toRad(a.latitude);
  const lat2 = toRad(b.latitude);
  const s =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
  return R * c;
}

/**
 * Corrected distance pipeline (V2)
 *
 * Pipeline:
 * - timestamp sanity
 * - accuracy gating (optional)
 * - outlier rejection by implied speed (meters / second)
 * - sum remaining segments
 *
 * Complexity: O(n)
 */
export function computeMetricsV2(
  sessionId: string,
  points: MetricsV2Point[],
  options?: {
    maxAccuracyM?: number;
    maxImpliedSpeedMps?: number;
    movingSpeedThresholdMps?: number;
  },
): MetricsV2Summary {
  const maxAccuracyM = options?.maxAccuracyM ?? 60;
  const maxImpliedSpeedMps = options?.maxImpliedSpeedMps ?? 12;
  const movingSpeedThresholdMps = options?.movingSpeedThresholdMps ?? 0.5;

  let total = 0;
  let corrected = 0;
  let moving = 0;
  let maxSpeed = 0;
  let dropped = 0;
  const notes: string[] = [];

  const cleaned = points
    .filter(p => Number.isFinite(p.latitude) && Number.isFinite(p.longitude) && Number.isFinite(p.timestamp))
    .sort((a, b) => a.timestamp - b.timestamp);

  if (cleaned.length < 2) {
    return {
      sessionId,
      pointCount: cleaned.length,
      totalDistance2d: 0,
      correctedDistance2d: 0,
      movingDistance2d: 0,
      maxSpeedMps: 0,
      averageSpeedMps: 0,
      droppedPoints: 0,
      notes: ['INSUFFICIENT_POINTS'],
    };
  }

  let prev = cleaned[0];
  for (let i = 1; i < cleaned.length; i++) {
    const cur = cleaned[i];
    const dt = (cur.timestamp - prev.timestamp) / 1000;
    if (!Number.isFinite(dt) || dt <= 0) {
      dropped++;
      continue;
    }

    const seg = distance2dMeters(prev, cur);
    total += seg;

    const implied = seg / dt;
    const prevAcc = prev.accuracy ?? 0;
    const curAcc = cur.accuracy ?? 0;
    const accOk = (prevAcc <= 0 || prevAcc <= maxAccuracyM) && (curAcc <= 0 || curAcc <= maxAccuracyM);

    if (!accOk || implied > maxImpliedSpeedMps) {
      dropped++;
      prev = cur;
      continue;
    }

    corrected += seg;
    if (implied >= movingSpeedThresholdMps) moving += seg;
    if (implied > maxSpeed) maxSpeed = implied;
    prev = cur;
  }

  const elapsedS = (cleaned[cleaned.length - 1].timestamp - cleaned[0].timestamp) / 1000;
  const avg = elapsedS > 0 ? corrected / elapsedS : 0;
  if (dropped > 0) notes.push('OUTLIERS_DROPPED');

  return {
    sessionId,
    pointCount: cleaned.length,
    totalDistance2d: total,
    correctedDistance2d: corrected,
    movingDistance2d: moving,
    maxSpeedMps: maxSpeed,
    averageSpeedMps: avg,
    droppedPoints: dropped,
    notes,
  };
}

