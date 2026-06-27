# Debugging & Logger Configuration

FitnessGeolocation follows the same **client → SDK → native** config pattern as Transistorsoft Background Geolocation.

## Quick start (development only)

```typescript
import BackgroundGeolocation, { LogLevel } from 'react-native-fitness-geolocation';

await BackgroundGeolocation.ready({
  logger: {
    debug: true,              // sound + vibration + debug notifications
    logLevel: LogLevel.Verbose,
    logMaxDays: 7,
    sound: true,
    vibration: true,
    feedbackThrottleMs: 1500,
  },
  startOnReady: true,
});
```

Legacy root flag still works:

```typescript
await BackgroundGeolocation.ready({ debug: true });
```

## Config groups

| Key | Purpose |
|-----|---------|
| `logger.debug` | Enables DebugMonitor (audible + notification feedback). **Not for production.** |
| `logger.logLevel` | SQLite native log verbosity (`Off` … `Verbose`) |
| `logger.logMaxDays` | Retention for `native_logs` table |
| `logger.sound` / `vibration` | Fine-tune debug feedback |
| `logger.feedbackThrottleMs` | Debounce repeated sounds per event |
| `logger.notificationDebounceMs` | Debounce Android FGS notification text updates |

`logLevel` and `debug` are independent (same as Transistorsoft):

- `debug: true` → lifecycle sound/vibration/notifications
- `logLevel` → what gets written to the on-device log database

## Log levels

```typescript
LogLevel.Off      // 0 — no persistence
LogLevel.Error    // 1
LogLevel.Warning  // 2
LogLevel.Info     // 3
LogLevel.Debug    // 4
LogLevel.Verbose  // 5
```

## Logger API

```typescript
import { Logger } from 'react-native-fitness-geolocation';
// or: BackgroundGeolocation.logger

await Logger.error('something failed');
const text = await Logger.getLog({ limit: 500 });
await Logger.emailLog('support@example.com');
await Logger.destroyLog();
```

## Runtime updates

```typescript
await BackgroundGeolocation.setConfig({
  logger: { logLevel: LogLevel.Info, debug: false },
});
```

`setConfig` and `ready` both route through `applyLoggerConfig()` on the JS layer and `configureLogger` on native.
