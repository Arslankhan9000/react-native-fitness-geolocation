# Competitive Research — Strava, Nike Run Club, Garmin, Fitbit

How top fitness apps solve GPS activity tracking, and what **react-native-fitness-geolocation** implements vs documents for app-level integration.

---

## Executive summary

| Capability | Strava | Nike RC | Garmin | Fitbit | **react-native-fitness-geolocation** |
|------------|--------|---------|--------|--------|---------------|
| Native background GPS | ✅ | ✅ | ✅ (watch) / ✅ (phone) | ✅ Connected GPS | ✅ **Built-in** |
| Write-first crash-safe queue | ✅ | ✅ | ✅ | ✅ | ✅ **SQLite native** |
| Motion auto-detection | ✅ | ✅ | ✅ IMU | ✅ IMU | ✅ **CMMotion / ActivityRecognition** |
| Auto-pause when stationary | ✅ | ✅ | ✅ | ✅ | ✅ **Native signal + event** |
| Adaptive GPS sampling | ✅ | ✅ | ✅ Multi-band | ✅ | ✅ **Tracking modes** |
| GPS filtering / smoothing | ✅ Map match | ✅ | ✅ Kalman fusion | ✅ | ✅ **Native filter engine** |
| Steps during activity | HealthKit | HealthKit | Watch IMU | IMU | ⚡ **CMPedometer optional** |
| HealthKit / Health Connect sync | ✅ | ✅ | ✅ | ✅ | 📄 **App integrates** |
| Foreground service (Android) | ✅ | ✅ | ✅ | ✅ | ✅ **Built-in** |
| Barometer elevation | ❌ phone | ❌ | ✅ ABC | ✅ | 📄 **Future / HealthKit** |
| Map matching (roads) | ✅ | ✅ | ✅ | ❌ | 📄 **App / Mapbox layer** |
| Privacy zones (hide start/end) | ✅ | ❌ | ❌ | ❌ | 📄 **App layer** |

**Legend:** ✅ Built into SDK · ⚡ Partial / optional · 📄 Documented — app adds based on use case

---

## Strava

### Techniques
1. **CoreLocation fitness mode** — `activityType = .fitness`, high accuracy while recording, reduced when paused.
2. **Background location mode** — `UIBackgroundModes: location` + Always authorization.
3. **Auto-pause** — Detects stopped movement via GPS speed + accelerometer; pauses timer and GPS sampling.
4. **Route recording** — Polyline built from filtered GPS; discards points with accuracy > ~50m.
5. **Map matching (post-process)** — Snaps route to roads for display (server-side / Mapbox Map Matching API).
6. **Privacy** — Hides start/end address zones (~100m radius).
7. **Battery** — Pauses location updates when activity paused; uses deferred updates where possible.

### Package equivalent
- `Geolocation.watchPosition` with fitness options → native engine
- `FitnessEngine.onAutoPause` → motion + GPS fusion
- `LocationFilter` → accuracy + spike rejection
- Privacy zones → app implements with coordinate masking

---

## Nike Run Club

### Techniques
1. **Phone-as-primary GPS** — Same CoreLocation stack as Strava.
2. **Audio-guided runs** — App layer (not location SDK).
3. **HealthKit integration** — Workouts written to Apple Health after completion.
4. **Lock screen / background** — Relies on iOS background location + audio session for guided runs.
5. **Pace smoothing** — Rolling window over filtered GPS segments.

### Package equivalent
- Native persistence survives screen lock
- `FitnessEngine.getMotionState()` for UI pace hints
- HealthKit → document in SETUP.md

---

## Garmin Connect

### Techniques
1. **Sensor fusion** — Watch combines GPS + accelerometer + gyroscope + **barometer (ABC)** for elevation and distance.
2. **Multi-band GPS** — Hardware on fēnix/Forerunner (not available on phone SDK).
3. **Connected GPS** — Phone GPS when watch has no GPS (similar to Fitbit Connected GPS).
4. **Activity classification** — Running vs cycling vs swimming from IMU patterns.
5. **Offline queue** — Device stores points; syncs on reconnect.
6. **Adaptive recording** — 1s interval moving, 60s interval stationary.

### Package equivalent
- `setMode('fitness' | 'balanced' | 'low_power' | 'stationary')` adaptive sampling
- `MotionEngine` activity type: walking, running, cycling, driving, stationary
- Native SQLite offline queue with foreground drain
- Barometer → not in phone SDK scope; document HealthKit altimeter

---

## Fitbit

### Techniques
1. **Connected GPS** — Phone records route when watch lacks GPS; same pattern as our phone-first SDK.
2. **IMU step counting** — Wrist accelerometer on device; phone uses **CMPedometer** / **Health Connect**.
3. **Auto workout detection** — Motion activity API triggers "workout started" prompt.
4. **Zone-based HR** — Watch hardware; app layer for phone-only.

### Package equivalent
- `MotionEngine.start()` + `onActivityChange` event
- `PedometerBridge` (iOS CMPedometer) optional steps stream
- Auto workout detection → `FitnessEngine.onWorkoutDetected`

---

## Technical patterns (industry standard)

### iOS (Apple-recommended for fitness apps)

```
CLLocationManager
  activityType = .fitness
  desiredAccuracy = kCLLocationAccuracyBest
  pausesLocationUpdatesAutomatically = false   ← fitness apps override Apple's default
  allowsBackgroundLocationUpdates = true     ← requires Always auth
  showsBackgroundLocationIndicator = true

+ CLBackgroundActivitySession (iOS 17+)      ← implemented
+ CMMotionActivityManager                    ← implemented  
+ CMPedometer (optional steps)               ← implemented
```

### Android

```
FusedLocationProviderClient
  PRIORITY_HIGH_ACCURACY while recording
  Foreground Service type=location           ← implemented
  ActivityRecognitionClient                  ← implemented
  WorkManager restart watchdog               ← documented for app
```

### Filtering pipeline (Strava-class)

```
Raw GPS fix
  → Accuracy gate (>50m discard)
  → Speed spike gate (>150 m/s discard)
  → Duplicate/jitter suppression
  → Weighted smoothing (accuracy-inverse weights)
  → Optional Kalman (V2)
  → Persist SQLite
  → Deliver to JS when active
```

---

## What the SDK owns vs what the app owns

### SDK owns (heart of tracker)
- Native GPS engine + background survival
- SQLite write-first queue
- Foreground replay to JS callbacks
- Permission API (request + status)
- Motion activity detection
- Auto-pause / auto-resume signals
- GPS filter pipeline
- Adaptive tracking modes
- iOS CLBackgroundActivitySession

### App owns (product layer)
- UI, maps, polylines
- Realm / server sync
- HealthKit / Health Connect write
- Custom foreground notification text
- Activity type picker, social, sharing
- Map matching API calls
- Privacy zones
- Min distance/duration validation before save

See [SETUP.md](./SETUP.md) for Info.plist, AndroidManifest, and Podfile requirements.
