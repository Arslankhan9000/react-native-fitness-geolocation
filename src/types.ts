/** Compatible with @react-native-community/geolocation types */

export const PositionError = {
  PERMISSION_DENIED: 1,
  POSITION_UNAVAILABLE: 2,
  TIMEOUT: 3,
} as const;

export interface GeolocationResponse {
  coords: {
    latitude: number;
    longitude: number;
    altitude: number | null;
    accuracy: number;
    altitudeAccuracy: number | null;
    heading: number | null;
    speed: number | null;
  };
  timestamp: number;
}

export interface GeolocationError {
  code: number;
  message: string;
  PERMISSION_DENIED: number;
  POSITION_UNAVAILABLE: number;
  TIMEOUT: number;
}

export interface GeolocationOptions {
  /** Milliseconds before failing with TIMEOUT (default: 15000) */
  timeout?: number;
  /** Accept cached position if younger than this (ms). Default: 0 = always fresh */
  maximumAge?: number;
  enableHighAccuracy?: boolean;
  /** Desired native accuracy in meters where supported. Lower is stricter. */
  desiredAccuracy?: number;
  distanceFilter?: number;
  activityType?: 'fitness' | 'automotiveNavigation' | 'otherNavigation' | 'other';
  pausesLocationUpdatesAutomatically?: boolean;
  showsBackgroundLocationIndicator?: boolean;
  useSignificantChanges?: boolean;
  deferredUpdatesDistance?: number;
  deferredUpdatesTimeout?: number;
  /** Android — desired interval between updates (ms). Default: 3000 */
  interval?: number;
  /** Alias used by background-geolocation style configs. Android only. */
  locationUpdateInterval?: number;
  /** Android — fastest interval between updates (ms). Default: 1000 */
  fastestInterval?: number;
  /** Alias used by background-geolocation style configs. Android only. */
  fastestLocationUpdateInterval?: number;
  /**
   * iOS note: CoreLocation is distance/accuracy driven, not timer driven.
   * Use distanceFilter: 0 with high accuracy for the densest workout route.
   */
  forceRequestLocation?: boolean;
  /** Adaptive sampling preset (fitness apps) */
  trackingMode?: TrackingMode;
  /** Start MotionEngine with this watch (fitness auto-pause). Default: false */
  enableMotion?: boolean;
  /** Request pedometer when enableMotion is true. Default: false */
  includePedometer?: boolean;
}

export interface GeolocationConfiguration {
  skipPermissionRequests?: boolean;
  authorizationLevel?: 'always' | 'whenInUse';
  locationProvider?: 'auto' | 'android' | 'playServices';
  enableBackgroundLocationUpdates?: boolean;
}

export type LocationSubscription = { remove: () => void };

export interface BackgroundGeolocationConfig extends GeolocationOptions, GeolocationConfiguration {
  /** Start native tracking automatically after ready(). Default: false */
  startOnReady?: boolean;
  /** Continue native tracking after app process restore where supported. Default: true */
  stopOnTerminate?: boolean;
  /** Android foreground-service notification title. */
  notificationTitle?: string;
  /** Android foreground-service notification body. */
  notificationText?: string;
}

export interface BackgroundGeolocationState extends FitnessEngineState {
  enabled: boolean;
  configured: boolean;
  authorization: string;
  always: boolean;
}

export interface GeolocationDiagnosticEvent {
  event: string;
  platform: 'ios' | 'android';
  timestamp: number;
  reason?: string;
  message?: string;
  id?: string;
  accuracy?: number;
  pending?: number;
  deliverLive?: boolean;
  [key: string]: unknown;
}

export type TrackingMode =
  | 'fitness'
  | 'navigation'
  | 'balanced'
  | 'low_power'
  | 'stationary';

export type MotionActivityType =
  | 'stationary'
  | 'walking'
  | 'running'
  | 'cycling'
  | 'driving'
  | 'unknown';

export type SignalStrength = 'weak' | 'medium' | 'strong';

export interface FitnessEngineConfig {
  autoPause?: boolean;
  autoPauseDelaySeconds?: number;
  autoResume?: boolean;
  includePedometer?: boolean;
  onAutoPause?: () => void;
  onAutoResume?: () => void;
}

export interface FitnessEngineState {
  isWatching: boolean;
  isPaused: boolean;
  mode: TrackingMode;
  pendingQueue: number;
  motionState: string;
  signalStrength: SignalStrength;
  backgroundSessionActive?: boolean;
}

export type LocationPayload = GeolocationResponse & { id?: string };

export type AuthorizationStatus =
  | 'granted'
  | 'denied'
  | 'restricted'
  | 'notDetermined'
  | 'blocked';

export interface FitnessPermissionResult {
  foregroundGranted: boolean;
  backgroundGranted: boolean;
  motionGranted: boolean;
  status: 'ready' | 'foreground_only' | 'denied';
  message?: string;
}
