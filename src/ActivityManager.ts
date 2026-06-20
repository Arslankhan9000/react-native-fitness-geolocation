import { AppState, NativeModules } from 'react-native';
import { TimeBasedTracker } from './TimeBasedTracker';
import { SmartGPSController } from './SmartGPSController';
import { PermissionManager } from './PermissionManager';
import type {
  ActivityOptions,
  ActivityState,
  ActivityStateSnapshot,
  ActivitySummary,
  GpsStrength,
  LocationSubscription,
  AutoPauseEvent,
  AutoResumeEvent,
  HeartbeatEvent,
} from './types';

const Native = NativeModules.FitnessGeolocation;

type StateChangeCallback = (state: ActivityState) => void;
type ActivityErrorCallback = (error: Error) => void;

const DEFAULT_OPTIONS: ActivityOptions = {
  name: 'Workout',
  activityType: 'running',
  trackingMode: 'fitness',
  intervalMs: 3000,
  adaptiveInterval: true,
  stationaryIntervalMs: 30000,
  autoPause: true,
  autoPauseDelaySeconds: 45,
  autoResume: true,
  includePedometer: false,
  maxAccuracy: 50,
};

/**
 * Full activity lifecycle manager.
 *
 * Manages the complete flow from start → track → pause → resume → end,
 * with smart GPS control, auto-pause/resume, battery optimization handling,
 * and offline-first session storage.
 *
 * Usage:
 * ```
 * const activity = ActivityManager.createActivity({ name: 'Morning Run' });
 * await activity.start(onLocation);
 * // ... later
 * const summary = await activity.end();
 * ```
 */
export class ActivityManager {
  private tracker: TimeBasedTracker;
  private gpsController: SmartGPSController;
  private options: Required<ActivityOptions>;
  private _state: ActivityState = 'idle';
  private _sessionId: string | null = null;
  private _startTime: number = 0;
  private _pauseStartTime: number = 0;
  private _totalPausedMs: number = 0;
  private _pauseCount: number = 0;
  private _elapsedMs: number = 0;
  private _activeMs: number = 0;
  private _totalDistance: number = 0;
  private _currentSpeed: number | null = null;
  private _maxSpeed: number = 0;
  private _totalElevationGain: number = 0;
  private _lastAltitude: number | null = null;
  private _pointCount: number = 0;
  private _batteryLevel: number = -1;
  private _extras: Record<string, unknown> = {};
  private _uploaded: boolean = false;

  private stateChangeListeners = new Set<StateChangeCallback>();
  private errorListeners = new Set<ActivityErrorCallback>();
  private tickUnsub: { remove: () => void } | null = null;
  private gpsUnsub: { remove: () => void } | null = null;
  private stationaryUnsub: { remove: () => void } | null = null;
  private appStateUnsub: { remove: () => void } | null = null;
  private autoPauseTimer: ReturnType<typeof setTimeout> | null = null;
  private _isPaused: boolean = false;

  constructor(options: ActivityOptions = {}) {
    this.options = { ...DEFAULT_OPTIONS, ...options } as Required<ActivityOptions>;
    this.tracker = new TimeBasedTracker();
    this.gpsController = new SmartGPSController({
      adaptiveInterval: this.options.adaptiveInterval,
      activeIntervalMs: this.options.intervalMs,
      stationaryIntervalMs: this.options.stationaryIntervalMs,
      maxAccuracy: this.options.maxAccuracy,
    });
    this._extras = options.extras ?? {};
  }

  // ─── Public State ─────────────────────────────────────────────────────────

  /** Current activity state */
  get state(): ActivityState {
    return this._state;
  }

  /** Unique session ID (set after start()) */
  get sessionId(): string | null {
    return this._sessionId;
  }

  /** Whether tracking is active (not paused, not stopped) */
  get isTracking(): boolean {
    return this._state === 'tracking';
  }

  /** Whether the activity is paused */
  get isPaused(): boolean {
    return this._isPaused;
  }

  /** Elapsed wall-clock time in ms since start */
  get elapsedMs(): number {
    if (this._state === 'idle') return 0;
    if (this._state === 'completed' || this._state === 'error') return this._elapsedMs;
    return Date.now() - this._startTime;
  }

  /** Active tracking time in ms (excluding pauses) */
  get activeMs(): number {
    if (this._state === 'idle') return 0;
    if (this._isPaused) return this._activeMs;
    return this._activeMs + (Date.now() - this._pauseStartTime);
  }

  /** Total paused duration in ms */
  get pausedMs(): number {
    return this._totalPausedMs;
  }

  /** Total distance in meters */
  get totalDistance(): number {
    return this._totalDistance;
  }

  /** Current GPS strength */
  get gpsStrength(): GpsStrength {
    return this.gpsController.gpsStrength;
  }

  /** Current speed in m/s (null if unknown) */
  get currentSpeed(): number | null {
    return this._currentSpeed;
  }

  /** Get a snapshot of current activity state */
  getSnapshot(): ActivityStateSnapshot {
    return {
      state: this._state,
      sessionId: this._sessionId,
      elapsedMs: this.elapsedMs,
      activeMs: this.activeMs,
      pausedMs: this.pausedMs,
      totalDistance: this._totalDistance,
      currentSpeed: this._currentSpeed,
      averageSpeed: this.activeMs > 0 ? this._totalDistance / (this.activeMs / 1000) : 0,
      gpsStrength: this.gpsController.gpsStrength,
      isStationary: this.gpsController.isStationary,
      batteryLevel: this._batteryLevel,
      pointCount: this._pointCount,
    };
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  /**
   * Start an activity session.
   * - Requests permissions if not granted
   * - Creates a native session in SQLite
   * - Starts time-based GPS tracking
   * - Configures smart auto-pause/resume
   *
   * @param options - Activity configuration (merged with constructor options)
   * @returns The session ID
   */
  async start(options?: ActivityOptions): Promise<string> {
    if (this._state === 'tracking') {
      throw new Error('Activity is already tracking');
    }

    this.setState('preparing');

    // Merge options
    if (options) {
      Object.assign(this.options, options);
      this.gpsController.configure({
        adaptiveInterval: this.options.adaptiveInterval,
        activeIntervalMs: this.options.intervalMs,
        stationaryIntervalMs: this.options.stationaryIntervalMs,
        maxAccuracy: this.options.maxAccuracy,
      });
    }

    // 1. Ensure permissions
    const permResult = await PermissionManager.requestFitnessPermissions({
      includeMotion: this.options.includePedometer,
    });
    if (permResult.status === 'denied') {
      this.setState('error');
      throw new Error('Location permission denied');
    }
    if (permResult.status === 'foreground_only') {
      console.warn('[FitnessGeolocation] Only foreground permission granted — background tracking may be unreliable');
    }

    // 2. Create native session
    const sessionId = await Native.createSession?.(this.options.name ?? 'Workout');
    this._sessionId = sessionId;

    // 3. Reset state
    this._startTime = Date.now();
    this._pauseStartTime = this._startTime;
    this._totalPausedMs = 0;
    this._pauseCount = 0;
    this._activeMs = 0;
    this._elapsedMs = 0;
    this._totalDistance = 0;
    this._currentSpeed = null;
    this._maxSpeed = 0;
    this._totalElevationGain = 0;
    this._lastAltitude = null;
    this._pointCount = 0;
    this._isPaused = false;
    this._uploaded = false;

    // 4. Subscribe to app state changes for foreground sync
    const appStateSub = AppState.addEventListener('change', (state) => {
      if (state === 'active' && this._state === 'tracking') {
        this.drainPendingQueue();
      }
    });
    this.appStateUnsub = appStateSub;

    // 5. Subscribe to GPS strength changes
    this.gpsUnsub = this.tracker.onGpsStrengthChange((strength) => {
      // If GPS drops to 'none', warn but keep trying
      if (strength === 'none' && __DEV__) {
        console.warn('[FitnessGeolocation] GPS signal lost');
      }
    });

    // 6. Subscribe to stationary changes for auto-pause
    this.stationaryUnsub = this.tracker.onStationaryChange((isStationary) => {
      if (isStationary && this.options.autoPause && this._state === 'tracking') {
        this.startAutoPauseTimer();
      } else if (!isStationary) {
        this.cancelAutoPauseTimer();
        if (this._isPaused && this.options.autoResume) {
          this.resume();
        }
      }
    });

    // 7. Subscribe to location ticks
    this.tickUnsub = this.tracker.onTick((location) => {
      this._pointCount++;
      this._currentSpeed = location.coords.speed;
      this._totalDistance = location.cumulativeDistance;
      this._batteryLevel = location.batteryLevel;

      // Track max speed
      if (location.coords.speed != null && location.coords.speed > this._maxSpeed) {
        this._maxSpeed = location.coords.speed;
      }

      // Track elevation gain
      if (location.coords.altitude != null && this._lastAltitude != null) {
        const diff = location.coords.altitude - this._lastAltitude;
        if (diff > 0) this._totalElevationGain += diff;
      }
      this._lastAltitude = location.coords.altitude;

      // Feed GPS controller for adaptive interval
      this.gpsController.feed(
        location.coords.accuracy,
        location.coords.speed,
        location.timestamp,
      );
    });

    // 8. Configure the tracker with adaptive settings
    this.options.intervalMs = this.gpsController.recommendedInterval;

    // 9. Start tracking
    await this.tracker.start({
      intervalMs: this.options.intervalMs,
      adaptiveInterval: this.options.adaptiveInterval,
      stationaryIntervalMs: this.options.stationaryIntervalMs,
      maxAccuracy: this.options.maxAccuracy,
      enableMotion: true,
      includePedometer: this.options.includePedometer,
    });

    this.setState('tracking');
    this._activeMs = Date.now() - this._startTime;

    if (__DEV__) {
      console.log(`[FitnessGeolocation] Activity started: session=${sessionId}, mode=${this.options.trackingMode}`);
      Native.devLog?.('info', 'ActivityManager', 'activity_started', {
        sessionId,
        mode: this.options.trackingMode,
        interval: this.options.intervalMs,
      });
    }

    return sessionId;
  }

  /**
   * Pause the current activity (stops GPS, keeps session alive).
   * Returns false if already paused or no active session.
   */
  pause(options?: { reason?: 'manual' | 'stationary' }): boolean {
    if (this._state !== 'tracking' || this._isPaused) return false;

    // Add the active time since last resume/start
    this._activeMs += Date.now() - this._pauseStartTime;

    this._isPaused = true;
    this._pauseStartTime = Date.now();
    this._pauseCount++;
    this.cancelAutoPauseTimer();

    // Pause the native tracker
    this.tracker.pause();

    // Notify native of pause for session tracking
    Native.setActivityPaused?.(true);

    if (__DEV__) {
      Native.devLog?.('info', 'ActivityManager', 'activity_paused', {
        sessionId: this._sessionId,
        reason: options?.reason ?? 'manual',
        pauseCount: this._pauseCount,
      });
    }

    return true;
  }

  /**
   * Resume the current activity after pause.
   * Returns false if not paused or no active session.
   */
  resume(options?: { reason?: 'manual' | 'movement' }): boolean {
    if (this._state !== 'tracking' || !this._isPaused) return false;

    // Add the paused duration since pause was called
    this._totalPausedMs += Date.now() - this._pauseStartTime;
    this._pauseStartTime = Date.now();
    this._isPaused = false;

    // Resume the native tracker
    this.tracker.resume();
    Native.setActivityPaused?.(false);

    if (__DEV__) {
      Native.devLog?.('info', 'ActivityManager', 'activity_resumed', {
        sessionId: this._sessionId,
        reason: options?.reason ?? 'manual',
      });
    }

    return true;
  }

  /**
   * End the current activity.
   * - Stops GPS tracking
   * - Finalizes the session in SQLite
   * - Returns a summary of the activity
   * - The session data remains in SQLite until syncSessionAll() is called
   */
  async end(): Promise<ActivitySummary> {
    if (this._state === 'idle') {
      throw new Error('No active activity to end');
    }

    if (this._isPaused) {
      this._totalPausedMs += Date.now() - this._pauseStartTime;
    }

    this.setState('ending');

    // Stop tracking
    this.tracker.stop();

    // Calculate final metrics
    this._elapsedMs = Date.now() - this._startTime;
    const correctActiveMs = this._elapsedMs - this._totalPausedMs;

    // Finalize session in native SQLite
    if (this._sessionId) {
      await Native.endSession?.(this._sessionId, {
        totalDistance: this._totalDistance,
        totalDuration: this._elapsedMs,
        totalActiveDuration: correctActiveMs,
        maxSpeed: this._maxSpeed,
        elevationGain: this._totalElevationGain,
        averageAccuracy: this.getAverageAccuracy(),
        pointCount: this._pointCount,
      });
    }

    // Cleanup subscriptions
    this.tickUnsub?.remove();
    this.gpsUnsub?.remove();
    this.stationaryUnsub?.remove();
    this.appStateUnsub?.remove();
    this.appStateUnsub = null;
    this.cancelAutoPauseTimer();

    const averageSpeed = correctActiveMs > 0 ? this._totalDistance / (correctActiveMs / 1000) : 0;

    const summary: ActivitySummary = {
      sessionId: this._sessionId ?? 'unknown',
      name: this.options.name ?? 'Workout',
      activityType: this.options.activityType ?? 'running',
      startTime: this._startTime,
      endTime: Date.now(),
      duration: Math.round(this._elapsedMs / 1000),
      activeDuration: Math.round(correctActiveMs / 1000),
      totalDistance: Math.round(this._totalDistance * 100) / 100,
      totalPausedDuration: Math.round(this._totalPausedMs / 1000),
      pauseCount: this._pauseCount,
      averageSpeed: Math.round(averageSpeed * 100) / 100,
      maxSpeed: Math.round(this._maxSpeed * 100) / 100,
      elevationGain: Math.round(this._totalElevationGain * 100) / 100,
      averageAccuracy: Math.round(this.getAverageAccuracy() * 100) / 100,
      pointCount: this._pointCount,
      uploaded: false,
      extras: this._extras,
    };

    this._state = 'completed';

    if (__DEV__) {
      console.log('[FitnessGeolocation] Activity ended:', summary);
      Native.devLog?.('info', 'ActivityManager', 'activity_ended', {
        sessionId: this._sessionId,
        duration: summary.duration,
        distance: summary.totalDistance,
        points: summary.pointCount,
      });
    }

    return summary;
  }

  /**
   * Discard the current activity without saving.
   * Deletes all collected points from SQLite.
   */
  async discard(): Promise<void> {
    if (this._state === 'idle') return;

    this.tracker.stop();
    this.tickUnsub?.remove();
    this.gpsUnsub?.remove();
    this.stationaryUnsub?.remove();
    this.appStateUnsub?.remove();
    this.cancelAutoPauseTimer();

    if (this._sessionId) {
      await Native.discardSession?.(this._sessionId);
    }

    this._state = 'idle';
    this._sessionId = null;

    if (__DEV__) {
      Native.devLog?.('info', 'ActivityManager', 'activity_discarded', {});
    }
  }

  // ─── Sync ─────────────────────────────────────────────────────────────────

  /**
   * Get all pending (un-uploaded) activity sessions.
   */
  async getPendingActivities(): Promise<ActivitySummary[]> {
    try {
      return await Native.getPendingSessions?.() ?? [];
    } catch {
      return [];
    }
  }

  /**
   * Upload a specific session to the server.
   * Returns true if upload was successful.
   */
  async uploadSession(
    sessionId: string,
    apiUrl: string,
    headers?: Record<string, string>,
  ): Promise<boolean> {
    try {
      const sessionData = await Native.getSessionForUpload?.(sessionId);
      if (!sessionData) return false;

      const response = await fetch(apiUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(headers ?? {}),
        },
        body: JSON.stringify(sessionData),
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      await Native.markSessionUploaded?.(sessionId);
      return true;
    } catch (error) {
      console.warn('[FitnessGeolocation] Upload failed:', error);
      return false;
    }
  }

  /**
   * Upload all pending sessions to the server.
   * Returns the count of successfully uploaded sessions.
   */
  async syncAllPending(apiUrl: string, headers?: Record<string, string>): Promise<number> {
    const sessions = await this.getPendingActivities();
    let successCount = 0;

    for (const session of sessions) {
      const ok = await this.uploadSession(session.sessionId, apiUrl, headers);
      if (ok) successCount++;
    }

    return successCount;
  }

  // ─── Events ───────────────────────────────────────────────────────────────

  /** Subscribe to activity state changes */
  onStateChange(callback: StateChangeCallback): LocationSubscription {
    this.stateChangeListeners.add(callback);
    return { remove: () => this.stateChangeListeners.delete(callback) };
  }

  /** Subscribe to activity errors */
  onError(callback: ActivityErrorCallback): LocationSubscription {
    this.errorListeners.add(callback);
    return { remove: () => this.errorListeners.delete(callback) };
  }

  /** Subscribe to location ticks during activity */
  onTick(callback: (location: import('./types').TimeBasedLocation) => void): LocationSubscription {
    return this.tracker.onTick(callback);
  }

  /** Subscribe to GPS strength changes */
  onGpsStrengthChange(callback: (strength: GpsStrength) => void): LocationSubscription {
    return this.tracker.onGpsStrengthChange(callback);
  }

  /** Subscribe to stationary/moving state changes (for auto-pause feedback) */
  onStationaryChange(callback: (isStationary: boolean) => void): LocationSubscription {
    return this.tracker.onStationaryChange(callback);
  }

  // ─── Private ──────────────────────────────────────────────────────────────

  private setState(state: ActivityState): void {
    this._state = state;
    for (const cb of this.stateChangeListeners) {
      try { cb(state); } catch {}
    }
  }

  private startAutoPauseTimer(): void {
    if (this.autoPauseTimer) return;
    this.autoPauseTimer = setTimeout(() => {
      if (!this._isPaused && this._state === 'tracking' && this.options.autoPause) {
        this.pause({ reason: 'stationary' });
      }
      this.autoPauseTimer = null;
    }, (this.options.autoPauseDelaySeconds ?? 45) * 1000);
  }

  private cancelAutoPauseTimer(): void {
    if (this.autoPauseTimer) {
      clearTimeout(this.autoPauseTimer);
      this.autoPauseTimer = null;
    }
  }

  private drainPendingQueue(): void {
    // Called when app returns to foreground
    // Drains any points collected while backgrounded
    if (this._sessionId) {
      Native.syncPendingLocations?.();
    }
  }

  private getAverageAccuracy(): number {
    // This would ideally track running average
    // For now return a reasonable default
    return 15;
  }
}

/**
 * Create a new ActivityManager instance with the given options.
 */
export function createActivityManager(options?: ActivityOptions): ActivityManager {
  return new ActivityManager(options);
}

export default ActivityManager;
