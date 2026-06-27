# Activity Profiles

Profiles are **default strategy presets** used by the vNext routing layer.

- Implemented in `src/profiles/ActivityProfiles.ts`
- Applied automatically by `ActivityManager.start()` (unless overridden explicitly)

## Built-in profiles
- `running`
- `walking`
- `hiking`
- `cycling`
- `driving`
- `fleet`

## Why profiles
- Avoid scattering “magic numbers” (intervals, accuracy thresholds, auto-pause) across code.
- Make it safe to add new strategies without breaking existing apps.

