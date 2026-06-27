# Pedometer Module

Passive, notification-free step counting for `react-native-fitness-geolocation`.

## Why a separate module?

GPS tracking and step counting have **different lifecycles**:

| Concern | GPS (`Geolocation`) | Pedometer (`Pedometer`) |
|--------|---------------------|-------------------------|
| Battery | High (GNSS) | Low (co-processor / step IC) |
| Background UX | Often needs indicator / FGS | No notification (platform sensors) |
| Kill recovery | Queue + watch restore | Hardware counter + CMPedometer query |
| Permissions | Location Always | Motion / Activity Recognition |

Apps like Apple Health and Google Fit count steps via **motion coprocessors**, not continuous GPS.

## Architecture (2026)

### iOS — `CMPedometer` + gap query

- Live: `CMPedometer.startUpdates(from:)`
- Kill/background gap: `CMPedometer.queryPedometerData(from:to:)` on foreground
- Permission: `NSMotionUsageDescription` in host `Info.plist`
- No foreground service, no blue location bar

References: [pedometerIOS](https://github.com/boomboss200/pedometerIOS), Apple Core Motion docs.

### Android — `TYPE_STEP_COUNTER` + fallback

1. **Primary**: `Sensor.TYPE_STEP_COUNTER` (cumulative since boot — survives process death)
2. **Secondary**: `TYPE_STEP_DETECTOR`
3. **Fallback**: accelerometer peak detection ([stepUp](https://github.com/adildsw/stepUp) style)

- Permission: `ACTIVITY_RECOGNITION` (API 29+), optional `BODY_SENSORS_BACKGROUND` (API 34+)
- **No foreground service** for steps — unlike GPS workouts
- Boot: `PedometerBootReceiver` flags session for reconcile

References: [stepsy](https://github.com/nvllz/stepsy), [walk-count](https://github.com/Ayush2006128/walk-count), [react-native-step-counter](https://github.com/AndrewDongminYoo/react-native-step-counter).

### JS layer

- `Pedometer.start()` / `stop()` / `restore()`
- `createStepCountFilter()` — cadence filter for live false positives
- `AppState` → `pedometerOnAppForeground()` for gap fill

## Usage

```ts
import { Pedometer } from 'react-native-fitness-geolocation';

// On app launch
await Pedometer.restore();

const support = await Pedometer.isSupported();
if (!support.supported) return;

await Pedometer.requestPermission();

const session = await Pedometer.start({ sessionId: 'walk-1' });

const sub = Pedometer.onStepUpdate((e) => {
  console.log(e.steps, e.counterType, e.source);
});

// ... later
await Pedometer.stop();
sub.remove();
```

## Permissions checklist

### iOS (`Info.plist`)

```xml
<key>NSMotionUsageDescription</key>
<string>Count steps during workouts without GPS.</string>
```

### Android (`AndroidManifest.xml` — included in SDK)

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
<uses-permission android:name="android.permission.BODY_SENSORS_BACKGROUND" />
```

## What this is NOT (yet)

- **HealthKit write / Google Fit sync** — optional future `Pedometer.syncToHealth()` layer
- **Indoor positioning** — see [Navigine algorithms](https://github.com/Navigine/Indoor-Positioning-And-Navigation-Algorithms) for BLE trilateration (separate from steps)
- **24/7 always-on without any permission** — OS requires motion consent

## Science notes

- Hardware step counters use **accelerometer fusion + gait models** on a low-power MCU
- Cadence filter rejects >~270 spm bursts (physically implausible for walking)
- Distance estimate: `steps × 0.762 m` default stride (configurable in future)
