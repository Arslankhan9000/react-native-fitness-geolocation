import { Platform } from 'react-native';
import type { TrackingHealth } from './types';
import { ProviderEvents } from './ProviderEvents';
import { OEMBatteryManager } from './OEMBatteryManager';
import { diagnosticsEngine } from './engines/DiagnosticsEngine';

/**
 * Health API — aggregates platform signals into a score/issues/recommendations.
 *
 * Native-first source signals:
 * - provider state (GPS enabled/authorization)
 * - power save state
 * - available sensors
 * - battery optimization exemption (Android)
 */
export const Health = {
  async getHealth(): Promise<TrackingHealth> {
    const [provider, powerSave, sensors, deviceInfo] = await Promise.all([
      ProviderEvents.getProviderState(),
      ProviderEvents.isPowerSaveMode(),
      ProviderEvents.getSensors(),
      ProviderEvents.getDeviceInfo(),
    ]);

    const isExempt = Platform.OS === 'android' ? await OEMBatteryManager.isExempt() : true;

    const issues: TrackingHealth['issues'] = [];
    const recommendations: TrackingHealth['recommendations'] = [];

    // Provider/GPS
    if (!provider.enabled) {
      issues.push({ code: 'GPS_DISABLED', severity: 'error', message: 'Location services are disabled.', data: provider as any });
      recommendations.push({ title: 'Enable GPS', message: 'Turn on Location Services to track workouts.', action: 'open_settings' });
    }

    // Permission status (native provides a string, keep permissive)
    const status = (provider as any).status as string | undefined;
    if (status && (status === 'denied' || status === 'restricted')) {
      issues.push({ code: 'PERMISSIONS_DENIED', severity: 'error', message: 'Location permission is denied.', data: { status } });
      recommendations.push({ title: 'Grant Location Permission', message: 'Allow location access (Always for background tracking).', action: 'request_permission' });
    }

    // Power save
    if (powerSave) {
      issues.push({ code: 'POWER_SAVE_ON', severity: 'warn', message: 'Power saving mode is enabled.' });
      recommendations.push({ title: 'Disable Power Saver', message: 'Power Saver may reduce GPS accuracy and kill background work.', action: 'open_settings' });
    }

    // Android battery optimization exemption
    if (Platform.OS === 'android' && !isExempt) {
      issues.push({ code: 'BATTERY_OPTIMIZATION_ON', severity: 'warn', message: 'Battery optimizations may stop background tracking.' });
      recommendations.push({ title: 'Disable Battery Optimization', message: 'Allow this app to ignore battery optimizations for reliable tracking.', action: 'disable_optimization' });
    }

    // Sensors
    const missing = Object.entries(sensors).filter(([, v]) => v === false).map(([k]) => k);
    if (missing.length >= 2) {
      issues.push({ code: 'SENSORS_MISSING', severity: 'info', message: 'Some motion sensors are not available.', data: { missing } });
    }

    // Score
    let score = 100;
    for (const i of issues) {
      if (i.severity === 'error') score -= 35;
      else if (i.severity === 'warn') score -= 15;
      else score -= 5;
    }
    score = Math.max(0, Math.min(100, score));

    const signals = { provider, powerSave, sensors, deviceInfo, batteryOptimizationExempt: isExempt };
    diagnosticsEngine.log('info', 'health_snapshot', { score, issueCount: issues.length });

    return { score, issues, recommendations, signals };
  },
};

export default Health;

