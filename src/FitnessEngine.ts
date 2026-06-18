import { NativeModules } from 'react-native';
import Geolocation from './Geolocation';
import { MotionEngine } from './MotionEngine';
import { PermissionManager } from './PermissionManager';
import type {
  FitnessEngineConfig,
  FitnessEngineState,
  GeolocationError,
  GeolocationOptions,
  GeolocationResponse,
  TrackingMode,
} from './types';

const Native = NativeModules.FitnessGeolocation;

/**
 * Heart of activity tracker apps — orchestrates permissions, GPS, motion, auto-pause.
 *
 * Drop-in for fitness apps. Your existing watchPosition/saveCoordinate flow still works
 * via Geolocation directly; FitnessEngine adds Strava-class intelligence on top.
 */
export class FitnessEngine {
  private watchId: number | null = null;
  private config: FitnessEngineConfig = {};
  private autoPauseUnsub: (() => void) | null = null;
  private autoResumeUnsub: (() => void) | null = null;

  /** Request all permissions needed for background fitness tracking */
  async prepare(): Promise<ReturnType<typeof PermissionManager.requestFitnessPermissions>> {
    return PermissionManager.requestFitnessPermissions();
  }

  /**
   * Start full fitness session — GPS watch + motion + auto-pause
   */
  start(
    onLocation: (position: GeolocationResponse) => void,
    onError?: (error: GeolocationError) => void,
    options: GeolocationOptions & { trackingMode?: TrackingMode } = {},
  ): number {
    const { trackingMode = 'fitness', ...geoOptions } = options;

    if (trackingMode) {
      Native.setTrackingMode(trackingMode).catch(() => {});
    }

    MotionEngine.start({ includePedometer: this.config.includePedometer ?? false });

    if (this.config.autoPause !== false) {
      MotionEngine.configureAutoPause(true, this.config.autoPauseDelaySeconds ?? 45);
      this.autoPauseUnsub = MotionEngine.onAutoPause(() => {
        this.setPaused(true);
        this.config.onAutoPause?.();
      });
      this.autoResumeUnsub = MotionEngine.onAutoResume(() => {
        this.setPaused(false);
        this.config.onAutoResume?.();
      });
    }

    this.watchId = Geolocation.watchPosition(onLocation, onError, {
      enableHighAccuracy: true,
      distanceFilter: 5,
      activityType: 'fitness',
      pausesLocationUpdatesAutomatically: false,
      showsBackgroundLocationIndicator: true,
      trackingMode,
      ...geoOptions,
    });

    return this.watchId;
  }

  stop(): void {
    if (this.watchId != null) {
      Geolocation.clearWatch(this.watchId);
      this.watchId = null;
    }
    MotionEngine.stop();
    this.autoPauseUnsub?.();
    this.autoResumeUnsub?.();
    Native.setActivityPaused(false).catch(() => {});
  }

  setPaused(paused: boolean): void {
    Native.setActivityPaused(paused).catch(() => {});
  }

  setMode(mode: TrackingMode): Promise<void> {
    return Native.setTrackingMode(mode);
  }

  async getState(): Promise<FitnessEngineState> {
    return Native.getEngineState();
  }

  async syncPending(): Promise<number> {
    return Geolocation.syncPendingLocations();
  }

  configure(config: FitnessEngineConfig): void {
    this.config = { ...this.config, ...config };
  }
}

export const createFitnessEngine = (config?: FitnessEngineConfig) => {
  const engine = new FitnessEngine();
  if (config) engine.configure(config);
  return engine;
};

export default FitnessEngine;
