# Pedometer Metrics — Science & Formulas

Pure TypeScript physiology pipeline for `PedometerMetrics.compute()`.

## References

| Topic | Source |
|-------|--------|
| MET values | Ainsworth BE et al. (2011) *Compendium of Physical Activities* |
| Cadence ↔ intensity | Tudor-Locke C et al. (2018) cadence thresholds in adults |
| Energy expenditure | ACSM: `kcal/min = (MET × 3.5 × kg) / 200` |
| Weekly targets | WHO (2020) 150 min moderate-equivalent / week |
| Heart Points | Google Fit mapping (1 min moderate = 1 HP, vigorous = 2 HP) |
| Stride length | Anthropometric ≈ 0.414 × height (walking) |

## Pipeline

```
steps + duration + profile (mass, height, sex)
    → cadence (spm) = steps / minutes
    → stride (m) ≈ factor × height [+ speed adjustment]
    → distance (m) = measured || steps × stride
    → speed (m/s) = distance / time
    → MET = f(speed) Compendium interpolation, else f(cadence)
    → gross kcal = MET × kg × hours × 1.05 (ACSM)
    → net kcal = gross − resting (1 MET)
    → Heart Points = active_minutes × (1 or 2 by MET band)
```

## API

```ts
import { Pedometer, PedometerMetrics } from 'react-native-fitness-geolocation/pedometer';

const snap = await Pedometer.getSnapshot();

const metrics = PedometerMetrics.fromStepEvent(snap, {
  massKg: 72,
  heightM: 1.78,
  sex: 'male',
});

console.log(metrics.heartPoints, metrics.netKcal, metrics.met, metrics.intensityBand);
```

## Intensity bands

| Band | MET | Cadence hint | Heart Points / min |
|------|-----|--------------|------------------|
| Sedentary | &lt; 2 | &lt; 60 spm | 0 |
| Light | 2–2.9 | 60–99 spm | 0 |
| Moderate | 3–6 | ≥ 100 spm | 1 |
| Vigorous | &gt; 6 | ≥ 130 spm | 2 |

## Extensibility

- `ageYears` reserved for HR-zone / max-HR models (Karvonen)
- Optional HealthKit energy comparison in future
- Native CMPedometer `distance` preferred over stride model when available
