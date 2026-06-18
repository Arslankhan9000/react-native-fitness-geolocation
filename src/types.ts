/** Compatible with @react-native-community/geolocation types */

export interface GeolocationResponse {
  coords: {
    latitude: number;
    longitude: number;
    altitude: number;
    accuracy: number;
    heading: number;
    speed: number;
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
  timeout?: number;
  maximumAge?: number;
  enableHighAccuracy?: boolean;
  distanceFilter?: number;
  activityType?: 'fitness' | 'automotiveNavigation' | 'otherNavigation' | 'other';
  pausesLocationUpdatesAutomatically?: boolean;
  showsBackgroundLocationIndicator?: boolean;
  useSignificantChanges?: boolean;
  deferredUpdatesDistance?: number;
  deferredUpdatesTimeout?: number;
  interval?: number;
  fastestInterval?: number;
  forceRequestLocation?: boolean;
  /** Micim extended — adaptive sampling preset */
  trackingMode?: TrackingMode;
}

export interface GeolocationConfiguration {
  skipPermissionRequests?: boolean;
  authorizationLevel?: 'always' | 'whenInUse';
  locationProvider?: 'auto' | 'android' | 'playServices';
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
