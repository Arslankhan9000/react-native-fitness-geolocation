# FitnessGeolocation vNext — Architecture

## Goals
- **Native-first**: iOS/Android engines own tracking; JS is control + consumption.
- **New Architecture-first**: TurboModule + codegen with classic bridge fallback.
- **Offline + reliability-first**: persist immediately; never depend on JS/network for correctness.
- **Science-first**: each algorithm module has documented purpose, formulas, complexity, limitations.

## Engine layout (current shipping)

```mermaid
flowchart TD
  RN[ReactNativeApp] -->|TurboModule typed| TM[FitnessGeolocationSpec]
  RN -->|Legacy fallback| LM[Classic bridge module]

  TM --> AE[ActivityEngine (JS facade)]
  LM --> AE

  subgraph nativeCore [Native Core]
    AE --> LE[LocationEngine]
    AE --> ME[MotionEngine]
    AE --> DB[Storage (SQLite)]
    AE --> GE[GeofenceEngine]
    AE --> DI[Diagnostics (timeline + logs)]
    AE --> SY[Sync (native HTTP)]
  end
```

## Compatibility rule
- Existing exports and behaviors remain intact.
- New capabilities ship under **new modules/new names** (`Tracking`, `Health`, `MetricsV2`, `Spatial`, `SyncEngine`, profiles).
- Internally, JS facades route to existing native methods so apps can adopt incrementally.

