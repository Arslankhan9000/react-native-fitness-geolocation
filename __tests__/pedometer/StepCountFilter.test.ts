import { createStepCountFilter } from '../../src/pedometer/StepCountFilter';
import type { PedometerStepEvent } from '../../src/pedometer/types';

function baseEvent(steps: number, endDate: number): PedometerStepEvent {
  return {
    sessionId: 's1',
    isRunning: true,
    steps,
    distance: steps * 0.76,
    startDate: 0,
    endDate,
    counterType: 'STEP_COUNTER',
  };
}

describe('createStepCountFilter', () => {
  it('passes normal walking cadence', () => {
    const filter = createStepCountFilter({ minimumStepIntervalMs: 300 });
    const a = filter(baseEvent(1, 1000));
    const b = filter(baseEvent(2, 1400));
    expect(a?.steps).toBe(1);
    expect(b?.steps).toBe(2);
  });

  it('drops impossible burst cadence', () => {
    const filter = createStepCountFilter({ minimumStepIntervalMs: 300 });
    filter(baseEvent(1, 1000));
    const burst = filter(baseEvent(10, 1100));
    expect(burst).toBeNull();
    const next = filter(baseEvent(11, 2000));
    expect(next?.steps).toBe(2);
  });
});
