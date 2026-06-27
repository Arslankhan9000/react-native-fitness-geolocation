import { computeMetricsV2 } from '../src/metrics/computeMetricsV2';

describe('MetricsV2', () => {
  it('drops extreme implied-speed jumps', () => {
    const sessionId = 's1';
    const t0 = 1_000_000;
    const points = [
      { latitude: 37.0, longitude: -122.0, accuracy: 5, timestamp: t0 },
      // huge jump in 1s (outlier)
      { latitude: 38.0, longitude: -122.0, accuracy: 5, timestamp: t0 + 1000 },
      // back to normal near start
      { latitude: 37.0001, longitude: -122.0001, accuracy: 5, timestamp: t0 + 2000 },
    ];

    const summary = computeMetricsV2(sessionId, points as any, { maxImpliedSpeedMps: 12 });
    expect(summary.droppedPoints).toBeGreaterThanOrEqual(1);
    expect(summary.correctedDistance2d).toBeLessThan(summary.totalDistance2d);
  });
});

