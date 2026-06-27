# Configuration (Compound Config Groups)

FitnessGeolocation supports **Transistorsoft-style compound configuration** passed from your app to the SDK.

You can supply options either:

- **Flat** (legacy / convenience): `url`, `distanceFilter`, `debug`, ...
- **Compound groups** (preferred): `geolocation`, `http`, `activity`, `persistence`, `app`, `logger`

Compound groups are **normalized** into the existing flat config before being sent to native.

## Example

```typescript
import BackgroundGeolocation, { LogLevel } from 'react-native-fitness-geolocation';

await BackgroundGeolocation.ready({
  geolocation: {
    distanceFilter: 10,
    authorizationLevel: 'always',
  },
  http: {
    url: 'https://example.com/locations',
    headers: { Authorization: 'Bearer token' },
    batchSize: 200,
  },
  persistence: {
    maxDaysToPersist: 14,
  },
  app: {
    startOnReady: true,
    stopOnTerminate: false,
    notificationTitle: 'Fitness Tracking',
  },
  activity: {
    trackingMode: 'fitness',
    includePedometer: true,
  },
  logger: {
    debug: true,
    logLevel: LogLevel.Verbose,
    logMaxDays: 7,
  },
});
```

## Precedence rules

- Nested group keys **override** root keys when both are provided.
  - Example: `http.url` overrides root `url`.
- Nested group objects are removed before sending to native — native receives a **flat** map.

## Supported groups

- `geolocation`: `GeolocationOptions` + `GeolocationConfiguration`
- `http`: `HttpConfig`
- `activity`: activity/motion-related toggles (subset)
- `persistence`: location retention (`maxDaysToPersist`)
- `app`: lifecycle + notification labels (subset)
- `logger`: debug UX + native log retention/verbosity (see `docs/DEBUGGING.md`)

