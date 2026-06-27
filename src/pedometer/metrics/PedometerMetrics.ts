import type { PedometerStepEvent } from '../types';
import type { PedometerMetricsInput, PedometerMetricsResult } from './computePedometerMetrics';
import { computePedometerMetricsSafe } from './validateProfile';

export { computePedometerMetrics } from './computePedometerMetrics';
export { computePedometerMetricsSafe, validateProfile } from './validateProfile';
export type { PedometerMetricsInput, PedometerMetricsResult } from './computePedometerMetrics';
export { estimateStrideMeters, distanceFromSteps } from './strideModel';
export { estimateMet, metFromCadence } from './metModel';
export { kcalPerMinute, totalKcal, netActivityKcal } from './energyExpenditure';
export { heartPointsForMinute, heartPointsForSession } from './heartPoints';

export interface PedometerMetricsProfile {
  massKg: number;
  heightM: number;
  sex?: PedometerMetricsInput['sex'];
  ageYears?: number;
}

export type PedometerMetricsResultWithWarnings = PedometerMetricsResult & { warnings: string[] };

export const PedometerMetrics = {
  compute(input: PedometerMetricsInput): PedometerMetricsResultWithWarnings {
    return computePedometerMetricsSafe(input);
  },

  fromStepEvent(
    event: PedometerStepEvent,
    profile: PedometerMetricsProfile,
  ): PedometerMetricsResultWithWarnings {
    const durationMs = Math.max(1, event.endDate - event.startDate);
    return computePedometerMetricsSafe({
      steps: event.steps,
      durationMs,
      measuredDistanceM: event.distance > 0 ? event.distance : undefined,
      massKg: profile.massKg,
      heightM: profile.heightM,
      sex: profile.sex,
      ageYears: profile.ageYears,
    });
  },
};
