# AI Agent Context — react-native-fitness-geolocation

> Read this first when working on the geo SDK or **lifeTracker** activity recording.

## Package

| Field | Value |
|-------|-------|
| npm name | `react-native-fitness-geolocation` |
| Path | `packages/react-native-fitness-geolocation/` |
| Native module | `FitnessGeolocation` |
| Version | 2.0.0 |

## lifeTracker integration

| File | Role |
|------|------|
| `lifeTracker/src/services/TrackingSession.ts` | Persistent GPS session, background service, live stream |
| `lifeTracker/src/services/RealmLocationStore.ts` | Batched Realm writes for location points |
| `lifeTracker/src/services/PermissionService.ts` | Permission education flow + fitness-geolocation engine |
| `lifeTracker/src/screens/record/RecordScreen.tsx` | Record tab — map, HUD, start/stop |
| `lifeTracker/src/components/TrackMap.tsx` | Map + polyline UI |

lifeTracker imports the SDK directly:

```typescript
import Geolocation from 'react-native-fitness-geolocation';
```

## Docs

- [docs/AI_CONTEXT.md](./docs/AI_CONTEXT.md) — full technical reference
- [docs/PRODUCTION.md](./docs/PRODUCTION.md) — production guide
- [docs/PUBLISH.md](./docs/PUBLISH.md) — npm publish
- [docs/SETUP.md](./docs/SETUP.md) — platform config

## Publish

Standalone git repo in `packages/react-native-fitness-geolocation/`. See [docs/PUBLISH.md](./docs/PUBLISH.md).
