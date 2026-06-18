# react-native-fitness-geolocation

Production-grade React Native GPS for **fitness and activity tracking** apps — background location, native SQLite persistence, and optional motion auto-pause.

Drop-in replacement for `@react-native-community/geolocation` with extensions for Strava/Nike-class reliability.

```bash
npm install react-native-fitness-geolocation
cd ios && pod install
```

## Platform support

| Feature | iOS | Android |
|---------|-----|---------|
| `getCurrentPosition` / `watchPosition` | ✅ | ✅ |
| Background GPS + SQLite queue | ✅ | ✅ |
| Foreground queue replay | ✅ | ✅ |
| Watch restore after app restart | ✅ | ✅ |
| `distanceFilter`, `interval`, `maximumAge` | ✅ | ✅ |
| Motion auto-pause (`MotionEngine`) | ✅ | 🚧 scaffold |
| `CLBackgroundActivitySession` (iOS 17+) | ✅ | — |

## Quick start

```javascript
import Geolocation from 'react-native-fitness-geolocation';

// One-shot location (map pin, start screen)
Geolocation.getCurrentPosition(
  position => console.log(position.coords),
  error => console.warn(error),
  { enableHighAccuracy: true, timeout: 15000, maximumAge: 10000 },
);

// Continuous tracking (run / ride / hike)
const watchId = Geolocation.watchPosition(
  position => saveRoutePoint(position),
  error => console.warn(error),
  {
    enableHighAccuracy: true,
    distanceFilter: 5,
    interval: 3000,
    fastestInterval: 1000,
    showsBackgroundLocationIndicator: true, // iOS
  },
);

// Stop
Geolocation.clearWatch(watchId);
```

## Permissions

Use built-in helpers or your own flow:

```javascript
import { PermissionManager } from 'react-native-fitness-geolocation';

const result = await PermissionManager.requestFitnessPermissions({
  includeMotion: true, // Android ACTIVITY_RECOGNITION
});

if (result.status !== 'ready') {
  await PermissionManager.openSettings();
}
```

Or configure once (community-geolocation compatible):

```javascript
Geolocation.setRNConfiguration({
  skipPermissionRequests: false,
  authorizationLevel: 'always', // fitness apps
});
```

## Background tracking

GPS continues in the background. Points collected while JS is suspended are stored in **native SQLite** and replayed when the app returns to foreground — no data loss on lock screen.

```javascript
// Manual sync (usually automatic via AppState)
const count = await Geolocation.syncPendingLocations();
console.log(`Delivered ${count} queued points`);
```

**Required setup:** See [docs/SETUP.md](./docs/SETUP.md) for Info.plist and AndroidManifest snippets.

Verify your app:

```bash
npx react-native-fitness-geolocation verify-setup
```

## Fitness apps (optional layer)

For full workout orchestration — permissions + GPS + motion + auto-pause:

```javascript
import { createFitnessEngine } from 'react-native-fitness-geolocation';

const engine = createFitnessEngine({ autoPause: true, includePedometer: false });

await engine.prepare();
engine.start(
  position => onLocation(position),
  error => onError(error),
  { trackingMode: 'fitness' },
);

// Later
engine.stop();
```

`FitnessEngine` is optional. Plain `Geolocation.watchPosition` works for any app.

## Migration from @react-native-community/geolocation

```diff
- import Geolocation from '@react-native-community/geolocation';
+ import Geolocation from 'react-native-fitness-geolocation';
```

Same API: `getCurrentPosition`, `watchPosition`, `clearWatch`, `requestAuthorization`, `setRNConfiguration`.

See [docs/MIGRATION.md](./docs/MIGRATION.md) for options matrix and edge cases.

## API reference

### Geolocation (default export)

| Method | Description |
|--------|-------------|
| `getCurrentPosition(success, error?, options?)` | Single fix with `timeout`, `maximumAge` |
| `watchPosition(success, error?, options?)` → `number` | Continuous updates |
| `clearWatch(id)` | Stop one watch |
| `stopObserving()` | Stop all watches |
| `requestAuthorization(level?)` | `'whenInUse'` \| `'always'` |
| `getAuthorizationStatus()` | `{ status, always }` |
| `setRNConfiguration(config)` | Global config |
| `syncPendingLocations()` | Drain SQLite queue to callbacks |
| `getQueueSize()` | Pending point count |
| `addAuthorizationListener(cb)` | Permission change events |

### Options (`GeolocationOptions`)

| Option | Default | Notes |
|--------|---------|-------|
| `timeout` | 15000 | ms, emits error code `3` |
| `maximumAge` | 0 | Accept cached fix if younger (ms) |
| `enableHighAccuracy` | true | |
| `distanceFilter` | 5 | meters |
| `interval` | 3000 | Android update interval (ms) |
| `fastestInterval` | 1000 | Android min interval (ms) |
| `trackingMode` | — | `fitness` \| `navigation` \| `balanced` \| `low_power` |
| `enableMotion` | false | Opt-in motion engine with watch |

### Error codes (`PositionError`)

| Code | Constant | Meaning |
|------|----------|---------|
| 1 | `PERMISSION_DENIED` | User denied location |
| 2 | `POSITION_UNAVAILABLE` | GPS unavailable |
| 3 | `TIMEOUT` | Request timed out |

## Android background note

For long sessions with the screen off, Android may require a **foreground service** with a persistent notification (OS policy). This package persists GPS natively; pair with a foreground service library for best results on Android 12+. See [docs/SETUP.md](./docs/SETUP.md).

## Docs

| Doc | Description |
|-----|-------------|
| [docs/SETUP.md](./docs/SETUP.md) | Platform permissions |
| [docs/MIGRATION.md](./docs/MIGRATION.md) | From community geolocation |
| [docs/PRODUCTION.md](./docs/PRODUCTION.md) | Production checklist |
| [docs/PUBLISH.md](./docs/PUBLISH.md) | npm publish |

## Requirements

- React Native ≥ 0.73
- iOS 13+ (iOS 17+ for background activity session)
- Android API 24+
- Bare workflow or Expo dev client (native module)

MIT · [Arslan Khan](https://github.com/Arslankhan9000)
