import type { PedometerStepEvent } from './types';

const VALID_COUNTER_TYPES = new Set([
  'CMPedometer',
  'STEP_COUNTER',
  'STEP_DETECTOR',
  'ACCELEROMETER',
]);

function finiteNum(v: unknown, fallback = 0): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

/** Defensive parse — never propagates NaN/Infinity to UI or metrics. */
export function parseStepEvent(raw: Record<string, unknown> | null | undefined): PedometerStepEvent {
  const r = raw ?? {};
  const counterRaw = String(r.counterType ?? 'CMPedometer');
  const counterType = (
    VALID_COUNTER_TYPES.has(counterRaw) ? counterRaw : 'CMPedometer'
  ) as PedometerStepEvent['counterType'];

  const steps = Math.max(0, Math.floor(finiteNum(r.steps)));
  const startDate = finiteNum(r.startDate);
  const endDate = Math.max(startDate, finiteNum(r.endDate, startDate));

  return {
    sessionId: typeof r.sessionId === 'string' ? r.sessionId : null,
    isRunning: Boolean(r.isRunning),
    steps,
    distance: Math.max(0, finiteNum(r.distance)),
    startDate,
    endDate,
    floorsAscended: r.floorsAscended != null ? Math.max(0, finiteNum(r.floorsAscended)) : undefined,
    floorsDescended: r.floorsDescended != null ? Math.max(0, finiteNum(r.floorsDescended)) : undefined,
    counterType,
    cadenceSpm: r.cadenceSpm != null ? finiteNum(r.cadenceSpm) : null,
    averageSpeedMps: r.averageSpeedMps != null ? finiteNum(r.averageSpeedMps) : null,
    source: r.source as PedometerStepEvent['source'],
  };
}

export const EMPTY_STEP_EVENT: PedometerStepEvent = {
  sessionId: null,
  isRunning: false,
  steps: 0,
  distance: 0,
  startDate: 0,
  endDate: 0,
  counterType: 'CMPedometer',
  cadenceSpm: null,
  averageSpeedMps: null,
};
