import {
  STRIDE_FACTOR_WALK_FEMALE,
  STRIDE_FACTOR_WALK_MALE,
  STRIDE_FACTOR_WALK_NEUTRAL,
} from './constants';

export type StrideSex = 'male' | 'female' | 'neutral';

export interface StrideEstimateInput {
  heightM: number;
  sex?: StrideSex;
  /** Optional measured speed (m·s⁻¹) for speed-adjusted stride (Höök et al. 2019 scaling). */
  speedMps?: number;
}

/**
 * Estimate stride length (m) from stature.
 * Baseline: anthropometric walking stride ≈ 0.41–0.415 × height.
 */
export function estimateStrideMeters(input: StrideEstimateInput): number {
  const { heightM, sex = 'neutral', speedMps } = input;
  if (!Number.isFinite(heightM) || heightM <= 0) return 0.762;

  const factor =
    sex === 'male'
      ? STRIDE_FACTOR_WALK_MALE
      : sex === 'female'
        ? STRIDE_FACTOR_WALK_FEMALE
        : STRIDE_FACTOR_WALK_NEUTRAL;

  let stride = factor * heightM;

  // Speed adjustment: stride increases sub-linearly with speed (typical walk 1.0–1.8 m/s).
  if (speedMps != null && Number.isFinite(speedMps) && speedMps > 0.5) {
    const refSpeed = 1.34; // ~3 mph reference
    const ratio = speedMps / refSpeed;
    stride *= Math.pow(ratio, 0.22);
    stride = clamp(stride, heightM * 0.32, heightM * 0.52);
  }

  return stride;
}

export function distanceFromSteps(steps: number, strideM: number): number {
  if (steps <= 0 || strideM <= 0) return 0;
  return steps * strideM;
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v));
}
