# Migration from @react-native-community/geolocation

`react-native-fitness-geolocation` is designed as a **drop-in replacement** for most apps.

## Install

```bash
npm uninstall @react-native-community/geolocation
npm install react-native-fitness-geolocation
cd ios && pod install
```

## Import change

```javascript
// Before
import Geolocation from '@react-native-community/geolocation';

// After
import Geolocation from 'react-native-fitness-geolocation';
```

No other code changes required for basic usage.

## API compatibility

| API | Supported | Notes |
|-----|-----------|-------|
| `getCurrentPosition` | ✅ | + native `maximumAge`, JS `timeout` |
| `watchPosition` | ✅ | + SQLite background replay |
| `clearWatch` | ✅ | |
| `stopObserving` | ✅ | |
| `requestAuthorization` | ✅ | Extended: `'whenInUse'` \| `'always'` Promise overload |
| `setRNConfiguration` | ✅ | `skipPermissionRequests`, `authorizationLevel` |
| `PositionError` codes 1–3 | ✅ | Export `PositionError` from package |

## Options matrix

| Option | Community | This package |
|--------|-----------|--------------|
| `timeout` | ✅ | ✅ JS layer |
| `maximumAge` | ✅ | ✅ native |
| `enableHighAccuracy` | ✅ | ✅ |
| `distanceFilter` | ✅ iOS | ✅ iOS + Android |
| `interval` | Android | ✅ Android |
| `fastestInterval` | Android | ✅ Android |
| `activityType` | iOS | ✅ iOS |
| `pausesLocationUpdatesAutomatically` | iOS | ✅ iOS |
| `showsBackgroundLocationIndicator` | iOS | ✅ iOS |
| `useSignificantChanges` | iOS | 🚧 typed, not implemented |
| `forceRequestLocation` | Android | 🚧 typed, not implemented |
| `trackingMode` | — | ✅ extension |
| `enableMotion` | — | ✅ extension (opt-in) |

## Behavioral differences (intentional)

### 1. Background SQLite queue

When the app is backgrounded, native code **continues GPS** and stores points in SQLite. On foreground, queued points are delivered to active `watchPosition` callbacks.

This fixes the #1 fitness app bug: gaps in routes when the screen locks.

### 2. Motion is opt-in

Community geolocation has no motion APIs. This package adds `enableMotion: true` on `watchPosition` or the optional `FitnessEngine` — **not enabled by default**, so generic apps behave like community geolocation.

### 3. `react-native-geolocation-service` users

If you used `react-native-geolocation-service` for permissions on iOS:

```javascript
import Geolocation, { PermissionManager } from 'react-native-fitness-geolocation';

await PermissionManager.requestForeground();
Geolocation.getCurrentPosition(success, error);
```

## TypeScript

Types are exported from the package:

```typescript
import Geolocation, {
  GeolocationResponse,
  GeolocationOptions,
  PositionError,
} from 'react-native-fitness-geolocation';
```

## Expo

Requires a **development build** (custom dev client). Add permissions via `app.json` / config plugin manually — see [SETUP.md](./SETUP.md).

## New Architecture

Classic bridge today. TurboModule support planned — track [GitHub issues](https://github.com/Arslankhan9000/react-native-fitness-geolocation/issues).
