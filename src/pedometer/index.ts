export { Pedometer, PedometerError, isPedometerError } from './Pedometer';
export { PedometerPermission } from './PedometerPermission';
export { PedometerHealth } from './PedometerHealth';
export type { PedometerHealthResult, PedometerDiagnostics } from './PedometerHealth';
export { createStepCountFilter } from './StepCountFilter';
export {
  PedometerMetrics,
  computePedometerMetrics,
  computePedometerMetricsSafe,
  validateProfile,
  estimateStrideMeters,
  estimateMet,
  heartPointsForSession,
  totalKcal,
} from './metrics/PedometerMetrics';
export type {
  PedometerMetricsInput,
  PedometerMetricsResult,
  PedometerMetricsProfile,
  PedometerMetricsResultWithWarnings,
} from './metrics/PedometerMetrics';
export type * from './types';
