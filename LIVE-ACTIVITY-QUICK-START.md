# Live Activity - Quick Start Guide

## 30-Second Setup ⚡

### 1. Check Support
```typescript
const supported = await FitnessGeolocation.isLiveActivitySupported();
```

### 2. Enable
```typescript
await FitnessGeolocation.setLiveActivityEnabled(true);
```

### 3. Start Workout
```typescript
const session = await FitnessGeolocation.createSession({
  name: 'Morning Run',
  activityType: 'running',
});

const watchId = await FitnessGeolocation.startTimeBasedTracking({
  intervalMs: 3000,
});
```

**That's it!** Live Activity now shows and updates automatically.

---

## What You Get 🎁

### iOS
- **Lock Screen widget** with real-time metrics
- **Dynamic Island** (iPhone 14 Pro+)
- Updates every 3 seconds
- Survives JS reload

### Android
- **Persistent notification** with custom layout
- **Collapsed + Expanded views**
- Updates every 3 seconds
- Survives JS reload

---

## Features Displayed 📊

- Distance (km/mi)
- Duration (HH:MM:SS)
- Pace (min/km or min/mi)
- GPS Status (🟢🟡🔴)
- Calories
- Heart Rate (optional)
- Pause indicator

---

## Common Code 💻

### Complete Workout Flow
```typescript
import FitnessGeolocation from 'react-native-fitness-geolocation';

// Setup (once on app init)
const setupLiveActivity = async () => {
  const supported = await FitnessGeolocation.isLiveActivitySupported();
  if (supported) {
    await FitnessGeolocation.setLiveActivityEnabled(true);
  }
};

// Start Workout
const startWorkout = async () => {
  const session = await FitnessGeolocation.createSession({
    name: 'Morning Run',
    activityType: 'running', // 'running' | 'cycling' | 'walking'
  });

  const watchId = await FitnessGeolocation.startTimeBasedTracking({
    intervalMs: 3000,
    adaptiveInterval: true,
  });

  return { session, watchId };
};

// Stop Workout
const stopWorkout = async (session, watchId) => {
  await FitnessGeolocation.stopTimeBasedTracking(watchId);
  
  await FitnessGeolocation.endSession(session.id, {
    totalDistance: 5234.5,
    totalDuration: 1845000,
    calories: 423,
  });
};
```

### Settings Toggle
```typescript
function SettingsScreen() {
  const [enabled, setEnabled] = useState(false);

  useEffect(() => {
    FitnessGeolocation.isLiveActivityEnabled().then(setEnabled);
  }, []);

  const toggle = async (value) => {
    await FitnessGeolocation.setLiveActivityEnabled(value);
    setEnabled(value);
  };

  return (
    <Switch 
      value={enabled} 
      onValueChange={toggle}
      label="Show Live Activity" 
    />
  );
}
```

---

## Platform Setup 🔧

### iOS (Xcode Required)

1. **Add to Info.plist:**
```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

2. **Done!** Widget Extension code is included in the package.

### Android (Automatic)

1. **Request notification permission** (Android 13+):
```typescript
if (Platform.OS === 'android' && Platform.Version >= 33) {
  await PermissionsAndroid.request(
    PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS
  );
}
```

2. **Done!** Layouts are included in the package.

---

## Troubleshooting 🔍

### Live Activity Not Showing

**iOS:**
```typescript
// Check iOS version
if (parseInt(Platform.Version) < 16) {
  console.log('Needs iOS 16.1+');
}

// Check if enabled
const enabled = await FitnessGeolocation.isLiveActivityEnabled();
console.log('Enabled:', enabled);
```

**Android:**
```typescript
// Check notification permission
import { PermissionsAndroid } from 'react-native';

const granted = await PermissionsAndroid.check(
  PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS
);
console.log('Permission:', granted);
```

### Updates Not Appearing

```typescript
// Verify tracking is active
const state = await FitnessGeolocation.getEngineState();
console.log('Time-based active:', state.timeBasedActive);

// Check session exists
console.log('Has session:', currentSessionId !== null);
```

---

## Key Points 📌

✅ **OFF by default** - User must enable

✅ **Automatic lifecycle** - No manual update calls needed

✅ **JS-independent** - Native updates continue when JS dies

✅ **Battery efficient** - ~1-2% overhead

✅ **No config required** - Works out-of-box

---

## API Reference 📚

```typescript
// Check support
isLiveActivitySupported(): Promise<boolean>

// Enable/disable
setLiveActivityEnabled(enabled: boolean): Promise<void>

// Check status
isLiveActivityEnabled(): Promise<boolean>
isLiveActivityActive(): Promise<boolean>
```

**Note:** Lifecycle is automatic via `createSession()` / `endSession()`.

---

## Full Documentation 📖

- **Complete Guide:** `LIVE-ACTIVITY-GUIDE.md`
- **Android Details:** `LIVE-ACTIVITY-ANDROID.md`
- **Implementation:** `LIVE-ACTIVITY-IMPLEMENTATION-COMPLETE.md`

---

## Support 💬

Issues? Check:
1. Platform version (iOS 16.1+ / Android 5.0+)
2. Live Activity enabled
3. Permissions granted
4. Session created before tracking
5. Logs: `adb logcat` (Android) / Xcode console (iOS)

---

**You're ready to go! 🚀**
