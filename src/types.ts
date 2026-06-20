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

export interface TimeBasedLocation {
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
  /** GPS signal quality at this point */
  gpsStrength: GpsStrength;
  /** Whether the device is estimated to be stationary */
  isStationary: boolean;
  /** Distance from previous point in meters */
  distanceFromPrev: number;
  /** Cumulative distance for this session in meters */
  cumulativeDistance: number;
  /** Battery level at time of this point (0.0–1.0) */
  batteryLevel: number;
  /** Current motion state */
  motionState: MotionActivityType;
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
  desiredAccuracy?: number;
  distanceFilter?: number;
  activityType?: 'fitness' | 'automotiveNavigation' | 'otherNavigation' | 'other';
  pausesLocationUpdatesAutomatically?: boolean;
  showsBackgroundLocationIndicator?: boolean;
  useSignificantChanges?: boolean;
  deferredUpdatesDistance?: number;
  deferredUpdatesTimeout?: number;
  interval?: number;
  locationUpdateInterval?: number;
  fastestInterval?: number;
  fastestLocationUpdateInterval?: number;
  forceRequestLocation?: boolean;
  trackingMode?: TrackingMode;
  enableMotion?: boolean;
  includePedometer?: boolean;
}

export interface TimeBasedOptions {
  /** Interval in ms between location samples (default: 3000) */
  intervalMs?: number;
  /** Enable adaptive interval — slows down when stationary (default: true) */
  adaptiveInterval?: boolean;
  /** Stationary interval in ms when device isn't moving (default: 30000) */
  stationaryIntervalMs?: number;
  /** Enable motion detection for auto-pause/resume (default: true) */
  enableMotion?: boolean;
  /** Include pedometer data (default: false) */
  includePedometer?: boolean;
  /** Minimum accuracy to accept a fix (default: 50) */
  maxAccuracy?: number;
}

export interface GeolocationConfiguration {
  skipPermissionRequests?: boolean;
  authorizationLevel?: 'always' | 'whenInUse';
  locationProvider?: 'auto' | 'android' | 'playServices';
  enableBackgroundLocationUpdates?: boolean;
}

export type LocationSubscription = { remove: () => void };

export interface BackgroundGeolocationConfig extends GeolocationOptions, GeolocationConfiguration {
  startOnReady?: boolean;
  stopOnTerminate?: boolean;
  notificationTitle?: string;
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

export type GpsStrength = 'strong' | 'medium' | 'weak' | 'none';

export type ActivityState = 'idle' | 'preparing' | 'tracking' | 'paused' | 'ending' | 'completed' | 'error';

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

export type SignalStrength = 'weak' | 'medium' | 'strong';

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

// ─── Debug Monitor Types ────────────────────────────────────────────────────

export interface DebugMonitorConfig {
  /** Enable debug mode — sound effects + notifications for lifecycle events (default: false) */
  debug?: boolean;
  /** Enable sound effects in debug mode (default: true) */
  sound?: boolean;
  /** Minutes of stillness before transitioning to stationary state (default: 5) */
  stopTimeout?: number;
  /** Seconds between heartbeat events (default: 60) */
  heartbeatInterval?: number;
  /** Auto-stop tracking after N minutes (default: 0 = disabled) */
  stopAfterElapsedMinutes?: number;
  /** Notification title for Android foreground service */
  notificationTitle?: string;
  /** Notification text when stationary */
  notificationTextStationary?: string;
  /** Notification text when walking */
  notificationTextWalking?: string;
  /** Notification text when running */
  notificationTextRunning?: string;
  /** Notification text when cycling */
  notificationTextCycling?: string;
  /** Notification text when driving */
  notificationTextDriving?: string;
  /** Notification text when moving (unknown activity type) */
  notificationTextMoving?: string;
}

export interface DebugMotionState {
  state: 'moving' | 'stationary';
  activity: MotionActivityType;
  confidence: number;
  sinceTimestamp: number;
  stopTimeoutRemaining: number;
}

export interface DebugLifecycleEvent {
  event: string;
  message: string;
  timestamp: number;
  data?: Record<string, unknown>;
}

export type DebugLifecycleSound =
  | 'motionchange_true'
  | 'motionchange_false'
  | 'location_recorded'
  | 'location_error'
  | 'heartbeat'
  | 'geofence_enter'
  | 'geofence_exit'
  | 'stop_timeout_start'
  | 'stop_timeout_cancel'
  | 'stop_detection_delay';

// ─── Activity Manager Types ─────────────────────────────────────────────────

export interface ActivityOptions {
  /** Activity name (default: "Workout") */
  name?: string;
  /** Activity type (default: "running") */
  activityType?: 'running' | 'walking' | 'cycling' | 'hiking' | 'other';
  /** Tracking mode (default: 'fitness') */
  trackingMode?: TrackingMode;
  /** Time-based tracking interval in ms (default: 3000) */
  intervalMs?: number;
  /** Enable adaptive interval (default: true) */
  adaptiveInterval?: boolean;
  /** Stationary pause interval in ms (default: 30000) */
  stationaryIntervalMs?: number;
  /** Enable auto-pause when stationary (default: true) */
  autoPause?: boolean;
  /** Seconds of stillness before auto-pause (default: 45) */
  autoPauseDelaySeconds?: number;
  /** Enable auto-resume on movement (default: true) */
  autoResume?: boolean;
  /** Include pedometer (default: false) */
  includePedometer?: boolean;
  /** Maximum GPS accuracy to accept a fix in meters (default: 50) */
  maxAccuracy?: number;
  /** Custom metadata to attach to this activity */
  extras?: Record<string, unknown>;
}

export interface ActivitySummary {
  /** Unique session ID */
  sessionId: string;
  /** Activity name */
  name: string;
  /** Activity type */
  activityType: string;
  /** Unix timestamp ms when activity started */
  startTime: number;
  /** Unix timestamp ms when activity ended (0 if still active) */
  endTime: number;
  /** Duration in seconds */
  duration: number;
  /** Duration in seconds excluding paused time */
  activeDuration: number;
  /** Total distance in meters */
  totalDistance: number;
  /** Total paused time in seconds */
  totalPausedDuration: number;
  /** Number of auto-pause events */
  pauseCount: number;
  /** Average speed in m/s */
  averageSpeed: number;
  /** Max speed in m/s */
  maxSpeed: number;
  /** Elevation gain in meters */
  elevationGain: number;
  /** Average GPS accuracy in meters */
  averageAccuracy: number;
  /** Number of GPS points collected */
  pointCount: number;
  /** Whether this session has been uploaded to the server */
  uploaded: boolean;
  /** Upload status message */
  uploadStatus?: string;
  /** Custom metadata */
  extras?: Record<string, unknown>;
}

export interface ActivityStateSnapshot {
  state: ActivityState;
  sessionId: string | null;
  elapsedMs: number;
  activeMs: number;
  pausedMs: number;
  totalDistance: number;
  currentSpeed: number | null;
  averageSpeed: number;
  gpsStrength: GpsStrength;
  isStationary: boolean;
  batteryLevel: number;
  pointCount: number;
}

export interface HeartbeatEvent {
  timestamp: number;
  state: ActivityState;
  elapsedMs: number;
  totalDistance: number;
  gpsStrength: GpsStrength;
  batteryLevel: number;
  pendingUploadCount: number;
}

export interface AutoPauseEvent {
  reason: 'stationary' | 'gps' | 'manual';
  timestamp: number;
}

export interface AutoResumeEvent {
  reason: 'movement' | 'manual';
  timestamp: number;
}

export interface GpsStrengthEvent {
  strength: GpsStrength;
  accuracy: number;
  timestamp: number;
}

export interface SmartGPSConfig {
  /** Enable adaptive interval (default: true) */
  adaptiveInterval?: boolean;
  /** Interval when actively moving in ms (default: 3000) */
  activeIntervalMs?: number;
  /** Interval when stationary in ms (default: 30000) */
  stationaryIntervalMs?: number;
  /** Interval when GPS signal is weak in ms (default: 10000) */
  weakSignalIntervalMs?: number;
  /** Speed threshold in m/s below which we consider device stationary (default: 0.5) */
  stationarySpeedThreshold?: number;
  /** Time in ms of no movement before switching to stationary mode (default: 10000) */
  stationaryDelayMs?: number;
  /** Minimum accuracy to accept a fix in meters (default: 50) */
  maxAccuracy?: number;
  /** Maximum accuracy to consider GPS "strong" in meters (default: 10) */
  strongAccuracyThreshold?: number;
  /** Maximum accuracy to consider GPS "medium" in meters (default: 30) */
  mediumAccuracyThreshold?: number;
}

export interface OEMBatteryInfo {
  manufacturer: string;
  model: string;
  isBatteryOptimizationExempt: boolean;
  canOpenOemSettings: boolean;
  oemSettingsAppName: string | null;
}

export interface DevLogEntry {
  level: 'debug' | 'info' | 'warn' | 'error';
  tag: string;
  message: string;
  timestamp: number;
  data?: Record<string, unknown>;
}

// ─── Headless Task Types ────────────────────────────────────────────────────

export interface HeadlessEvent {
  name: string;
  params: Record<string, unknown>;
}

export type HeadlessTaskCallback = (event: HeadlessEvent) => Promise<void>;

// ─── HTTP Auto-Sync Types ──────────────────────────────────────────────────

export type HttpMethod = 'POST' | 'PUT' | 'PATCH';

export interface HttpConfig {
  /** Server URL for auto-uploading locations */
  url?: string;
  /** HTTP method (default: 'POST') */
  method?: HttpMethod;
  /** Custom HTTP headers */
  headers?: Record<string, string>;
  /** Automatically sync locations to server (default: false) */
  autoSync?: boolean;
  /** Sync in batch (single POST with array) vs individual (default: true) */
  batchSync?: boolean;
  /** Max batch size for batchSync (default: 100) */
  batchSize?: number;
  /** Max days to persist locations in SQLite before auto-delete (default: 7) */
  maxDaysToPersist?: number;
  /** Retry count on failure (default: 3) */
  retryCount?: number;
  /** Custom location JSON template (default: all fields) */
  locationTemplate?: string;
  /** Additional params to include in every request */
  params?: Record<string, string>;
}

export interface HttpEvent {
  success: boolean;
  status: number;
  responseText: string;
  locationCount?: number;
}

// ─── Geofencing Types ──────────────────────────────────────────────────────

export interface Geofence {
  /** Unique identifier for this geofence */
  identifier: string;
  /** Latitude of center point */
  latitude: number;
  /** Longitude of center point */
  longitude: number;
  /** Radius in meters */
  radius: number;
  /** Notify on entry (default: true) */
  notifyOnEntry?: boolean;
  /** Notify on exit (default: true) */
  notifyOnExit?: boolean;
  /** Notify on dwell (default: false) */
  notifyOnDwell?: boolean;
  /** Time in ms before dwell notification fires (default: 30000) */
  loiteringDelayMs?: number;
  /** Custom metadata attached to this geofence */
  extras?: Record<string, unknown>;
}

export interface GeofenceEvent {
  identifier: string;
  action: 'ENTER' | 'EXIT' | 'DWELL';
  latitude: number;
  longitude: number;
  radius: number;
  timestamp: number;
  extras?: Record<string, unknown>;
}

export interface GeofencesChangeEvent {
  /** Geofences that were just activated */
  on: Geofence[];
  /** Identifiers of geofences that were just deactivated */
  off: string[];
}

// ─── Provider & Power Save Types ───────────────────────────────────────────

export interface ProviderChangeEvent {
  /** Whether location services are enabled */
  enabled: boolean;
  /** Authorization status: 'always' | 'when_in_use' | 'denied' | 'not_determined' */
  status: string;
  /** Whether GPS provider is available (Android) */
  gps?: boolean;
  /** Whether network provider is available (Android) */
  network?: boolean;
  /** iOS 14+: 'full' | 'reduced' */
  accuracyAuthorization?: string;
}

export interface ConnectivityChangeEvent {
  connected: boolean;
  type?: string;
}

export interface SensorState {
  accelerometer: boolean;
  gyroscope: boolean;
  magnetometer: boolean;
  /** Android only */
  significantMotion?: boolean;
  /** iOS only */
  motionHardware?: boolean;
}
