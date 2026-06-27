import type { PedometerStepEvent } from './types';

export interface StepCountFilterOptions {
  /** Reject bursts faster than this cadence (default 220ms ≈ 273 spm) */
  minimumStepIntervalMs?: number;
}

/**
 * Stateful live-update filter — inspired by
 * [@dongminyu/react-native-step-counter](https://github.com/AndrewDongminYoo/react-native-step-counter)
 * and accelerometer peak detectors in [stepUp](https://github.com/adildsw/stepUp).
 *
 * Drops impossible cadence bursts (phone rotation, pocket jostle) and rebases
 * cumulative counts so ignored steps do not reappear on the next event.
 */
export function createStepCountFilter(options: StepCountFilterOptions = {}) {
  const minInterval = options.minimumStepIntervalMs ?? 220;
  let lastAcceptedEnd = 0;
  let lastAcceptedSteps = 0;
  let rebasedOffset = 0;

  return (data: PedometerStepEvent): PedometerStepEvent | null => {
    const steps = data.steps;
    const endDate = data.endDate;

    // Native counter reset (reboot) — accept new baseline
    if (steps < lastAcceptedSteps + rebasedOffset) {
      lastAcceptedEnd = 0;
      lastAcceptedSteps = 0;
      rebasedOffset = 0;
    }

    if (lastAcceptedEnd > 0) {
      const deltaSteps = steps - lastAcceptedSteps - rebasedOffset;
      const deltaMs = endDate - lastAcceptedEnd;
      if (deltaSteps > 0 && deltaMs > 0 && deltaMs < deltaSteps * minInterval) {
        rebasedOffset += deltaSteps;
        return null;
      }
    }

    lastAcceptedEnd = endDate;
    lastAcceptedSteps = steps - rebasedOffset;
    return { ...data, steps: lastAcceptedSteps };
  };
}
