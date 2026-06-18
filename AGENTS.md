# AI Agent Context — react-native-fitness-geolocation

> Read this first when working on the geo SDK or MFC-App activity tracking.

## Package

| Field | Value |
|-------|-------|
| npm name | `react-native-fitness-geolocation` |
| Path | `packages/react-native-fitness-geolocation/` |
| Native module | `FitnessGeolocation` |
| Version | 2.0.0 |

## MFC-App toggle (minimal integration)

```javascript
// MFC-App/src/config/geolocation.config.js
export const USE_FITNESS_GEO = false; // true = react-native-fitness-geolocation, false = legacy community geolocation
```

| File | Role |
|------|------|
| `src/config/geolocation.config.js` | Single boolean toggle |
| `src/utils/geolocationProvider.js` | Routes to legacy or SDK |
| `LocationTrackingService.js` | Uses `getTrackingGeolocation()` — unchanged logic |
| `LocationService.js` | Uses `getPermissionGeolocation()` — unchanged logic |

**Do not** import `react-native-fitness-geolocation` directly in app files — always go through `geolocationProvider.js`.

## Docs

- [docs/AI_CONTEXT.md](./docs/AI_CONTEXT.md) — full technical reference
- [docs/PRODUCTION.md](./docs/PRODUCTION.md) — production guide
- [docs/PUBLISH.md](./docs/PUBLISH.md) — npm publish
- [docs/SETUP.md](./docs/SETUP.md) — platform config

## Publish

Standalone git repo in `packages/react-native-fitness-geolocation/`. See [docs/PUBLISH.md](./docs/PUBLISH.md).
