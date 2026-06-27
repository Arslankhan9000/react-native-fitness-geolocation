import { Platform } from 'react-native';
import type { HealthIssue, HealthRecommendation } from '../types';
import { OEMBatteryManager } from '../OEMBatteryManager';
import { ProviderEvents } from '../ProviderEvents';
import { callNative, getPedometerNative } from './nativeBridge';
import { PedometerPermission } from './PedometerPermission';

export interface PedometerDiagnostics {
  manufacturer: string;
  model: string;
  platform: string;
  counterType: string;
  isRunning: boolean;
  hasStepCounter: boolean;
  hasStepDetector: boolean;
  hasAccelerometerFallback: boolean;
  oemRestrictionLevel: 'none' | 'moderate' | 'aggressive' | string;
  oemAggressiveBackground: boolean;
  oemSettingsLabel: string | null;
  oemPedometerNote: string | null;
  batteryOptimizationExempt?: boolean;
  powerSaveMode?: boolean;
  sessionSteps: number;
}

export interface PedometerHealthResult {
  score: number;
  issues: HealthIssue[];
  recommendations: HealthRecommendation[];
  diagnostics: PedometerDiagnostics | null;
  support: Awaited<ReturnType<typeof PedometerPermission.getSupport>>;
}

async function readDiagnostics(): Promise<PedometerDiagnostics | null> {
  if (!getPedometerNative()?.pedometerGetDiagnostics) return null;
  try {
    const raw = await callNative<Record<string, unknown>>('pedometerGetDiagnostics', {}, n =>
      (n as { pedometerGetDiagnostics?: () => Promise<Record<string, unknown>> }).pedometerGetDiagnostics!(),
    );
    return {
      manufacturer: String(raw.manufacturer ?? 'unknown'),
      model: String(raw.model ?? 'unknown'),
      platform: String(raw.platform ?? Platform.OS),
      counterType: String(raw.counterType ?? 'unknown'),
      isRunning: raw.isRunning === true,
      hasStepCounter: raw.hasStepCounter === true,
      hasStepDetector: raw.hasStepDetector === true,
      hasAccelerometerFallback: raw.hasAccelerometerFallback === true,
      oemRestrictionLevel: String(raw.oemRestrictionLevel ?? 'none'),
      oemAggressiveBackground: raw.oemAggressiveBackground === true,
      oemSettingsLabel: raw.oemSettingsLabel != null ? String(raw.oemSettingsLabel) : null,
      oemPedometerNote: raw.oemPedometerNote != null ? String(raw.oemPedometerNote) : null,
      batteryOptimizationExempt: raw.batteryOptimizationExempt === true,
      powerSaveMode: raw.powerSaveMode === true,
      sessionSteps: Number(raw.sessionSteps ?? 0),
    };
  } catch {
    return null;
  }
}

/**
 * OEM-aware pedometer health — surfaces manufacturer restrictions that block
 * background step delivery (MIUI, EMUI, ColorOS, Samsung Device Care, etc.).
 */
export const PedometerHealth = {
  async getHealth(): Promise<PedometerHealthResult> {
    const [support, diagnostics, powerSave, oemInfo] = await Promise.all([
      PedometerPermission.getSupport(),
      readDiagnostics(),
      ProviderEvents.isPowerSaveMode().catch(() => false),
      Platform.OS === 'android' ? OEMBatteryManager.getInfo() : null,
    ]);

    const issues: HealthIssue[] = [];
    const recommendations: HealthRecommendation[] = [];

    if (!support.supported) {
      issues.push({
        code: 'SENSORS_MISSING',
        severity: 'error',
        message: 'Step counting is not available on this device.',
      });
    }

    if (support.supported && !support.granted) {
      issues.push({
        code: 'PERMISSIONS_DENIED',
        severity: 'error',
        message:
          Platform.OS === 'ios'
            ? 'Motion & Fitness permission is required for daily steps.'
            : 'Activity recognition permission is required for daily steps.',
      });
      recommendations.push({
        title: 'Grant motion permission',
        message: 'Allow step counting so daily steps stay accurate.',
        action: 'request_permission',
      });
    }

    if (diagnostics?.hasAccelerometerFallback) {
      issues.push({
        code: 'SENSORS_MISSING',
        severity: 'warn',
        message: 'No hardware step counter — using accelerometer fallback (less accurate).',
      });
    }

    if (powerSave) {
      issues.push({
        code: 'POWER_SAVE_ON',
        severity: 'warn',
        message: 'Power saver may delay step updates until you open the app.',
      });
      recommendations.push({
        title: 'Disable power saver',
        message: 'Turn off battery saver for more consistent step counting.',
        action: 'open_settings',
      });
    }

    if (Platform.OS === 'android') {
      const exempt = diagnostics?.batteryOptimizationExempt ?? oemInfo?.isBatteryOptimizationExempt ?? false;
      if (!exempt) {
        issues.push({
          code: 'BATTERY_OPTIMIZATION_ON',
          severity: 'warn',
          message: 'Battery optimization may pause step counting in the background.',
        });
        recommendations.push({
          title: 'Disable battery optimization',
          message: OEMBatteryManager.getRationale(oemInfo?.manufacturer),
          action: 'disable_optimization',
        });
      }

      if (diagnostics?.oemAggressiveBackground || oemInfo?.canOpenOemSettings) {
        issues.push({
          code: 'OEM_RESTRICTIONS',
          severity: 'warn',
          message:
            diagnostics?.oemPedometerNote ??
            OEMBatteryManager.getRationale(oemInfo?.manufacturer),
          data: { manufacturer: diagnostics?.manufacturer ?? oemInfo?.manufacturer },
        });
        recommendations.push({
          title: oemInfo?.oemSettingsAppName ?? 'Open device settings',
          message:
            diagnostics?.oemPedometerNote ??
            'Your phone manufacturer restricts background apps. Whitelist this app for reliable daily steps.',
          action: 'open_settings',
        });
      }
    }

    let score = 100;
    for (const issue of issues) {
      if (issue.severity === 'error') score -= 35;
      else if (issue.severity === 'warn') score -= 15;
      else score -= 5;
    }
    score = Math.max(0, Math.min(100, score));

    return { score, issues, recommendations, diagnostics, support };
  },

  async openOemSettings(): Promise<void> {
    await OEMBatteryManager.openOemBatterySettings();
  },
};
