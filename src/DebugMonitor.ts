import { NativeEventEmitter, Platform } from 'react-native';
import type {
  DebugMonitorConfig,
  DebugMotionState,
  DebugLifecycleEvent,
  DebugLifecycleSound,
  LocationSubscription,
} from './types';
import { getFitnessGeolocationNative } from './native/getNativeModule';

const Native = getFitnessGeolocationNative();
const emitter = new NativeEventEmitter(Native);
const TAG = 'FitnessGeoDebug';

type MotionStateCallback = (state: DebugMotionState) => void;
type HeartbeatCallback = (event: DebugLifecycleEvent) => void;
type EnabledChangeCallback = (enabled: boolean) => void;
type LifecycleCallback = (event: DebugLifecycleEvent) => void;

const SOUND_LABELS: Record<DebugLifecycleSound, string> = {
  motionchange_true: 'Started moving',
  motionchange_false: 'Stopped — now stationary',
  location_recorded: 'Location recorded',
  location_error: 'Location error',
  heartbeat: 'Heartbeat',
  geofence_enter: 'Geofence entered',
  geofence_exit: 'Geofence exited',
  stop_timeout_start: 'Stop timeout started — device still',
  stop_timeout_cancel: 'Stop timeout cancelled — device moved',
  stop_detection_delay: 'Stop detection delay',
};

/**
 * Debug Monitor — provides development-time feedback about what the
 * tracking engine is doing. Mirrors transistorsoft's debug mode.
 *
 * Features:
 * - Sound effects for lifecycle events (motion change, location, geofence, etc.)
 * - Dynamic Android notification text based on activity state
 * - Motion state machine with stopTimeout (moving ↔ stationary)
 * - Periodic heartbeat events
 * - onEnabledChange events
 * - Lifecycle event log for debugging
 */
export class DebugMonitor {
  private _enabled = false;
  private _sound = true;
  private motionStateListeners = new Set<MotionStateCallback>();
  private heartbeatListeners = new Set<HeartbeatCallback>();
  private enabledChangeListeners = new Set<EnabledChangeCallback>();
  private lifecycleListeners = new Set<LifecycleCallback>();
  private subs: { remove: () => void }[] = [];

  get enabled(): boolean {
    return this._enabled;
  }

  /**
   * Configure and enable debug mode.
   * Call with your config to turn on debug features.
   */
  async configure(config: DebugMonitorConfig = {}): Promise<void> {
    const merged: DebugMonitorConfig = {
      debug: true,
      sound: config.sound ?? true,
      vibration: config.vibration ?? (Platform.OS === 'android'),
      feedbackThrottleMs: config.feedbackThrottleMs ?? 1500,
      notificationDebounceMs: config.notificationDebounceMs ?? 1200,
      stopTimeout: config.stopTimeout ?? 5,
      heartbeatInterval: config.heartbeatInterval ?? 60,
      stopAfterElapsedMinutes: config.stopAfterElapsedMinutes ?? 0,
      notificationTitle: config.notificationTitle ?? 'Tracking activity',
      notificationTextStationary: config.notificationTextStationary ?? 'Stationary',
      notificationTextWalking: config.notificationTextWalking ?? 'Walking',
      notificationTextRunning: config.notificationTextRunning ?? 'Running',
      notificationTextCycling: config.notificationTextCycling ?? 'Cycling',
      notificationTextDriving: config.notificationTextDriving ?? 'Driving',
      notificationTextMoving: config.notificationTextMoving ?? 'Moving',
      ...config,
    };

    this._sound = merged.sound ?? true;

    // Send config to native
    try {
      await Native.setDebugMonitorConfig?.({
        enabled: merged.debug,
        sound: merged.sound,
        vibration: merged.vibration,
        feedbackThrottleMs: merged.feedbackThrottleMs,
        notificationDebounceMs: merged.notificationDebounceMs,
        stopTimeoutMinutes: merged.stopTimeout,
        heartbeatIntervalSeconds: merged.heartbeatInterval,
        stopAfterElapsedMinutes: merged.stopAfterElapsedMinutes,
        notificationTitle: merged.notificationTitle,
        notificationTextStationary: merged.notificationTextStationary,
        notificationTextWalking: merged.notificationTextWalking,
        notificationTextRunning: merged.notificationTextRunning,
        notificationTextCycling: merged.notificationTextCycling,
        notificationTextDriving: merged.notificationTextDriving,
        notificationTextMoving: merged.notificationTextMoving,
      });
    } catch (error) {
      console.warn(`[${TAG}] Failed to configure:`, error);
      return;
    }

    this._enabled = true;
    this.subscribeToEvents();

    if (__DEV__) {
      console.log(`[${TAG}] Debug mode enabled: sound=${merged.sound}, stopTimeout=${merged.stopTimeout}min, heartbeat=${merged.heartbeatInterval}s`);
    }
  }

  /**
   * Disable debug mode and clean up.
   */
  async disable(): Promise<void> {
    try {
      await Native.setDebugMonitorConfig?.({ enabled: false });
    } catch {}
    this._enabled = false;
    this.unsubscribeFromEvents();
  }

  /**
   * Get the current motion state from the native state machine.
   */
  async getMotionState(): Promise<DebugMotionState | null> {
    try {
      return await Native.getDebugMotionState?.() ?? null;
    } catch {
      return null;
    }
  }

  /**
   * Subscribe to motion state changes (moving ↔ stationary).
   */
  onMotionStateChange(callback: MotionStateCallback): LocationSubscription {
    this.motionStateListeners.add(callback);
    return { remove: () => this.motionStateListeners.delete(callback) };
  }

  /**
   * Subscribe to periodic heartbeat events.
   */
  onHeartbeat(callback: HeartbeatCallback): LocationSubscription {
    this.heartbeatListeners.add(callback);
    return { remove: () => this.heartbeatListeners.delete(callback) };
  }

  /**
   * Subscribe to enabled state changes (tracking start/stop).
   */
  onEnabledChange(callback: EnabledChangeCallback): LocationSubscription {
    this.enabledChangeListeners.add(callback);
    return { remove: () => this.enabledChangeListeners.delete(callback) };
  }

  /**
   * Subscribe to all debug lifecycle events (for logging).
   */
  onLifecycleEvent(callback: LifecycleCallback): LocationSubscription {
    this.lifecycleListeners.add(callback);
    return { remove: () => this.lifecycleListeners.delete(callback) };
  }

  /**
   * Get human-readable label for a sound event.
   */
  getSoundLabel(sound: DebugLifecycleSound): string {
    return SOUND_LABELS[sound] ?? sound;
  }

  private subscribeToEvents(): void {
    this.unsubscribeFromEvents();

    this.subs.push(
      emitter.addListener('debugMotionState', (event: DebugMotionState) => {
        for (const cb of this.motionStateListeners) {
          try { cb(event); } catch {}
        }
      }),
    );

    this.subs.push(
      emitter.addListener('debugHeartbeat', (event: DebugLifecycleEvent) => {
        for (const cb of this.heartbeatListeners) {
          try { cb(event); } catch {}
        }
      }),
    );

    this.subs.push(
      emitter.addListener('debugEnabledChange', (event: { enabled: boolean }) => {
        for (const cb of this.enabledChangeListeners) {
          try { cb(event.enabled); } catch {}
        }
      }),
    );

    this.subs.push(
      emitter.addListener('debugLifecycle', (event: DebugLifecycleEvent) => {
        if (__DEV__) {
          const prefix = event.event === 'sound' ? '🔊' : '📋';
          console.log(`[${TAG}] ${prefix} ${event.message}`);
        }
        for (const cb of this.lifecycleListeners) {
          try { cb(event); } catch {}
        }
      }),
    );
  }

  private unsubscribeFromEvents(): void {
    this.subs.forEach(s => s.remove());
    this.subs = [];
  }
}

/** Singleton instance */
export const debugMonitor = new DebugMonitor();
export default DebugMonitor;
