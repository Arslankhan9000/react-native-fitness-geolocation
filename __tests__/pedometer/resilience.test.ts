import { parseStepEvent, EMPTY_STEP_EVENT } from '../../src/pedometer/parseStepEvent';
import { validateProfile } from '../../src/pedometer/metrics/validateProfile';

describe('parseStepEvent', () => {
  it('sanitizes NaN and negative values', () => {
    const e = parseStepEvent({
      steps: 'bad',
      distance: -5,
      startDate: 1000,
      endDate: 500,
      isRunning: 1,
    });
    expect(e.steps).toBe(0);
    expect(e.distance).toBe(0);
    expect(e.endDate).toBeGreaterThanOrEqual(1000);
  });

  it('returns empty event for null', () => {
    expect(parseStepEvent(null)).toEqual(expect.objectContaining({ steps: 0 }));
  });
});

describe('validateProfile', () => {
  it('clamps invalid anthropometrics', () => {
    const v = validateProfile({ massKg: 5, heightM: 0.5 });
    expect(v.profileAdjusted).toBe(true);
    expect(v.massKg).toBe(70);
    expect(v.warnings.length).toBeGreaterThan(0);
  });
});
