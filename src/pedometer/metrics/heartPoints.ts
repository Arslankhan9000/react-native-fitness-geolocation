import { MET_MODERATE_MIN, MET_VIGOROUS_MIN } from './constants';
import type { IntensityBand } from './metModel';

/**
 * Heart Points — Google Fit / WHO-aligned moderate-to-vigorous credit.
 *
 * - Moderate (3–6 MET): 1 point per active minute
 * - Vigorous (>6 MET): 2 points per active minute
 * - Light/sedentary: 0 points
 *
 * WHO 150 min/week moderate ≡ ~150 HP/week at this mapping.
 */
export function heartPointsForMinute(met: number): number {
  if (met >= MET_VIGOROUS_MIN) return 2;
  if (met >= MET_MODERATE_MIN) return 1;
  return 0;
}

export function heartPointsForSession(met: number, activeMinutes: number): number {
  return heartPointsForMinute(met) * Math.max(0, activeMinutes);
}

export function activeMinutesFromBand(band: IntensityBand, durationMinutes: number): number {
  if (band === 'moderate' || band === 'vigorous') return durationMinutes;
  return 0;
}
