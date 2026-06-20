import { NativeModules } from 'react-native';
import type { GpsStrength, GpsStrengthEvent, SmartGPSConfig } from './types';

const Native = NativeModules.FitnessGeolocation;

type GpsStrengthCallback = (event: GpsStrengthEvent) => void;

/**
 * Smart GPS Controller — adaptive accuracy management for battery efficiency.
 *
 * Core idea: don't use maximum GPS accuracy when you don't need it.
 * - Walking slowly → medium accuracy, longer interval
 * - Running → high accuracy, short interval
 * - Stationary → minimum accuracy, very long interval (or pause GPS)
 * - Weak GPS signal → reduce polling frequency to save battery
 *
 * Uses motion detection + GPS accuracy heuristics to dynamically
 * adjust the tracking profile.
 */
export class SmartGPSController {
  private config: Required<SmartGPSConfig>;
  private _currentStrength: GpsStrength = 'medium';
  private _isStationary: boolean = false;
  private _lastSpeed: number = 0;
  private _lastAccuracy: number = 999;
  private _stationaryStartTime: number = 0;
  private _currentIntervalMs: number;
  private strengthListeners = new Set<GpsStrengthCallback>();

  constructor(config: SmartGPSConfig = {}) {
    this.config = {
      adaptiveInterval: config.adaptiveInterval ?? true,
      activeIntervalMs: config.activeIntervalMs ?? 3000,
      stationaryIntervalMs: config.stationaryIntervalMs ?? 30000,
      weakSignalIntervalMs: config.weakSignalIntervalMs ?? 10000,
      stationarySpeedThreshold: config.stationarySpeedThreshold ?? 0.5,
      stationaryDelayMs: config.stationaryDelayMs ?? 10000,
      maxAccuracy: config.maxAccuracy ?? 50,
      strongAccuracyThreshold: config.strongAccuracyThreshold ?? 10,
      mediumAccuracyThreshold: config.mediumAccuracyThreshold ?? 30,
    };
    this._currentIntervalMs = this.config.activeIntervalMs;
  }

  /** Current GPS signal strength assessment */
  get gpsStrength(): GpsStrength {
    return this._currentStrength;
  }

  /** Whether the device is estimated as stationary */
  get isStationary(): boolean {
    return this._isStationary;
  }

  /** Current recommended polling interval based on conditions */
  get recommendedInterval(): number {
    return this._currentIntervalMs;
  }

  /**
   * Feed a new location sample to the controller.
   * Returns the recommended tracking interval for the next sample.
   */
  feed(accuracy: number, speed: number | null, timestamp: number): number {
    if (!this.config.adaptiveInterval) return this.config.activeIntervalMs;

    this._lastAccuracy = accuracy;
    this._lastSpeed = speed ?? 0;

    // 1. Assess GPS strength
    this._currentStrength = this.assessStrength(accuracy);

    // 2. Assess stationary state
    const wasStationary = this._isStationary;
    if (this._lastSpeed < this.config.stationarySpeedThreshold) {
      if (this._stationaryStartTime === 0) {
        this._stationaryStartTime = timestamp;
      }
      this._isStationary = (timestamp - this._stationaryStartTime) >= this.config.stationaryDelayMs;
    } else {
      this._stationaryStartTime = 0;
      this._isStationary = false;
    }

    // 3. Compute optimal interval
    if (this._isStationary) {
      this._currentIntervalMs = this.config.stationaryIntervalMs;
    } else if (this._currentStrength === 'weak' || this._currentStrength === 'none') {
      this._currentIntervalMs = this.config.weakSignalIntervalMs;
    } else if (this._currentStrength === 'strong') {
      this._currentIntervalMs = this.config.activeIntervalMs;
    } else {
      // medium — use a moderate interval
      this._currentIntervalMs = Math.min(
        this.config.activeIntervalMs * 2,
        this.config.stationaryIntervalMs,
      );
    }

    // Fire strength event if changed
    const event: GpsStrengthEvent = {
      strength: this._currentStrength,
      accuracy,
      timestamp,
    };
    for (const cb of this.strengthListeners) {
      try { cb(event); } catch {}
    }

    return this._currentIntervalMs;
  }

  /** Reset stationary detection state */
  reset(): void {
    this._stationaryStartTime = 0;
    this._isStationary = false;
    this._currentIntervalMs = this.config.activeIntervalMs;
  }

  /** Update configuration at runtime */
  configure(config: Partial<SmartGPSConfig>): void {
    Object.assign(this.config, config);
  }

  /**
   * Assess GPS signal quality based on horizontal accuracy.
   * Uses same thresholds as the native filter.
   */
  assessStrength(accuracy: number): GpsStrength {
    if (accuracy <= 0 || accuracy > this.config.maxAccuracy) return 'none';
    if (accuracy <= this.config.strongAccuracyThreshold) return 'strong';
    if (accuracy <= this.config.mediumAccuracyThreshold) return 'medium';
    return 'weak';
  }

  /**
   * Check if GPS signal is good enough for quality tracking.
   * When false, the tracker may want to:
   * - Reduce polling frequency
   * - Show a warning to the user
   * - Use cached positions
   */
  isGpsUsable(): boolean {
    return this._currentStrength !== 'none';
  }

  /**
   * Whether we should skip this GPS sample (too inaccurate).
   * Use this in the tick callback to decide whether to record the point.
   */
  shouldSkipSample(accuracy: number): boolean {
    return accuracy <= 0 || accuracy > this.config.maxAccuracy;
  }

  /** Subscribe to GPS strength change events */
  onGpsStrengthChange(callback: GpsStrengthCallback): () => void {
    this.strengthListeners.add(callback);
    return () => this.strengthListeners.delete(callback);
  }
}

/** Singleton instance */
export const smartGPSController = new SmartGPSController();

export default SmartGPSController;
