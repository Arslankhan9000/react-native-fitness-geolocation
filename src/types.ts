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
  distanceFilter?: number;
  activityType?: 'fitness' | 'automotiveNavigation' | 'otherNavigation' | 'other';
  pausesLocationUpdatesAutomatically?: boolean;
  showsBackgroundLocationIndicator?: boolean;
  useSignificantChanges?: boolean;
  deferredUpdatesDistance?: number;
  deferredUpdatesTimeout?: number;
  /** Android — desired interval between updates (ms). Default: 3000 */
  interval?: number;
  /** Android — fastest interval between updates (ms). Default: 1000 */
  fastestInterval?: number;
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
