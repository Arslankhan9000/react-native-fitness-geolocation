import {
  CADENCE_MODERATE_MIN,
  CADENCE_VIGOROUS_MIN,
  MET_MODERATE_MAX,
  MET_MODERATE_MIN,
  MET_VIGOROUS_MIN,
  WALKING_MET_BY_SPEED_MPS,
} from './constants';

export type IntensityBand = 'sedentary' | 'light' | 'moderate' | 'vigorous';

export interface MetEstimate {
  met: number;
  band: IntensityBand;
  cadenceSpm: number | null;
  speedMps: number | null;
}

function interpolateMet(speedMps: number): number {
  const table = WALKING_MET_BY_SPEED_MPS;
  if (speedMps <= table[0].speedMps) return table[0].met;
  for (let i = 1; i < table.length; i++) {
    const hi = table[i];
    const lo = table[i - 1];
    if (speedMps <= hi.speedMps) {
      const t = (speedMps - lo.speedMps) / (hi.speedMps - lo.speedMps);
      return lo.met + t * (hi.met - lo.met);
    }
  }
  const last = table[table.length - 1];
  const prev = table[table.length - 2];
  const slope = (last.met - prev.met) / (last.speedMps - prev.speedMps);
  return last.met + slope * (speedMps - last.speedMps);
}

function bandFromMet(met: number): IntensityBand {
  if (met >= MET_VIGOROUS_MIN) return 'vigorous';
  if (met >= MET_MODERATE_MIN && met <= MET_MODERATE_MAX) return 'moderate';
  if (met > 1.5) return 'light';
  return 'sedentary';
}

/**
 * MET from cadence when speed unknown (Tudor-Locke cadence–intensity mapping).
 */
export function metFromCadence(cadenceSpm: number): number {
  if (cadenceSpm >= CADENCE_VIGOROUS_MIN) return 6.5;
  if (cadenceSpm >= CADENCE_MODERATE_MIN) return 3.8;
  if (cadenceSpm >= 60) return 2.5;
  return 1.5;
}

/**
 * Combined MET estimate — prefers speed (Compendium), falls back to cadence.
 */
export function estimateMet(
  speedMps: number | null,
  cadenceSpm: number | null,
): MetEstimate {
  let met: number;
  if (speedMps != null && Number.isFinite(speedMps) && speedMps > 0.1) {
    met = interpolateMet(speedMps);
  } else if (cadenceSpm != null && cadenceSpm > 0) {
    met = metFromCadence(cadenceSpm);
  } else {
    met = 1.3;
  }

  return {
    met,
    band: bandFromMet(met),
    cadenceSpm,
    speedMps,
  };
}
