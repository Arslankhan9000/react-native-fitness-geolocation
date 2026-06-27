# Modular Subsystem Imports

## Simple install (default)

```bash
yarn add react-native-fitness-geolocation
```

```ts
import Geolocation, { Pedometer, Geofencing, ActivityManager } from 'react-native-fitness-geolocation';
```

**One package, everything included** — same as before. Subpaths are optional for bundle size.

## Optional subpath imports

| Subsystem | Import | Lifecycle |
|-----------|--------|-----------|
| Core | `react-native-fitness-geolocation/core` | Permissions, types, config |
| Geolocation | `react-native-fitness-geolocation/geolocation` | `Geolocation.watchPosition` / `stopObserving` |
| Pedometer | `react-native-fitness-geolocation/pedometer` | `Pedometer.start` / `stop` (no GPS) |
| Geofence | `react-native-fitness-geolocation/geofence` | Geofencing + Spatial |
| Activity | `react-native-fitness-geolocation/activity` | ActivityManager sessions |
| Sync | `react-native-fitness-geolocation/sync` | HttpSync, SyncEngine |
| Diagnostics | `react-native-fitness-geolocation/diagnostics` | DebugMonitor, Health |

**Backward compatible:** `import Geolocation from 'react-native-fitness-geolocation'` still works.

## Examples

```ts
// Pedometer-only app (no GPS imports in JS bundle)
import { Pedometer, PedometerMetrics } from 'react-native-fitness-geolocation/pedometer';

// GPS-only app
import { Geolocation } from 'react-native-fitness-geolocation/geolocation';

// Combined — separate lifecycles
import { Geolocation } from 'react-native-fitness-geolocation/geolocation';
import { Pedometer } from 'react-native-fitness-geolocation/pedometer';

await Pedometer.start();
await Geolocation.ready({ geolocation: { /* … */ } });
// … workout uses GPS; daily steps use Pedometer only
```

## Native linking (honest limits)

| Layer | Subpath tree-shaking |
|-------|----------------------|
| **JavaScript** | Yes — Metro/webpack resolve only imported subpaths |
| **Native iOS/Android** | Single module today — all native code links via one pod/gradle project |

Native optional feature flags (e.g. `FitnessGeolocation/PedometerOnly`) are planned; JS modular imports ship now without breaking current consumers.

## Design rules

1. **Separate lifecycles** — `Pedometer.stop()` does not call `Geolocation.stopObserving()`.
2. **Composable** — ActivityManager can use GPS + pedometer together when you import both.
3. **Pure metrics** — `PedometerMetrics` is JS-only math (no native dependency).

See also: [PEDOMETER.md](./PEDOMETER.md), [PEDOMETER_METRICS.md](./PEDOMETER_METRICS.md).
