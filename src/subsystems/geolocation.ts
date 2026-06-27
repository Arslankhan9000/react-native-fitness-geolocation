/**
 * Geolocation + GPS fitness tracking subsystem.
 * Import: `react-native-fitness-geolocation/geolocation`
 *
 * Independent lifecycle: use Geolocation.watchPosition / stopObserving only.
 */
export { default as Geolocation, default as BackgroundGeolocation, default } from '../Geolocation';
export { MotionEngine } from '../MotionEngine';
export { FitnessEngine, createFitnessEngine } from '../FitnessEngine';
export { TimeBasedTracker, timeBasedTracker } from '../TimeBasedTracker';
export { SmartGPSController, smartGPSController } from '../SmartGPSController';
export { Tracking } from '../Tracking';
export { MetricsV2, computeMetricsV2 } from '../MetricsV2';
export { LiveActivity } from '../LiveActivity';
export { FitnessTrackingService, default as fitnessTrackingService } from '../FitnessTrackingService';
export { OEMBatteryManager } from '../OEMBatteryManager';
export { registerHeadlessTask, isHeadlessTaskRegistered } from '../HeadlessTask';
export { ProviderEvents } from '../ProviderEvents';
export { Logger } from '../Logger';
