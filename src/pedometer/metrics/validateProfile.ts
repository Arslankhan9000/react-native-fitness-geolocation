import { PedometerError } from '../errors';
import type { PedometerMetricsInput, PedometerMetricsResult } from './computePedometerMetrics';
import { computePedometerMetrics } from './computePedometerMetrics';

const MASS_KG_MIN = 20;
const MASS_KG_MAX = 300;
const HEIGHT_M_MIN = 0.9;
const HEIGHT_M_MAX = 2.5;

export interface ValidatedProfile {
  massKg: number;
  heightM: number;
  sex?: PedometerMetricsInput['sex'];
  ageYears?: number;
  /** True when fallbacks were applied */
  profileAdjusted: boolean;
  warnings: string[];
}

export function validateProfile(input: {
  massKg?: number;
  heightM?: number;
  sex?: PedometerMetricsInput['sex'];
  ageYears?: number;
}): ValidatedProfile {
  const warnings: string[] = [];
  let profileAdjusted = false;

  let massKg = input.massKg ?? 70;
  if (!Number.isFinite(massKg) || massKg < MASS_KG_MIN || massKg > MASS_KG_MAX) {
    warnings.push(`massKg out of range; using 70 kg`);
    massKg = 70;
    profileAdjusted = true;
  }

  let heightM = input.heightM ?? 1.7;
  if (!Number.isFinite(heightM) || heightM < HEIGHT_M_MIN || heightM > HEIGHT_M_MAX) {
    warnings.push(`heightM out of range; using 1.70 m`);
    heightM = 1.7;
    profileAdjusted = true;
  }

  let ageYears = input.ageYears;
  if (ageYears != null && (!Number.isFinite(ageYears) || ageYears < 5 || ageYears > 120)) {
    warnings.push(`ageYears ignored`);
    ageYears = undefined;
    profileAdjusted = true;
  }

  return {
    massKg,
    heightM,
    sex: input.sex,
    ageYears,
    profileAdjusted,
    warnings,
  };
}

export function computePedometerMetricsSafe(
  input: PedometerMetricsInput,
): PedometerMetricsResult & { warnings: string[] } {
  if (input.steps < 0 || !Number.isFinite(input.steps)) {
    throw new PedometerError('INVALID_STATE', 'steps must be a non-negative finite number');
  }

  const profile = validateProfile(input);
  const result = computePedometerMetrics({
    ...input,
    steps: Math.max(0, Math.floor(input.steps)),
    durationMs: Math.max(0, input.durationMs),
    massKg: profile.massKg,
    heightM: profile.heightM,
    sex: profile.sex,
    ageYears: profile.ageYears,
  });

  return { ...result, warnings: profile.warnings };
}
