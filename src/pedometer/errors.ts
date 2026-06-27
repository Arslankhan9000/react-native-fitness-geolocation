/** Typed errors for pedometer subsystem — stable codes for app telemetry. */
export type PedometerErrorCode =
  | 'NOT_SUPPORTED'
  | 'PERMISSION_DENIED'
  | 'NATIVE_UNAVAILABLE'
  | 'NATIVE_FAILED'
  | 'ALREADY_RUNNING'
  | 'NOT_RUNNING'
  | 'INVALID_STATE';

export class PedometerError extends Error {
  readonly code: PedometerErrorCode;
  readonly cause?: unknown;

  constructor(code: PedometerErrorCode, message: string, cause?: unknown) {
    super(message);
    this.name = 'PedometerError';
    this.code = code;
    this.cause = cause;
  }
}

export function isPedometerError(e: unknown): e is PedometerError {
  return e instanceof PedometerError;
}
