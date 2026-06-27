# Policy Mapping (2026+)

## iOS
- **iOS 16.1+** required for Live Activities (`ActivityKit`, `WidgetKit`).
- Background location requires correct `Info.plist` keys and user consent.

## Android
- **Android 9+ (API 28)** baseline.
- Foreground Service policy: tracking runs via a foreground service where required.
- Android 13+ requires runtime **notification permission** (`POST_NOTIFICATIONS`) for FGS notifications.
- OEM battery optimizations vary by manufacturer; Health API surfaces this risk.

