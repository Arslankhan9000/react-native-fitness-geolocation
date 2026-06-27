/**
 * Literature-backed constants for pedometer-derived physiology metrics.
 *
 * References:
 * - Ainsworth BE et al. (2011) Compendium of Physical Activities Medicine & Science in Sports & Exercise.
 * - WHO (2020) Guidelines on physical activity and sedentary behaviour.
 * - Tudor-Locke C et al. (2018) Step cadence and intensity in adults: SCANDINAVIAN J Med Sci Sports.
 * - Google Fit Heart Points (1 min moderate = 1 HP, 1 min vigorous = 2 HP).
 * - ACSM metabolic calculation: kcal/min = (MET × 3.5 × kg) / 200.
 */

/** 1 MET ≡ 3.5 mL O₂·kg⁻¹·min⁻¹ (resting metabolic rate reference). */
export const MET_RESTING_VO2_ML_PER_KG_MIN = 3.5;

/** ACSM energy conversion divisor (kcal/min from MET × mass). */
export const ACSM_KCAL_DIVISOR = 200;

/** O₂ energy density ≈ 5.05 kcal·L⁻¹ (used in some lab derivations; ACSM uses compact form above). */
export const O2_ENERGY_KCAL_PER_LITER = 5.05;

/** Anthropometric stride factors (stride ≈ factor × height_m). */
export const STRIDE_FACTOR_WALK_MALE = 0.415;
export const STRIDE_FACTOR_WALK_FEMALE = 0.413;
export const STRIDE_FACTOR_WALK_NEUTRAL = 0.414;

/** Cadence thresholds (steps·min⁻¹) — Tudor-Locke et al. 2018 meta-analysis. */
export const CADENCE_LIGHT_MAX = 99;
export const CADENCE_MODERATE_MIN = 100;
export const CADENCE_VIGOROUS_MIN = 130;

/** MET band edges (Compendium walking codes 17151–17270). */
export const MET_LIGHT_MAX = 2.9;
export const MET_MODERATE_MIN = 3.0;
export const MET_MODERATE_MAX = 6.0;
export const MET_VIGOROUS_MIN = 6.1;

/** WHO weekly targets (minutes of moderate-equivalent activity). */
export const WHO_MODERATE_MINUTES_PER_WEEK = 150;

/** Google Fit weekly Heart Points goal. */
export const HEART_POINTS_WEEKLY_GOAL = 150;

/**
 * Walking speed (m·s⁻¹) → MET via Compendium piecewise linear interpolation.
 * Anchors: 0.89 m/s (2 mph)=2.8, 1.34 m/s (3 mph)=3.5, 1.79 m/s (4 mph)=5.0, 2.24 m/s (5 mph)=8.3
 */
export const WALKING_MET_BY_SPEED_MPS: ReadonlyArray<{ speedMps: number; met: number }> = [
  { speedMps: 0.0, met: 1.3 },
  { speedMps: 0.89, met: 2.8 },
  { speedMps: 1.12, met: 3.0 },
  { speedMps: 1.34, met: 3.5 },
  { speedMps: 1.56, met: 4.0 },
  { speedMps: 1.79, met: 5.0 },
  { speedMps: 2.01, met: 6.5 },
  { speedMps: 2.24, met: 8.3 },
  { speedMps: 2.68, met: 9.8 },
  { speedMps: 3.13, met: 11.0 },
];
