/**
 * FitnessTrackingService — unified high-level API for fitness GPS apps.
 *
 * Solves common gaps in @react-native-community/geolocation and basic wrappers:
 * - Permission flow (foreground + background + motion)
 * - Native SQLite background queue + foreground drain
 * - Auto pause/resume via motion
 * - Session lifecycle with crash-safe native storage
 * - iOS: native location background (no 30s UIBackgroundTask trap)
 * - Engine diagnostics and queue sync
 *
 * For Transistorsoft-parity (HTTP sync, geofences, headless), use HttpSync / Geofencing directly.
 */
import { AppState, Platform, type AppStateStatus } from 'react-native';
import Geolocation from './Geolocation';
import { PermissionManager } from './PermissionManager';
import { ActivityManager, createActivityManager } from './ActivityManager';
import type {
  ActivityOptions,
  ActivityState,
  ActivityStateSnapshot,
  ActivitySummary,
  FitnessPermissionResult,
  GeolocationResponse,
  TimeBasedLocation,
} from './types';

export interface FitnessTrackingReadyConfig extends ActivityOptions {
  /** Request motion permission on Android (activity recognition) */
  includeMotion?: boolean;
  /** Skip permission prompts (e.g. already granted) */
  skipPermissionRequests?: boolean;
}

export interface FitnessTrackingStartOptions extends ActivityOptions {
  onLocation?: (position: GeolocationResponse) => void;
  onStateChange?: (state: ActivityState) => void;
  onError?: (error: Error) => void;
}

export interface FitnessTrackingServiceState {
  ready: boolean;
  permission: FitnessPermissionResult | null;
  activity: ActivityStateSnapshot | null;
  queueSize: number;
  engineState: Record<string, unknown> | null;
}

type Listener = (state: FitnessTrackingServiceState) => void;

let activity: ActivityManager | null = null;
let tickUnsub: { remove: () => void } | null = null;
let readyConfig: FitnessTrackingReadyConfig | null = null;
let permissionResult: FitnessPermissionResult | null = null;
let queueSize = 0;
let engineState: Record<string, unknown> | null = null;
let locationHandler: ((position: GeolocationResponse) => void) | null = null;
const listeners = new Set<Listener>();
let appStateSub: { remove: () => void } | null = null;

function timeBasedToGeolocation(loc: TimeBasedLocation): GeolocationResponse {
  return {
    coords: {
      latitude: loc.coords.latitude,
      longitude: loc.coords.longitude,
      altitude: loc.coords.altitude,
      accuracy: loc.coords.accuracy,
      altitudeAccuracy: loc.coords.altitudeAccuracy ?? null,
      heading: loc.coords.heading ?? null,
      speed: loc.coords.speed ?? null,
    },
    timestamp: loc.timestamp,
  };
}

function buildState(): FitnessTrackingServiceState {
  return {
    ready: permissionResult?.status === 'ready',
    permission: permissionResult,
    activity: activity?.getSnapshot() ?? null,
    queueSize,
    engineState,
  };
}

function emit() {
  const snap = buildState();
  listeners.forEach(fn => {
    try {
      fn(snap);
    } catch {
      /* ignore */
    }
  });
}

async function refreshMeta(): Promise<void> {
  try {
    const [q, engine] = await Promise.all([
      Geolocation.getQueueSize(),
      Geolocation.getEngineState(),
    ]);
    queueSize = q;
    engineState = engine as Record<string, unknown>;
  } catch {
    /* ignore */
  }
  emit();
}

function ensureAppStateListener(): void {
  appStateSub?.remove();
  appStateSub = AppState.addEventListener('change', (next: AppStateStatus) => {
    if (next === 'active') {
      Geolocation.syncPendingLocations()
        .catch(() => {})
        .finally(() => refreshMeta());
    }
  });
}

export const FitnessTrackingService = {
  /**
   * Configure + request permissions (call once at app launch or before first activity).
   * Mirrors BackgroundGeolocation.ready() intent without commercial SDK lock-in.
   */
  async ready(config: FitnessTrackingReadyConfig = {}): Promise<FitnessTrackingServiceState> {
    readyConfig = config;
    ensureAppStateListener();

    if (!config.skipPermissionRequests) {
      permissionResult = await PermissionManager.requestFitnessPermissions({
        includeMotion: config.includeMotion ?? Platform.OS === 'android',
      });
    } else {
      const auth = await Geolocation.getAuthorizationStatus();
      permissionResult = {
        foregroundGranted: auth.status === 'granted',
        backgroundGranted: auth.always === true,
        motionGranted: true,
        notificationsGranted: true,
        status: auth.always ? 'ready' : 'foreground_only',
      };
    }

    Geolocation.setRNConfiguration({
      authorizationLevel: 'always',
      skipPermissionRequests: config.skipPermissionRequests,
    });

    await refreshMeta();
    return buildState();
  },

  subscribe(listener: Listener): () => void {
    listeners.add(listener);
    listener(buildState());
    return () => listeners.delete(listener);
  },

  getState(): FitnessTrackingServiceState {
    return buildState();
  },

  async start(options: FitnessTrackingStartOptions = {}): Promise<string> {
    if (permissionResult?.status !== 'ready') {
      const afterReady = await this.ready(readyConfig ?? {});
      if (!afterReady.ready) {
        throw new Error(
          afterReady.permission?.message ??
            'Background location (Always Allow) is required for locked-screen tracking.',
        );
      }
    }

    tickUnsub?.remove();
    locationHandler = options.onLocation ?? null;

    activity = createActivityManager({ ...readyConfig, ...options });

    if (options.onStateChange) {
      activity.onStateChange(options.onStateChange);
    }
    if (options.onError) {
      activity.onError(options.onError);
    }

    if (locationHandler) {
      tickUnsub = activity.onTick(loc => {
        locationHandler?.(timeBasedToGeolocation(loc));
        emit();
      });
    }

    const sessionId = await activity.start(options);
    await refreshMeta();
    return sessionId;
  },

  async pause(reason: 'stationary' | 'manual' = 'manual'): Promise<void> {
    if (!activity) return;
    await activity.pause({ reason });
    await refreshMeta();
  },

  async resume(): Promise<void> {
    if (!activity) return;
    await activity.resume();
    await refreshMeta();
  },

  async stop(): Promise<ActivitySummary | null> {
    tickUnsub?.remove();
    tickUnsub = null;
    if (!activity) return null;
    const summary = await activity.end();
    activity = null;
    locationHandler = null;
    await refreshMeta();
    return summary;
  },

  async discard(): Promise<void> {
    tickUnsub?.remove();
    tickUnsub = null;
    if (!activity) return;
    await activity.discard();
    activity = null;
    locationHandler = null;
    await refreshMeta();
  },

  async syncQueue(): Promise<number> {
    const n = await Geolocation.syncPendingLocations();
    await refreshMeta();
    return n;
  },

  openSettings(): Promise<void> {
    return PermissionManager.openSettings();
  },

  getActivity(): ActivityManager | null {
    return activity;
  },
};

export default FitnessTrackingService;
