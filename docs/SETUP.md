# Platform Setup Guide

What **react-native-fitness-geolocation** handles automatically vs what you must add to your app.

---

## Quick install

```bash
yarn add react-native-fitness-geolocation
cd ios && pod install
```

The native module auto-links via React Native autolinking. No manual `AppDelegate` changes required.

---

## iOS — Required (you add once)

### 1. Info.plist — Location permission strings

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We use your location to track workouts and show your route on the map.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need background location to continue tracking when your screen is locked during a workout.</string>
```

### 2. Info.plist — Background mode

```xml
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

> Optional: `fetch`, `processing` if you use background fetch for sync — not required for GPS.

### 3. Request permissions in app (SDK provides API)

```javascript
import Geolocation, { PermissionManager } from 'react-native-fitness-geolocation';

// Full fitness flow (foreground → background)
const result = await PermissionManager.requestFitnessPermissions();
if (!result.backgroundGranted) {
  // Show UI explaining "Always Allow" for locked-screen tracking
}
```

### 4. Podfile — react-native-permissions (if not already)

If you use `react-native-permissions` alongside this SDK:

```ruby
setup_permissions([
  'LocationWhenInUse',
  'LocationAlways',
  'Motion',  # for MotionEngine
])
```

---

## iOS — Optional

| Feature | Info.plist key | SDK API |
|---------|----------------|---------|
| Motion / auto-pause | `NSMotionUsageDescription` | `MotionEngine.start()` |
| Steps during workout | `NSMotionUsageDescription` | `MotionEngine.startPedometer()` |
| HealthKit sync | `NSHealthShareUsageDescription` | App uses `react-native-health` |
| Barometer elevation | — | HealthKit or future SDK |

---

## Android — Required (you add once)

### AndroidManifest.xml

```xml
<!-- Foreground location (required) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Background (Android 10+) — request at runtime after foreground granted -->
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />

<!-- Foreground service while tracking (Android 10+) -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<!-- Motion / activity recognition (auto-pause) -->
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
```

### Foreground service (keep existing background-actions)

The SDK handles GPS natively. Your app should keep `react-native-background-actions` for:
- Persistent notification during workout
- Step counter JS callbacks
- Notification text updates

Example service declaration (you likely already have this):

```xml
<service
  android:name="com.asterinet.react.bgactions.RNBackgroundActionsTask"
  android:foregroundServiceType="location|dataSync"
  android:exported="false" />
```

### Runtime permission order (Android 11+)

```javascript
await PermissionManager.requestFitnessPermissions();
// SDK requests: FINE → BACKGROUND (separate screens on Android 11+)
```

---

## Android — Optional

| Feature | Permission | Notes |
|---------|------------|-------|
| Health Connect | `android.permission.health.*` | App integrates separately |
| Exact alarms restart | `SCHEDULE_EXACT_ALARM` | WorkManager fallback documented |
| Ignore battery opt | Settings intent | `PermissionManager.openBatterySettings()` |

---

## Verify setup

```bash
npx react-native-fitness-geolocation verify-setup
# or from package:
node node_modules/react-native-fitness-geolocation/scripts/verify-setup.js
```

---

## MFC-App checklist (already configured ✅)

Your project already has:
- ✅ `UIBackgroundModes: location`
- ✅ `NSLocationAlwaysAndWhenInUseUsageDescription`
- ✅ `NSMotionUsageDescription`
- ✅ Android `ACCESS_BACKGROUND_LOCATION`
- ✅ Android `FOREGROUND_SERVICE_LOCATION`
- ✅ `react-native-background-actions` for notifications

No additional manifest/plist changes needed for MFC-App.

---

## Use-case matrix

| App type | SDK mode | App adds |
|----------|----------|----------|
| Run / Walk tracker | `fitness` + MotionEngine | Map, Realm, HealthKit |
| Cycling | `navigation` or `fitness` | Higher speed thresholds in app |
| Hiking | `balanced` + barometer | Elevation from HealthKit |
| Logistics / delivery | `navigation` | Server sync, geofences |
| Low power walk | `low_power` | Longer distanceFilter |
