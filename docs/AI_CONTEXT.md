# AI Context Document — react-native-fitness-geolocation v2

Structured reference for AI coding assistants. Last updated: June 2026.

---

## 1. Executive summary

`react-native-fitness-geolocation` is a React Native native module that replaces `@react-native-community/geolocation` for fitness activity tracking. It provides Strava-class reliability: native background GPS, SQLite persistence, motion intelligence, and automatic sync to JS when the app returns to foreground.

**Primary consumer:** MFC-App (`My Fitness Coach`) — physical activity tracking screen.

**Install path:** `file:../packages/react-native-fitness-geolocation` (monorepo local package).

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         JS LAYER (React Native)                   │
│  Geolocation.watchPosition(success, error, options)              │
│       ↓ success callback                                          │
│  LocationTrackingService.saveCoordinate() → Realm batch          │
│  AppState.active → drainNativeQueueToWatches() [automatic]       │
└────────────────────────────┬─────────────────────────────────────┘
                             │ RCTEventEmitter (foreground live)
                             │ Promise calls (drain, permissions)
┌────────────────────────────▼─────────────────────────────────────┐
│                      NATIVE LAYER (iOS/Android)                   │
│                                                                   │
│  CLLocationManager / FusedLocationProvider                        │
│  Android FitnessLocationService keeps GPS foreground-eligible      │
│       ↓                                                           │
│  LocationFilter (accuracy ≤50m, spike ≤150m/s, smooth)           │
│       ↓                                                           │
│  LocationDatabase SQLite INSERT (delivered_to_js = 0|1)           │
│       ↓                                                           │
│  If app active → emit watchPosition event + mark delivered        │
│  If app background → persist only (no JS emit)                    │
│                                                                   │
│  MotionEngine (CMMotionActivityManager) → autoPause/autoResume    │
│  BackgroundActivitySession (iOS 17+) keeps pipeline alive          │
└──────────────────────────────────────────────────────────────────┘
```

### Design principle (from original spec)

> JS handles UI, config, events, sync. Native handles GPS, motion, filtering, persistence, recovery. **JS is never required for continuous tracking.**

---

## 3. Data flow scenarios

### 3.1 Foreground tracking (normal)

1. App calls `Geolocation.watchPosition(callback, error, options)`
2. Native starts `CLLocationManager.startUpdatingLocation()` / FusedLocationProvider
3. Android starts `FitnessLocationService`; native starts `MotionEngine` where available
4. GPS fix → `LocationFilter.process()` → SQLite insert → emit `watchPosition` event
5. JS callback runs → MFC-App `saveCoordinate()` → Realm

### 3.2 Background tracking (screen locked)

1. iOS / Android may suspend the JS thread
2. Native continues receiving CLLocation / foreground-service FusedLocation updates
3. Each fix → filter → SQLite insert with `delivered_to_js = 0`
4. No JS callback (JS may be frozen)
5. `CLBackgroundActivitySession` (iOS 17+) and Android foreground service keep the native pipeline alive

### 3.3 Foreground return (sync)

1. `UIApplication.didBecomeActiveNotification` OR `AppState` → `active`
2. Native emits `foregroundSync` event
3. JS `drainNativeQueueToWatches()` calls `getPendingForJs(limit)`
4. Each pending row replayed through **all active watch callbacks** (same as live GPS)
5. MFC-App `saveCoordinate()` writes to Realm
6. `markDelivered(ids)` prevents double-replay
7. `purgeDelivered()` on watch stop cleans native backup

### 3.4 App kill recovery

1. Native persists `watchActive = true` in UserDefaults
2. On relaunch, `LocationEngine.restoreWatchIfNeeded()` restarts CLLocationManager
3. When JS calls `watchPosition` again, drain replays any SQLite backlog

---

## 4. Public API surface

### 4.1 Geolocation (drop-in — default export)

```typescript
import Geolocation from 'react-native-fitness-geolocation';

Geolocation.getCurrentPosition(success, error?, options?);
Geolocation.watchPosition(success, error?, options?): number;  // watchId
Geolocation.clearWatch(watchId);  // drains pending native rows before teardown
Geolocation.stopObserving();      // drains pending native rows before teardown
Geolocation.requestAuthorization('whenInUse' | 'always'): Promise<string>;
Geolocation.requestAuthorization(success, error);  // community callback style
Geolocation.getAuthorizationStatus(): Promise<{ status, always }>;
Geolocation.setRNConfiguration(config);  // no-op compat

// Fitness geolocation extensions
Geolocation.syncPendingLocations(): Promise<number>;
Geolocation.getQueueSize(): Promise<number>;
Geolocation.setTrackingMode(mode): Promise<void>;
Geolocation.setActivityPaused(paused): Promise<void>;
Geolocation.getEngineState(): Promise<object>;
```

### 4.1b BackgroundGeolocation-style lifecycle

This is a clean-room API shape inspired by mature background-location SDK public contracts. Do not copy closed native implementation. The core rule is: native records, SQLite persists, JS subscribes, JS acks after app storage succeeds.

```typescript
import { BackgroundGeolocation } from 'react-native-fitness-geolocation';

BackgroundGeolocation.onLocation(async location => {
  await saveCoordinate(location);
});

await BackgroundGeolocation.ready({
  authorizationLevel: 'always',
  enableHighAccuracy: true,
  desiredAccuracy: 10,
  distanceFilter: 0,
  locationUpdateInterval: 1000,
  fastestLocationUpdateInterval: 1000,
  trackingMode: 'fitness',
  pausesLocationUpdatesAutomatically: false,
});

await BackgroundGeolocation.start();
await BackgroundGeolocation.sync();
await BackgroundGeolocation.stop();
```

### 4.2 PermissionManager

```typescript
import { PermissionManager } from 'react-native-fitness-geolocation';

await PermissionManager.requestFitnessPermissions();
// → { foregroundGranted, backgroundGranted, status: 'ready' | 'foreground_only' | 'denied' }

await PermissionManager.getStatus();
PermissionManager.openSettings();
PermissionManager.openBatterySettings();  // Android
```

### 4.3 MotionEngine

```typescript
import { MotionEngine } from 'react-native-fitness-geolocation';

MotionEngine.start({ includePedometer?: boolean });
MotionEngine.stop();
MotionEngine.configureAutoPause(enabled, delaySeconds);

MotionEngine.onActivityChange(({ activity, confidence }) => {});
MotionEngine.onStepsUpdate(({ steps, distanceM }) => {});
MotionEngine.onAutoPause(({ reason }) => {});
MotionEngine.onAutoResume(({ reason }) => {});
```

Native events: `motionActivity`, `motionSteps`, `autoPause`, `autoResume`

### 4.4 FitnessEngine (orchestrator)

```typescript
import { createFitnessEngine } from 'react-native-fitness-geolocation';

const engine = createFitnessEngine({
  autoPause: true,
  autoPauseDelaySeconds: 45,
  onAutoPause: () => {},
  onAutoResume: () => {},
});

await engine.prepare();  // permissions
engine.start(onLocation, onError, { trackingMode: 'fitness' });
engine.stop();
engine.setPaused(true);
await engine.syncPending();
```

### 4.5 GeolocationOptions (extends community)

```typescript
{
  enableHighAccuracy?: boolean;
  distanceFilter?: number; // 0 = densest native route; iOS still not timer-guaranteed
  activityType?: 'fitness' | 'automotiveNavigation' | 'otherNavigation' | 'other';
  pausesLocationUpdatesAutomatically?: boolean;  // default false in native
  showsBackgroundLocationIndicator?: boolean;
  trackingMode?: 'fitness' | 'navigation' | 'balanced' | 'low_power' | 'stationary';
}
```

---

## 5. Native events (RCTEventEmitter)

| Event | Payload | When |
|-------|---------|------|
| `watchPosition` | `{ watchId, position?, error?, nativeId? }` | Live GPS (foreground) |
| `foregroundSync` | `{ pending: number }` | App became active |
| `authorizationChange` | `{ status }` | Permission changed |
| `motionActivity` | `{ activity, confidence }` | Motion state change |
| `motionSteps` | `{ steps, distanceM }` | Pedometer update |
| `autoPause` | `{ reason: 'stationary' }` | Auto-pause triggered |
| `autoResume` | `{ reason: 'movement' }` | Movement detected |

---

## 6. SQLite schema

Table: `locations` in `Documents/fitness_geolocation.db`

| Column | Type | Purpose |
|--------|------|---------|
| id | TEXT PK | UUID |
| latitude, longitude | REAL | Coordinates |
| accuracy, speed, heading, altitude | REAL | GPS metadata |
| timestamp | INTEGER | Unix ms |
| battery_level | REAL | Device battery |
| signal_strength | TEXT | weak/medium/strong |
| provider | TEXT | gps/fused |
| motion_state | TEXT | stationary/moving/unknown |
| confidence | REAL | 0-1 |
| session_id | TEXT | Session grouping |
| delivered_to_js | INTEGER | 0=pending replay, 1=delivered |

---

## 7. iOS native configuration

Set automatically by `LocationEngine`:

```swift
locationManager.pausesLocationUpdatesAutomatically = false
locationManager.activityType = .fitness
locationManager.desiredAccuracy = kCLLocationAccuracyBest
locationManager.showsBackgroundLocationIndicator = true
locationManager.allowsBackgroundLocationUpdates = true  // when Always authorized
```

Requires app Info.plist (documented in SETUP.md):
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `UIBackgroundModes: location`
- `NSMotionUsageDescription` (for MotionEngine)

---

## 8. MFC-App file references

| File | Role |
|------|------|
| `MFC-App/src/screens/track_physical_activities/utils/LocationTrackingService.js` | Main tracker — `watchPosition`, batching, Realm |
| `MFC-App/src/screens/track_physical_activities/components/LocationService.js` | Permission + getCurrentCoords for map |
| `MFC-App/src/screens/track_physical_activities/ActivityMap.js` | Map UI, auto-pause modal |
| `MFC-App/src/screens/track_physical_activities/hook/useActivityTracker.js` | Reads Realm coords for polyline |
| `MFC-App/src/screens/track_physical_activities/StartActivityScreen.js` | Pre-activity permission flow |

MFC-App also uses:
- `react-native-background-actions` — app-specific notification text and step counter loop (GPS foreground service is built in)
- `realm` — app session + LocationPoint storage (NOT replaced; native SQLite is GPS buffer only)

---

## 9. SDK vs app responsibilities

| Responsibility | SDK | MFC-App |
|----------------|-----|---------|
| Background GPS collection | ✅ | — |
| SQLite GPS buffer | ✅ | — |
| Foreground → Realm replay | ✅ (via callbacks) | saveCoordinate |
| Realm session/points | — | ✅ |
| Map / polyline UI | — | ✅ |
| GPS foreground service | ✅ | — |
| Custom notification text | basic default | ✅ background-actions |
| Step counting | MotionEngine optional | ✅ stepCounterHelper |
| HealthKit sync | — | ✅ react-native-health |
| Server upload | — | ✅ app API |
| Auto-pause UI modal | emits events | ✅ NotMovingModal |
| Min distance validation | — | ✅ ActivityMap |

---

## 10. Tracking modes

| Mode | distanceFilter | Accuracy | Use case |
|------|---------------|----------|----------|
| fitness | 5m | Best | Running, walking (default) |
| navigation | 3m | BestForNavigation | Cycling, fast movement |
| balanced | 8m | NearestTenMeters | Hiking |
| low_power | 15m | HundredMeters | Long walks, battery save |
| stationary | 25m | HundredMeters | Auto-pause / paused state |

---

## 11. LocationFilter rules

Reject if:
- `horizontalAccuracy > 50m` or `< 0`
- Coordinates `(0, 0)`
- Computed speed `> 150 m/s`
- Distance `< 1m` with accuracy `> 20m` (jitter)

Accept with weighted smoothing (inverse accuracy² weights).

Warmup: first 3 good fixes accepted without sanity check.

---

## 12. Known limitations (v2.0)

- Android MotionEngine is scaffold only (GPS speed-based motion on Android)
- No TurboModule / New Architecture codegen yet
- No HealthKit integration in SDK
- No map matching / road snapping
- No server sync / ACK pipeline (native deletes on purge only)
- Kalman filter not implemented (heuristic smoothing only)

---

## 13. Common tasks for AI agents

### Add new native method
1. Implement in `LocationEngine.swift` or `MotionEngine.swift`
2. Expose in `FitnessGeolocation.swift` + `FitnessGeolocation.m` (RCT_EXTERN)
3. Wrap in `Geolocation.ts` or dedicated JS module
4. Export from `index.ts`
5. Update this doc + PRODUCTION.md

### Debug missing background points
1. Check Always location permission: `Geolocation.getAuthorizationStatus()`
2. Check native queue: `Geolocation.getQueueSize()`
3. Force sync: `Geolocation.syncPendingLocations()`
4. Verify Info.plist `UIBackgroundModes: location`
5. Test on real device (not simulator)

### MFC-App import migration
Only change:
```javascript
import Geolocation from 'react-native-fitness-geolocation';
```
Do NOT add `startTracking()` or platform conditionals unless explicitly requested.

---

## 14. Build & link

```bash
# Package
packages/react-native-fitness-geolocation/

# Autolinking requires podspec at package ROOT
FitnessGeolocation.podspec

# MFC-App install
yarn add file:../packages/react-native-fitness-geolocation
cd ios && pod install

# Verify
node node_modules/react-native-fitness-geolocation/scripts/verify-setup.js
```

Native module name for `NativeModules`: `FitnessGeolocation`
