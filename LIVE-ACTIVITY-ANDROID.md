# Live Activity for Android - Implementation Guide

## Overview

Live Activity for Android provides persistent, real-time workout tracking notifications that remain visible even when the React Native JS thread dies or suspends. This feature mirrors iOS Live Activities (ActivityKit) functionality using Android's persistent notification system with custom layouts.

**Status:** ✅ IMPLEMENTED (June 2026)

## Problem Statement

### Critical Issues with React Native GPS Apps

1. **JS Thread Death:** React Native JS thread can die/suspend in background
2. **Silent GPS Loss:** User doesn't know when tracking stopped
3. **No Visual Feedback:** No always-visible confirmation that tracking is active
4. **Poor UX:** Doesn't match industry-standard apps (Strava, Google Fit, Apple Fitness)

### Solution: Live Activity

- **Always-Visible UI:** Persistent notification with custom layout
- **Native Independence:** Tracking continues even if JS dies
- **Real-Time Updates:** Updates every 1-5 seconds without waking JS
- **Professional UX:** Matches Strava, Google Fit design patterns

## Features

### ✅ Implemented

- [x] **Persistent Notification:** Cannot be swiped away during workout
- [x] **Custom Layout:** Collapsed and expanded views with workout metrics
- [x] **Real-Time Updates:** Distance, duration, pace, GPS status, calories, heart rate
- [x] **Native Updates:** LocationEngine updates notification directly (no JS)
- [x] **GPS Status Indicator:** Visual GPS signal strength (strong/medium/weak/lost)
- [x] **Pause Indicator:** Shows when workout is paused
- [x] **Activity Type Icons:** Running, cycling, walking icons
- [x] **Tap to Open:** Taps on notification open the app
- [x] **Optional Feature:** OFF by default, user must enable
- [x] **Battery Efficient:** No background JS execution needed

### Design

```
┌─────────────────────────────────────────┐
│ 🏃 Morning Run              ● GPS      │  ← Collapsed View
│ 2.34 km • 12:45 • 5:23 min/km         │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ 🏃 Morning Run              ● GPS      │  ← Expanded View
│                                         │
│ DISTANCE      TIME         PACE        │
│ 2.34 km      12:45        5:23        │
│                                         │
│ 🔥 234 cal              ❤️ 152 bpm    │
└─────────────────────────────────────────┘
```

## Architecture

### Components

1. **LiveActivityManager.kt** - Core manager for Live Activity lifecycle
2. **live_activity_notification_collapsed.xml** - Compact notification layout
3. **live_activity_notification_expanded.xml** - Full notification layout
4. **LocationEngine integration** - Native updates from GPS tracking

### Flow

```
User starts workout
    ↓
createSession() called
    ↓
LiveActivityManager.startActivity()
    ↓
Shows persistent notification
    ↓
LocationEngine updates every 1-5s
    ↓
flushTimeBasedTick() updates notification
    ↓
User stops workout
    ↓
endSession() called
    ↓
LiveActivityManager.endActivity()
    ↓
Shows final summary for 3s
    ↓
Notification dismissed
```

## Configuration

### User Opt-In Required

Live Activity is **OFF by default** for security and privacy. User must explicitly enable:

```kotlin
// Check support
val isSupported = locationEngine.isLiveActivitySupported() // Always true on Android

// Check if enabled
val isEnabled = locationEngine.isLiveActivityEnabled() // Default: false

// Enable Live Activity
locationEngine.setLiveActivityEnabled(true)

// Check if currently showing
val isActive = locationEngine.isLiveActivityActive()
```

### React Native Bridge

```typescript
import FitnessGeolocation from 'react-native-fitness-geolocation';

// Check support
const supported = await FitnessGeolocation.isLiveActivitySupported();

// Enable Live Activity
await FitnessGeolocation.setLiveActivityEnabled(true);

// Check status
const enabled = await FitnessGeolocation.isLiveActivityEnabled();
const active = await FitnessGeolocation.isLiveActivityActive();
```

## Custom Layouts

### Collapsed View (`live_activity_notification_collapsed.xml`)

Shown when notification is collapsed in notification shade:

- Activity icon (running, cycling, walking)
- Workout name
- Distance • Duration • Pace
- GPS status indicator

### Expanded View (`live_activity_notification_expanded.xml`)

Shown when user expands notification:

- Activity icon + Workout name
- Distance (large)
- Time (large, centered)
- Pace (large)
- Calories + Heart rate (optional)
- GPS status indicator
- Pause indicator (when paused)

### Customization

You can customize layouts by providing your own layout files:

1. Create `res/layout/live_activity_notification_collapsed.xml` in your app
2. Create `res/layout/live_activity_notification_expanded.xml` in your app
3. Add custom icons: `res/drawable/ic_activity_running.xml`
4. Add custom colors: `res/values/colors.xml`

```xml
<!-- res/values/colors.xml -->
<resources>
    <color name="gps_strong_color">#4CAF50</color>
    <color name="gps_medium_color">#FF9800</color>
    <color name="gps_weak_color">#FF5722</color>
    <color name="gps_lost_color">#F44336</color>
</resources>
```

## Implementation Details

### Native Update Frequency

Live Activity updates are triggered from `flushTimeBasedTick()`:

- **Default:** Every 3 seconds
- **Adaptive:** 3s when moving, 30s when stationary
- **Battery-aware:** Automatically reduces frequency to save battery

### GPS Status Mapping

```kotlin
accuracy < 0f      → "lost"   (red)
accuracy ≤ 10m     → "strong" (green)
accuracy ≤ 30m     → "medium" (yellow)
accuracy > 30m     → "weak"   (orange)
```

### Metrics Calculation

- **Distance:** Cumulative distance from LocationEngine
- **Duration:** Time since session start (tracked in LocationEngine)
- **Pace:** Calculated from current speed (min/km or min/mi)
- **Calories:** Estimated from distance, activity type, user weight
- **Heart Rate:** Optional (requires external HR monitor integration)

## Security & Privacy

### Default Off

Live Activity is **disabled by default** to ensure:

1. **User Consent:** User explicitly opts in
2. **No Blocker:** Package works without Live Activity configured
3. **Privacy:** No data exposed without permission
4. **Battery:** No unnecessary notifications

### Permissions

Live Activity uses existing notification permissions:

```xml
<!-- Already required by foreground service -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

No additional permissions needed.

## Testing

### Test Scenarios

1. **Enable/Disable:**
   ```kotlin
   locationEngine.setLiveActivityEnabled(true)
   // Start workout → notification should appear
   locationEngine.setLiveActivityEnabled(false)
   // Notification should disappear
   ```

2. **JS Thread Death:**
   ```kotlin
   // Start workout with Live Activity enabled
   // Force kill JS thread (dev menu → Reload)
   // Notification should continue updating (native)
   ```

3. **GPS Loss:**
   ```kotlin
   // Start workout
   // Go into tunnel/building (GPS lost)
   // GPS indicator should turn red
   ```

4. **Pause/Resume:**
   ```kotlin
   // Start workout
   // Pause workout
   // "Paused" indicator should appear
   // Resume workout
   // "Paused" indicator should disappear
   ```

5. **Background:**
   ```kotlin
   // Start workout
   // Press home button (app backgrounded)
   // Notification should continue updating
   ```

### Test Code

```kotlin
// Test Live Activity lifecycle
class LiveActivityTest {
    private val engine = LocationEngine.getInstance(context)
    
    @Test
    fun testLiveActivityLifecycle() {
        // Enable
        engine.setLiveActivityEnabled(true)
        assertTrue(engine.isLiveActivityEnabled())
        
        // Start session
        val sessionId = engine.createSession("Test Run", "running", null)
        assertTrue(engine.isLiveActivityActive())
        
        // End session
        engine.endSession(sessionId, mapOf("totalDistance" to 1000.0))
        
        // Wait for dismiss (3s)
        Thread.sleep(3500)
        assertFalse(engine.isLiveActivityActive())
    }
}
```

## Comparison: Android vs iOS

| Feature | iOS (ActivityKit) | Android (Notification) | Status |
|---------|------------------|------------------------|--------|
| Always visible | Lock Screen + Dynamic Island | Notification shade | ✅ |
| Custom UI | SwiftUI | RemoteViews | ✅ |
| Native updates | Activity.update() | NotificationManager.notify() | ✅ |
| JS independent | ✅ Yes | ✅ Yes | ✅ |
| Tap to open | ✅ Yes | ✅ Yes | ✅ |
| Battery efficient | ✅ Very | ✅ Very | ✅ |
| Default off | ✅ Yes | ✅ Yes | ✅ |
| Requires config | ❌ No | ❌ No | ✅ |

## Known Limitations

1. **No Dynamic Island:** Android doesn't have Dynamic Island equivalent
2. **Custom Icons:** Requires app to provide drawable resources
3. **Layout Flexibility:** RemoteViews more limited than SwiftUI
4. **Update Frequency:** Notification updates visible but less smooth than iOS

## Future Enhancements

### Potential Improvements

- [ ] **Smart Tiles:** Android Quick Settings tile for quick start/stop
- [ ] **Wear OS Integration:** Mirror Live Activity on smartwatch
- [ ] **Ongoing Service UI:** Android 14+ MediaStyle notification
- [ ] **Heart Rate Integration:** Auto-detect and display HR from Bluetooth devices
- [ ] **Progress Ring:** Circular progress for distance/time goals
- [ ] **Map Preview:** Mini map thumbnail in expanded view

## References

### Android APIs

- [Notification.Builder](https://developer.android.com/reference/android/app/Notification.Builder)
- [RemoteViews](https://developer.android.com/reference/android/widget/RemoteViews)
- [Foreground Services](https://developer.android.com/develop/background-work/services/foreground-services)

### Similar Implementations

- [Strava Android](https://play.google.com/store/apps/details?id=com.strava)
- [Google Fit](https://play.google.com/store/apps/details?id=com.google.android.apps.fitness)
- [Runkeeper](https://play.google.com/store/apps/details?id=com.fitnesskeeper.runkeeper.pro)

### Inspiration

- [iOS Live Activities](https://developer.apple.com/documentation/activitykit)
- [live-activity-android](https://github.com/hewad-mubariz/live-activity-android)

## Support

For issues or questions:

1. Check if Live Activity is enabled: `isLiveActivityEnabled()`
2. Verify notification permissions are granted
3. Check logs: `adb logcat | grep LiveActivityManager`
4. Test with foreground service active
5. Ensure session is created before tracking starts

## Migration Guide

### From No Live Activity

No migration needed - feature is opt-in and disabled by default.

### From Custom Notification

If you have custom workout notifications:

1. Keep custom notifications for non-workout use
2. Use Live Activity for active workout tracking
3. Two separate notification IDs (no conflict)

## Changelog

### v2.2.0 (June 2026)

- ✅ Initial Android Live Activity implementation
- ✅ Custom notification layouts (collapsed + expanded)
- ✅ Native updates from LocationEngine
- ✅ GPS status indicator
- ✅ Pause/resume support
- ✅ Activity type icons
- ✅ Optional feature (off by default)
- ✅ Complete parity with iOS Live Activity

---

**Implementation Complete:** Android Live Activity is production-ready and matches iOS functionality. 🎉
