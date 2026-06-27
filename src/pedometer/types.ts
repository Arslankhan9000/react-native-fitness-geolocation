/** Sensor / engine used for step counting */
export type PedometerCounterType =
  | 'CMPedometer'
  | 'STEP_COUNTER'
  | 'STEP_DETECTOR'
  | 'ACCELEROMETER';

export type PedometerPermissionStatus =
  | 'granted'
  | 'denied'
  | 'restricted'
  | 'not_determined'
  | 'unknown';

export interface PedometerSupportResult {
  supported: boolean;
  granted: boolean;
  status: PedometerPermissionStatus;
  platform: 'ios' | 'android';
}

export interface PedometerStepEvent {
  sessionId: string | null;
  isRunning: boolean;
  steps: number;
  distance: number;
  startDate: number;
  endDate: number;
  floorsAscended?: number;
  floorsDescended?: number;
  counterType: PedometerCounterType;
  cadenceSpm?: number | null;
  averageSpeedMps?: number | null;
  source?: 'live' | 'query' | 'foreground_reconcile' | 'boot_reconcile';
}

export interface PedometerStartOptions {
  sessionId?: string;
  /** Apply cadence filter to live updates (default: true) */
  filterLiveUpdates?: boolean;
  /** Minimum ms between accepted steps — rejects hand-shake false positives */
  minimumStepIntervalMs?: number;
}

export interface PedometerQueryResult {
  steps: number;
  distance: number;
  startDate: number;
  endDate: number;
  counterType: PedometerCounterType;
  floorsAscended?: number;
  floorsDescended?: number;
  source?: string;
}
