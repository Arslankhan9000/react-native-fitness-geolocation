# Changelog

## 2.0.0

### Public release — general-purpose fitness geolocation

- Drop-in API compatible with `@react-native-community/geolocation`
- iOS: CoreLocation engine, LocationFilter, SQLite write-first, iOS 17 background activity session
- Android: Fused Location, SQLite queue, option parsing, runtime permissions, watch restore
- JS: AppState foreground drain, timeout support, `setRNConfiguration`, `PositionError` export
- Optional `FitnessEngine`, `MotionEngine`, `PermissionManager` for workout apps
- Motion tracking opt-in via `enableMotion` (not auto-started on every watch)
- `npx react-native-fitness-geolocation verify-setup` CLI
