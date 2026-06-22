# Changelog

## 2.1.0

### iOS — Live Activities (Lock Screen & Dynamic Island)
- New `LiveActivity` JS module: `start`, `update`, `end`, `setEnabled`, `isEnabled`
- Native `LiveActivityManager.swift` (ActivityKit, iOS 16.1+): circuit-breaker, stale-date management, calorie estimation
- 5 new RCT bridge methods in `FitnessGeolocation.swift` / `.m`
- `NSSupportsLiveActivities` + `NSSupportsLiveActivitiesFrequentUpdates` keys documented for host app `Info.plist`
- `WorkoutLiveActivity.swift` — complete SwiftUI widget for Lock Screen, Dynamic Island compact/expanded/minimal, and StandBy

### iOS — C++ Native Tracking Engine (`TrackEngine.h/.cpp`)
- `GPSRingBuffer<2048>`: O(1) push/access, 64 KiB, zero heap allocation (replaces JS `[p, ...points].slice(500)`)
- `KalmanState`: 4-state Kalman filter using flat `double[4]`/`double[4][4]` stack arrays — ~0 heap allocations vs ~20 per fix in the previous Swift `[[Double]]` version
- `DistanceAccumulator`: Kahan-compensated running sum prevents FP drift over long runs
- `PaceWindow`: rolling 30-second pace (same smoothness as Garmin/Strava display)
- `LiveActivityGate`: `mach_absolute_time()` token-bucket throttle, fires before Swift/JS bridge
- `LocationFilterC`: C++ port of Swift `LocationFilter` (accuracy gate + spike detection + inverse-accuracy smoothing)
- `SessionEngine`: aggregates all above; hot path ~2 µs/fix on A15 Bionic (JS bridge alone costs 100–300 µs)
- `TrackEngineBridge.h/.mm`: ObjC++ bridge exposes engine to Swift; `TEFixResult` carries filtered coords, pace, speed, LA gate flag
- `LocationEngine.swift` now uses C++ engine for filtering, distance accumulation, and native Live Activity updates (no JS bridge crossing on the update path)
- `FitnessGeolocation-Bridging-Header.h` added for Swift ↔ ObjC++ interop

### Android — Bug fixes & reliability
- **Fixed**: `AndroidManifest.xml` declared `.HeadlessTaskService` but actual class is `FitnessHeadlessTaskService` — caused `ClassNotFoundException` at runtime
- **Fixed**: `LocationEngine.kt` missing public `restoreWatchFromCrash(mode, intervalMs, distanceM)` and `logDiagnostic(event)` methods — caused compile errors in `BootCompletedReceiver` and `TrackingRestartWorker`
- **Fixed**: `androidx.work:work-runtime-ktx` missing from `build.gradle` — `TrackingRestartWorker` (WorkManager) failed to compile
- **Fixed**: Notification ID collision — `BootCompletedReceiver` error notification now uses ID `48293` (was `48292`, same as `LiveActivityManager.NOTIFICATION_ID`)
- **Added**: `TrackingRestartWorker.schedule()` called when `watchPosition()` starts; `cancel()` called when watch stops — watchdog now runs during real tracking sessions
- **Added**: `active_session_id` written to SharedPreferences on `createSession()` — `BootCompletedReceiver` can reference the active session after reboot
- **Added**: `last_location_heartbeat` written to SharedPreferences on each persisted GPS fix — `TrackingRestartWorker` can detect GPS stalls (> 10 min without a fix)

### SDK — TypeScript
- Exported `LiveActivity` from `src/index.ts` and built into `lib/`
- `lib/typescript/index.d.ts`, `lib/commonjs/`, `lib/module/` rebuilt with all 18 source files including `LiveActivity.ts`

## 2.0.0

### Public release — general-purpose fitness geolocation

- Drop-in API compatible with `@react-native-community/geolocation`
- iOS: CoreLocation engine, LocationFilter, SQLite write-first, iOS 17 background activity session
- Android: Fused Location, SQLite queue, option parsing, runtime permissions, watch restore
- JS: AppState foreground drain, timeout support, `setRNConfiguration`, `PositionError` export
- Optional `FitnessEngine`, `MotionEngine`, `PermissionManager` for workout apps
- Motion tracking opt-in via `enableMotion` (not auto-started on every watch)
- `npx react-native-fitness-geolocation verify-setup` CLI
