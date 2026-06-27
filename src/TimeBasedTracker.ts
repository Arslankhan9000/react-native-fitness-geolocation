import { NativeEventEmitter, Platform } from 'react-native';
import type {
  TimeBasedLocation,
  TimeBasedOptions,
  GpsStrength,
  MotionActivityType,
  LocationSubscription,
} from './types';
import { getFitnessGeolocationNative } from './native/getNativeModule';

const Native = getFitnessGeolocationNative();

const emitter = new NativeEventEmitter(Native);

type TickCallback = (location: TimeBasedLocation) => void;
type GpsStrengthCallback = (strength: GpsStrength) => void;
type StationaryChangeCallback = (isStationary: boolean) => void;

/**
 * Time-based location tracker — polls GPS at a fixed interval (default 3s)
 * regardless of distance traveled. Designed for fitness route recording.
 *
 * Unlike watchPosition (which fires when distanceFilter is exceeded),
 * TimeBasedTracker gives you a point every N seconds — perfect for
 * drawing smooth route lines and calculating accurate pacing.
 */
export class TimeBasedTracker {
  private watchId: number | null = null;
  private intervalMs: number = 3000;
  private stationaryIntervalMs: number = 30000;
  private adaptiveInterval: boolean = true;
  private maxAccuracy: number = 50;
  private isPaused: boolean = false;
  private _isStationary: boolean = false;
  private _gpsStrength: GpsStrength = 'medium';
  private _cumulativeDistance: number = 0;
  private _lastLocation: TimeBasedLocation | null = null;

  private tickSub: { remove: () => void } | null = null;
  private tickListeners = new Set<TickCallback>();
  private gpsStrengthListeners = new Set<GpsStrengthCallback>();
  private stationaryListeners = new Set<StationaryChangeCallback>();

  /** Whether the tracker is currently active */
  get isTracking(): boolean {
    return this.watchId != null;
  }

  /** Current GPS signal strength */
  get gpsStrength(): GpsStrength {
    return this._gpsStrength;
  }

  /** Whether the device is currently estimated as stationary */
  get isStationary(): boolean {
    return this._isStationary;
  }

  /** Cumulative distance tracked in meters */
  get cumulativeDistance(): number {
    return this._cumulativeDistance;
  }

  /** Current tracking interval in ms */
  get interval(): number {
    return this.intervalMs;
  }

  /**
   * Start time-based location tracking.
   * Returns a promise that resolves when the first valid fix is obtained.
   */
  async start(options: TimeBasedOptions = {}): Promise<void> {
    if (this.watchId != null) {
      console.warn('[FitnessGeolocation] TimeBasedTracker already running');
      return;
    }

    this.intervalMs = options.intervalMs ?? 3000;
    this.stationaryIntervalMs = options.stationaryIntervalMs ?? 30000;
    this.adaptiveInterval = options.adaptiveInterval ?? true;
    this.maxAccuracy = options.maxAccuracy ?? 50;
    this._cumulativeDistance = 0;
    this._lastLocation = null;

    // Subscribe to native tick events
    this.tickSub = emitter.addListener('timeBasedTick', (event: Record<string, unknown>) => {
      const location = this.parseLocation(event);
      if (location == null) return;

      // Update GPS strength
      this._gpsStrength = location.gpsStrength;

      // Update stationary state
      const wasStationary = this._isStationary;
      this._isStationary = location.isStationary;

      // Fire stationary change if state changed
      if (wasStationary !== this._isStationary) {
        for (const cb of this.stationaryListeners) {
          try { cb(this._isStationary); } catch {}
        }
      }

      // Update cumulative distance
      this._cumulativeDistance = location.cumulativeDistance;

      // Fire tick callbacks
      for (const cb of this.tickListeners) {
        try { cb(location); } catch {}
      }

      // Fire GPS strength callbacks
      for (const cb of this.gpsStrengthListeners) {
        try { cb(this._gpsStrength); } catch {}
      }

      this._lastLocation = location;
    });

    // Start native time-based tracking
    this.watchId = Native.startTimeBasedTracking({
      intervalMs: this.intervalMs,
      stationaryIntervalMs: this.stationaryIntervalMs,
      adaptiveInterval: this.adaptiveInterval,
      maxAccuracy: this.maxAccuracy,
      enableMotion: options.enableMotion ?? true,
      includePedometer: options.includePedometer ?? false,
    });

    // Log in DEV
    if (__DEV__) {
      console.log(`[FitnessGeolocation] TimeBasedTracker started: interval=${this.intervalMs}ms, adaptive=${this.adaptiveInterval}`);
      Native.devLog?.('debug', 'TimeBasedTracker', 'started', {
        intervalMs: this.intervalMs,
        adaptiveInterval: this.adaptiveInterval,
        maxAccuracy: this.maxAccuracy,
      });
    }
  }

  /** Stop time-based tracking */
  stop(): void {
    if (this.watchId == null) return;

    Native.stopTimeBasedTracking(this.watchId);
    this.tickSub?.remove();
    this.tickSub = null;
    this.watchId = null;
    this._cumulativeDistance = 0;
    this._lastLocation = null;

    if (__DEV__) {
      console.log('[FitnessGeolocation] TimeBasedTracker stopped');
      Native.devLog?.('debug', 'TimeBasedTracker', 'stopped', {});
    }
  }

  /** Pause location updates (keeps session alive, stops GPS) */
  pause(): void {
    if (this.isPaused || this.watchId == null) return;
    this.isPaused = true;
    Native.pauseTimeBasedTracking(this.watchId);

    if (__DEV__) {
      Native.devLog?.('debug', 'TimeBasedTracker', 'paused', {});
    }
  }

  /** Resume location updates after pause */
  resume(): void {
    if (!this.isPaused || this.watchId == null) return;
    this.isPaused = false;
    Native.resumeTimeBasedTracking(this.watchId);

    if (__DEV__) {
      Native.devLog?.('debug', 'TimeBasedTracker', 'resumed', {});
    }
  }

  /** Change the tracking interval dynamically */
  setInterval(ms: number): void {
    this.intervalMs = Math.max(500, ms);
    if (this.watchId != null) {
      Native.setTimeBasedInterval(this.watchId, this.intervalMs);
    }
  }

  /** Subscribe to location tick events */
  onTick(callback: TickCallback): LocationSubscription {
    this.tickListeners.add(callback);
    return { remove: () => this.tickListeners.delete(callback) };
  }

  /** Subscribe to GPS strength changes */
  onGpsStrengthChange(callback: GpsStrengthCallback): LocationSubscription {
    this.gpsStrengthListeners.add(callback);
    return { remove: () => this.gpsStrengthListeners.delete(callback) };
  }

  /** Subscribe to stationary/moving state changes */
  onStationaryChange(callback: StationaryChangeCallback): LocationSubscription {
    this.stationaryListeners.add(callback);
    return { remove: () => this.stationaryListeners.delete(callback) };
  }

  /** Get the last known location */
  getLastLocation(): TimeBasedLocation | null {
    return this._lastLocation;
  }

  /** Reset cumulative distance to 0 */
  resetDistance(): void {
    this._cumulativeDistance = 0;
  }

  private parseLocation(event: Record<string, unknown>): TimeBasedLocation | null {
    const coords = event.coords as Record<string, unknown> | undefined;
    if (!coords) return null;

    const lat = Number(coords.latitude);
    const lng = Number(coords.longitude);
    const accuracy = Number(coords.accuracy ?? 999);

    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    if (lat === 0 && lng === 0) return null;
    if (accuracy <= 0 || accuracy > this.maxAccuracy) return null;

    let quality: any = undefined;
    const rawQuality = event.quality;
    if (typeof rawQuality === 'string') {
      try { quality = JSON.parse(rawQuality); } catch {}
    } else if (rawQuality && typeof rawQuality === 'object') {
      quality = rawQuality;
    }

    return {
      coords: {
        latitude: lat,
        longitude: lng,
        altitude: coords.altitude != null ? Number(coords.altitude) : null,
        accuracy,
        altitudeAccuracy: null,
        heading: coords.heading != null ? Number(coords.heading) : null,
        speed: coords.speed != null ? Number(coords.speed) : null,
      },
      timestamp: Number(event.timestamp ?? Date.now()),
      gpsStrength: (event.gpsStrength as GpsStrength) ?? 'medium',
      isStationary: Boolean(event.isStationary),
      distanceFromPrev: Number(event.distanceFromPrev ?? 0),
      cumulativeDistance: Number(event.cumulativeDistance ?? 0),
      batteryLevel: Number(event.batteryLevel ?? -1),
      motionState: (event.motionState as MotionActivityType) ?? 'unknown',
      quality,
    };
  }
}

/** Singleton instance for easy import */
export const timeBasedTracker = new TimeBasedTracker();

export default TimeBasedTracker;
