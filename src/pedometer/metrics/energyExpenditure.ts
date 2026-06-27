import { ACSM_KCAL_DIVISOR, MET_RESTING_VO2_ML_PER_KG_MIN } from './constants';

/**
 * ACSM metabolic equation (steady-state aerobic work):
 *   VO₂ (mL·kg⁻¹·min⁻¹) = MET × 3.5
 *   Energy (kcal·min⁻¹) = (MET × 3.5 × mass_kg) / 200
 *
 * Total session energy:
 *   ΔEE (kcal) = (MET × 3.5 × kg / 200) × duration_min
 *            = MET × kg × hours × 1.05  (algebraically equivalent)
 */
export function kcalPerMinute(met: number, massKg: number): number {
  if (met <= 0 || massKg <= 0) return 0;
  return (met * MET_RESTING_VO2_ML_PER_KG_MIN * massKg) / ACSM_KCAL_DIVISOR;
}

export function totalKcal(met: number, massKg: number, durationMinutes: number): number {
  return kcalPerMinute(met, massKg) * Math.max(0, durationMinutes);
}

/** Net activity kcal above resting (subtract 1 MET baseline). */
export function netActivityKcal(met: number, massKg: number, durationMinutes: number): number {
  const gross = totalKcal(met, massKg, durationMinutes);
  const resting = totalKcal(1, massKg, durationMinutes);
  return Math.max(0, gross - resting);
}
