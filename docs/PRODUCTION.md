# Production Guide — react-native-fitness-geolocation

Engineering reference for deploying and maintaining react-native-fitness-geolocation in production.

---

## Overview

| | |
|---|---|
| **Package** | `react-native-fitness-geolocation` v2.0.0 |
| **Type** | React Native native module |
| **Replaces** | `@react-native-community/geolocation` (activity tracking) |
| **Production app** | MFC-App (My Fitness Coach) |
| **Install** | `file:../packages/react-native-fitness-geolocation` |

---

## What this package does

1. **Collects GPS natively** — continues when JS thread is suspended (iOS background)
2. **Persists every point to SQLite** before any JS delivery (crash-safe)
3. **Replays background points** through your existing `watchPosition` callback when app opens
4. **Filters GPS noise** — accuracy gate, speed spikes, smoothing
5. **Detects motion** — walking/running/stationary for auto-pause (iOS)
6. **Manages permissions** — unified fitness permission API

---

## Quick integration (MFC-App pattern)

### Step 1 — Install

```json
// MFC-App/package.json
"react-native-fitness-geolocation": "file:../packages/react-native-fitness-geolocation"
```

```bash
yarn install
cd ios && pod install
```

### Step 2 — Swap import (only code change)

```javascript
// LocationTrackingService.js
import Geolocation from 'react-native-fitness-geolocation';

// LocationService.js
import Geolocation from 'react-native-fitness-geolocation';
```

### Step 3 — Verify platform config

```bash
node node_modules/react-native-fitness-geolocation/scripts/verify-setup.js
```

MFC-App already passes all checks.

### Step 4 — Rebuild on device

Test on a **physical device** with **Always Allow** location permission. Simulator does not represent background GPS accurately.

---

## Runtime behavior

### During an active workout

```
User starts activity
  → BackgroundService.start()          [existing — notification + steps]
  → Geolocation.watchPosition()        [native GPS starts]
  → saveCoordinate() on each fix       [existing — Realm]

User locks screen
  → JS may suspend
  → Native continues GPS → SQLite

User unlocks phone
  → AppState 'active'
  → Package replays SQLite → watchPosition callbacks
  → saveCoordinate() catches up Realm
  → Map polyline updates
```

### Paused activity

Call from app when user pauses:

```javascript
await Geolocation.setActivityPaused(true);   // reduces GPS sampling
await Geolocation.setActivityPaused(false);  // resume fitness mode
```

Or use `FitnessEngine.setPaused()` / auto-pause via `MotionEngine`.

---

## API reference (production)

### Essential (drop-in)

```javascript
import Geolocation from 'react-native-fitness-geolocation';

// Same as @react-native-community/geolocation
Geolocation.watchPosition(success, error, {
  enableHighAccuracy: true,
  distanceFilter: 5,
  activityType: 'fitness',
  pausesLocationUpdatesAutomatically: false,
  showsBackgroundLocationIndicator: true,
});

Geolocation.clearWatch(watchId);
Geolocation.requestAuthorization('always');  // returns 'granted' | 'denied'
```

### Operations

```javascript
// Force sync after app resume (usually automatic)
const count = await Geolocation.syncPendingLocations();

// Monitor native backlog
const pending = await Geolocation.getQueueSize();

// Engine diagnostics
const state = await Geolocation.getEngineState();
// { isWatching, isPaused, mode, pendingQueue, motionState, signalStrength }
```

### Permissions (recommended for StartActivityScreen)

```javascript
import { PermissionManager } from 'react-native-fitness-geolocation';

const result = await PermissionManager.requestFitnessPermissions();

if (result.status === 'foreground_only') {
  // Show UI: user must enable "Always Allow" for locked-screen tracking
  PermissionManager.openSettings();
}
```

### Auto-pause integration (optional)

```javascript
import { MotionEngine } from 'react-native-fitness-geolocation';
import { DeviceEventEmitter } from 'react-native';

MotionEngine.onAutoPause(() => toggleTracking('auto'));
MotionEngine.onAutoResume(() => DeviceEventEmitter.emit('activity:movementDetected'));
```

MotionEngine starts automatically when `watchPosition` is called.

---

## Platform requirements

See [SETUP.md](./SETUP.md) for full copy-paste snippets.

### iOS (required)

- [x] `NSLocationWhenInUseUsageDescription`
- [x] `NSLocationAlwaysAndWhenInUseUsageDescription`
- [x] `UIBackgroundModes: location`
- [x] `NSMotionUsageDescription` (auto-pause)
- [x] User grants **Always Allow** location

### Android (required)

- [x] `ACCESS_FINE_LOCATION`
- [x] `ACCESS_BACKGROUND_LOCATION`
- [x] `FOREGROUND_SERVICE_LOCATION`
- [x] `ACTIVITY_RECOGNITION`
- [x] Foreground service via `react-native-background-actions`

---

## Architecture components

| Component | Platform | File |
|-----------|----------|------|
| LocationEngine | iOS | `ios/FitnessGeolocation/LocationEngine.swift` |
| LocationDatabase | iOS | `ios/FitnessGeolocation/LocationDatabase.swift` |
| LocationFilter | iOS | `ios/FitnessGeolocation/LocationFilter.swift` |
| MotionEngine | iOS | `ios/FitnessGeolocation/MotionEngine.swift` |
| BackgroundActivitySession | iOS 17+ | `ios/FitnessGeolocation/BackgroundActivitySession.swift` |
| LocationEngine | Android | `android/.../LocationEngine.kt` |
| LocationDatabase | Android | `android/.../LocationDatabase.kt` |
| Geolocation (JS) | Both | `src/Geolocation.ts` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| No GPS when screen locked | When In Use only permission | Request Always; check Settings |
| Route gaps after unlock | Drain not running | Call `syncPendingLocations()`; ensure watch still active |
| Module not found | Pod not linked | `pod install`; rebuild; check `FitnessGeolocation.podspec` at package root |
| Background indicator missing | iOS config | Set `showsBackgroundLocationIndicator: true` |
| Points duplicated | — | Should not happen; `delivered_to_js` prevents double replay |
| Battery drain high | Mode too aggressive | Use `setTrackingMode('balanced')` or `'low_power'` |
| Auto-pause not firing | Motion permission | Add `NSMotionUsageDescription`; test on device |

### Debug commands

```javascript
console.log(await Geolocation.getEngineState());
console.log('Pending native queue:', await Geolocation.getQueueSize());
await Geolocation.syncPendingLocations();
```

### Logs to watch

```
[FitnessGeolocation] Delivered N queued background location(s)
```

---

## Release checklist

- [ ] Bump version in `package.json`
- [ ] `yarn prepare` (bob build)
- [ ] MFC-App `yarn install`
- [ ] `cd ios && pod install`
- [ ] `verify-setup.js` passes
- [ ] Test: 10+ min locked-screen walk on iOS device
- [ ] Test: app kill during activity → relaunch → route intact
- [ ] Test: pause/resume during activity
- [ ] Test: Android foreground service notification visible

---

## Relationship to original spec

Original design doc: `/smart-location-engine-v1.md` (repo root)

| V1 spec item | v2.0 status |
|--------------|-------------|
| Drop-in Geolocation API | ✅ Done |
| Native SQLite write-first | ✅ Done |
| Background iOS tracking | ✅ Done |
| Foreground JS replay | ✅ Done |
| Motion detection | ✅ iOS; Android scaffold |
| Adaptive tracking modes | ✅ Done |
| GPS filtering | ✅ Heuristic (not Kalman) |
| ACK server sync pipeline | ❌ v3 |
| Android foreground service | 📄 App uses background-actions |
| HealthKit integration | 📄 App layer |
| TurboModule | ❌ v3 |

---

## Support & ownership

- **Package path:** `packages/react-native-fitness-geolocation/`
- **Docs:** `docs/` folder + `AGENTS.md`
- **Competitive analysis:** [COMPETITIVE_RESEARCH.md](./COMPETITIVE_RESEARCH.md)
