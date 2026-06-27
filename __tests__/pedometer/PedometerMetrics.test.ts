import { computePedometerMetrics } from '../../src/pedometer/metrics/computePedometerMetrics';
import { kcalPerMinute } from '../../src/pedometer/metrics/energyExpenditure';
import { heartPointsForMinute } from '../../src/pedometer/metrics/heartPoints';
import { metFromCadence } from '../../src/pedometer/metrics/metModel';

describe('computePedometerMetrics', () => {
  const profile = { massKg: 70, heightM: 1.75, sex: 'male' as const };

  it('computes distance from stride when no native distance', () => {
    const r = computePedometerMetrics({
      steps: 2000,
      durationMs: 20 * 60_000,
      ...profile,
    });
    expect(r.distanceSource).toBe('stride_model');
    expect(r.distanceM).toBeGreaterThan(1000);
    expect(r.cadenceSpm).toBeCloseTo(100, 0);
  });

  it('prefers measured distance from CMPedometer', () => {
    const r = computePedometerMetrics({
      steps: 1500,
      durationMs: 15 * 60_000,
      measuredDistanceM: 1200,
      ...profile,
    });
    expect(r.distanceSource).toBe('measured');
    expect(r.distanceM).toBe(1200);
  });

  it('assigns moderate MET and heart points for brisk walk cadence', () => {
    const r = computePedometerMetrics({
      steps: 3000,
      durationMs: 30 * 60_000,
      ...profile,
    });
    expect(r.cadenceSpm).toBe(100);
    expect(r.met).toBeGreaterThanOrEqual(3);
    expect(r.heartPoints).toBe(30);
    expect(r.netKcal).toBeGreaterThan(0);
  });
});

describe('ACSM energy', () => {
  it('matches standard 3.5 MET × kg formula', () => {
    // 3.5 MET, 70 kg → (3.5 * 3.5 * 70) / 200 = 4.2875 kcal/min
    expect(kcalPerMinute(3.5, 70)).toBeCloseTo(4.2875, 3);
  });
});

describe('heart points', () => {
  it('doubles for vigorous MET', () => {
    expect(heartPointsForMinute(7)).toBe(2);
    expect(heartPointsForMinute(4)).toBe(1);
    expect(heartPointsForMinute(2)).toBe(0);
  });
});

describe('cadence MET', () => {
  it('maps Tudor-Locke thresholds', () => {
    expect(metFromCadence(130)).toBeGreaterThanOrEqual(6);
    expect(metFromCadence(110)).toBeGreaterThanOrEqual(3);
  });
});
