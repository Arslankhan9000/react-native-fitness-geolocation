# AI Agent Context — @micim/geo

> Read this first when working on the geo SDK or MFC-App activity tracking.

## Package

| Field | Value |
|-------|-------|
| npm name | `@micim/geo` |
| Path | `packages/micim-geo/` |
| Native module | `MicimGeolocation` (internal, unchanged) |
| Version | 2.0.0 |

## MFC-App toggle (minimal integration)

```javascript
// MFC-App/src/config/geolocation.config.js
export const USE_MICIM_GEO = false; // true = @micim/geo, false = legacy community geolocation
```

| File | Role |
|------|------|
| `src/config/geolocation.config.js` | Single boolean toggle |
| `src/utils/geolocationProvider.js` | Routes to legacy or SDK |
| `LocationTrackingService.js` | Uses `getTrackingGeolocation()` — unchanged logic |
| `LocationService.js` | Uses `getPermissionGeolocation()` — unchanged logic |

**Do not** import `@micim/geo` directly in app files — always go through `geolocationProvider.js`.

## Docs

- [docs/AI_CONTEXT.md](./docs/AI_CONTEXT.md) — full technical reference
- [docs/PRODUCTION.md](./docs/PRODUCTION.md) — production guide
- [docs/PUBLISH.md](./docs/PUBLISH.md) — npm publish
- [docs/SETUP.md](./docs/SETUP.md) — platform config

## Publish

Standalone git repo in `packages/micim-geo/`. See [docs/PUBLISH.md](./docs/PUBLISH.md).
