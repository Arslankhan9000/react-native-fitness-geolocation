import { HEART_POINTS_WEEKLY_GOAL, WHO_MODERATE_MINUTES_PER_WEEK } from './constants';
import { heartPointsForSession, activeMinutesFromBand } from './heartPoints';
import { estimateMet } from './metModel';
import { netActivityKcal, totalKcal } from './energyExpenditure';
import { distanceFromSteps, estimateStrideMeters, type StrideSex } from './strideModel';

export interface PedometerMetricsInput {
  steps: number;
  /** Session duration (ms) */
  durationMs: number;
  /** Measured distance (m) — if from native CMPedometer, preferred over stride estimate */
  measuredDistanceM?: number;
  /** User mass (kg) — required for calories */
  massKg: number;
  /** Stature (m) — for stride-based distance */
  heightM: number;
  sex?: StrideSex;
  /** Age (years) — reserved for future HR-zone models */
  ageYears?: number;
}

export interface PedometerMetricsResult {
  steps: number;
  durationMs: number;
  durationMinutes: number;

  /** Distance (m): native measurement or stride model */
  distanceM: number;
  distanceSource: 'measured' | 'stride_model';

  cadenceSpm: number;
  speedMps: number;

  strideM: number;
  met: number;
  intensityBand: 'sedentary' | 'light' | 'moderate' | 'vigorous';

  /** Gross energy at estimated MET (kcal) */
  grossKcal: number;
  /** Net above resting 1-MET (kcal) */
  netKcal: number;

  /** Moderate/vigorous minutes in session */
  activeMinutes: number;
  /** Google Fit–style Heart Points */
  heartPoints: number;

  /** Progress toward WHO / Google weekly goals (0–1) if applied to this session only */
  whoWeeklyProgress: number;
  heartPointsWeeklyProgress: number;
}

/**
 * Compute science-backed pedometer metrics from steps + duration + anthropometrics.
 * Pure functions — no native calls, fully testable / replayable.
 */
export function computePedometerMetrics(input: PedometerMetricsInput): PedometerMetricsResult {
  const steps = Math.max(0, Math.floor(input.steps));
  const durationMs = Math.max(0, input.durationMs);
  const durationMinutes = durationMs / 60_000;
  const massKg = input.massKg;
  const heightM = input.heightM;

  const cadenceSpm = durationMinutes > 0 ? steps / durationMinutes : 0;

  const preliminarySpeed =
    durationMs > 0 && input.measuredDistanceM != null && input.measuredDistanceM > 0
      ? input.measuredDistanceM / (durationMs / 1000)
      : null;

  const strideM = estimateStrideMeters({
    heightM,
    sex: input.sex,
    speedMps: preliminarySpeed ?? (cadenceSpm > 0 ? (cadenceSpm / 60) * heightM * 0.414 : undefined),
  });

  const modeledDistance = distanceFromSteps(steps, strideM);
  const distanceM =
    input.measuredDistanceM != null && input.measuredDistanceM > 0
      ? input.measuredDistanceM
      : modeledDistance;
  const distanceSource =
    input.measuredDistanceM != null && input.measuredDistanceM > 0 ? 'measured' : 'stride_model';

  const speedMps = durationMs > 0 ? distanceM / (durationMs / 1000) : 0;

  const { met, band } = estimateMet(speedMps, cadenceSpm);

  const grossKcal = totalKcal(met, massKg, durationMinutes);
  const netKcal = netActivityKcal(met, massKg, durationMinutes);

  const activeMinutes = activeMinutesFromBand(band, durationMinutes);
  const heartPoints = heartPointsForSession(met, activeMinutes);

  return {
    steps,
    durationMs,
    durationMinutes,
    distanceM,
    distanceSource,
    cadenceSpm,
    speedMps,
    strideM,
    met,
    intensityBand: band,
    grossKcal,
    netKcal,
    activeMinutes,
    heartPoints,
    whoWeeklyProgress: Math.min(1, activeMinutes / WHO_MODERATE_MINUTES_PER_WEEK),
    heartPointsWeeklyProgress: Math.min(1, heartPoints / HEART_POINTS_WEEKLY_GOAL),
  };
}
