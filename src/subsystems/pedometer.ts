/**
 * Passive pedometer subsystem — no GPS, own lifecycle.
 * Import: `react-native-fitness-geolocation/pedometer`
 */
export {
  Pedometer,
  PedometerError,
  isPedometerError,
  PedometerPermission,
  createStepCountFilter,
  PedometerHealth,
  PedometerMetrics,
  computePedometerMetrics,
  computePedometerMetricsSafe,
  estimateStrideMeters,
  estimateMet,
  heartPointsForSession,
  totalKcal,
} from '../pedometer';
export type {
  PedometerStepEvent,
  PedometerStartOptions,
  PedometerSupportResult,
  PedometerCounterType,
  PedometerMetricsInput,
  PedometerMetricsResult,
  PedometerMetricsProfile,
  PedometerMetricsResultWithWarnings,
} from '../pedometer';
export type { PedometerHealthResult, PedometerDiagnostics } from '../pedometer/PedometerHealth';
