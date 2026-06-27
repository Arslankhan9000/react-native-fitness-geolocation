import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

/**
 * TurboModule spec (codegen) for FitnessGeolocation.
 *
 * Design rules:
 * - Keep types permissive (`Record<string, unknown>`) to avoid breaking rapid iteration.
 * - Preserve the existing public JS API. This spec only defines the native surface.
 * - Events remain delivered via the existing emitter contract (`addListener/removeListeners`).
 *
 * NOTE: This file is consumed by RN codegen when New Architecture is enabled.
 */
export interface Spec extends TurboModule {
  // EventEmitter contract (required by RN for native event modules)
  addListener(eventName: string): void;
  removeListeners(count: number): void;

  // ─── Geolocation core ────────────────────────────────────────────────────
  getCurrentPosition(options: Object): Promise<Object>;
  watchPosition(options: Object): number;
  clearWatch(watchId: number): void;
  stopLocationObserving(): void;

  // Queue / offline delivery
  getPendingForJs(limit: number): Promise<Array<Object>>;
  markDelivered(ids: string[]): Promise<number>;
  purgeDelivered(): Promise<number>;
  getQueueSize(): Promise<number>;

  // Authorization
  requestAuthorization(level: string): Promise<string>;
  getAuthorizationStatus(): Promise<{ status: string; always: boolean }>;

  // Config / lifecycle (background engine)
  ready(config: Object): Promise<Object>;
  setConfiguration(config: Object): Promise<void>;
  setConfig(config: Object): Promise<Object>;
  getState(): Promise<Object>;
  start(): Promise<Object>;
  stop(): Promise<Object>;
  reset(): Promise<void>;
  changePace(isMoving: boolean): Promise<void>;
  setActivityPaused(paused: boolean): Promise<void>;

  // Schedule / geofences / sync
  startSchedule(): Promise<void>;
  stopSchedule(): Promise<void>;
  startGeofences(): Promise<void>;
  sync(): Promise<Array<Object>>;
  httpSync(): Promise<Array<Object>>;
  configureHttp(config: Object): Promise<void>;

  // Persistence CRUD
  getLocations(): Promise<Array<Object>>;
  destroyLocation(uuid: string): Promise<boolean>;
  destroyLocations(): Promise<number>;
  getCount(): Promise<number>;
  insertLocation(params: Object): Promise<string | null>;

  // Sessions
  createSession(name: string, activityType: string, extras: string | null): Promise<string>;
  endSession(sessionId: string, data: Object): Promise<boolean>;
  discardSession(sessionId: string): Promise<boolean>;
  getPendingSessions(): Promise<Array<Object>>;

  // Motion / auto-pause
  startMotionTracking(includePedometer: boolean): Promise<null>;
  stopMotionTracking(): Promise<null>;
  configureAutoPause(config: Object): Promise<void>;

  // Diagnostics / logger
  configureLogger(config: Object): Promise<void>;
  getDiagnostics(): Promise<Array<Object>>;
  devLog(level: string, tag: string, message: string, data: Object | null): void;
  log(level: string, message: string, data: Object | null): Promise<void>;
  getLog(query: Object): Promise<string>;
  destroyLog(): Promise<number>;
  uploadLog(url: string, query: Object): Promise<boolean>;

  // iOS Live Activities (no-ops on unsupported platforms)
  setLiveActivityEnabled(enabled: boolean): void;
  getLiveActivityEnabled(): Promise<boolean>;
  startLiveActivity(name: string, activityType: string): Promise<void>;
  updateLiveActivity(
    distance: number,
    duration: number,
    pace: string,
    speed: number,
    calories: number,
    gpsStatus: string,
    isPaused: boolean,
  ): void;
  endLiveActivity(distance: number, duration: number, calories: number): Promise<void>;

  // Platform-specific
  requestTemporaryFullAccuracy(purpose: string): Promise<boolean>;
  isIgnoringBatteryOptimizations(): Promise<boolean>;
  requestBatteryOptimizationPermission(): Promise<boolean>;
  openOemBatterySettings(): Promise<boolean>;

  // Time-based tracker
  startTimeBasedTracking(options: Object): number;
  stopTimeBasedTracking(watchId: number): Promise<void>;
  pauseTimeBasedTracking(watchId: number): Promise<void>;
  resumeTimeBasedTracking(watchId: number): Promise<void>;
  setTimeBasedInterval(watchId: number, intervalMs: number): Promise<void>;

  // Odometer
  getOdometer(): Promise<number>;
  resetOdometer(): Promise<void>;
  setOdometer(value: number): Promise<void>;

  // Pedometer (passive — no notification)
  pedometerIsSupported(): Promise<Object>;
  pedometerStart(sessionId: string | null): Promise<Object>;
  pedometerStop(): Promise<Object>;
  pedometerGetSnapshot(): Promise<Object>;
  pedometerQuery(fromMs: number, toMs: number): Promise<Object>;
  pedometerOnAppForeground(): void;
}

export default TurboModuleRegistry.get<Spec>('FitnessGeolocation');

