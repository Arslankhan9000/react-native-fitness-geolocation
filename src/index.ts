/**
 * react-native-fitness-geolocation
 *
 * Drop-in:  import Geolocation from 'react-native-fitness-geolocation'
 * Advanced: import { FitnessEngine, MotionEngine, PermissionManager } from 'react-native-fitness-geolocation'
 */

export { default, Geolocation } from './Geolocation';
export { Geolocation as BackgroundGeolocation } from './Geolocation';
export { PermissionManager } from './PermissionManager';
export { MotionEngine } from './MotionEngine';
export { FitnessEngine, createFitnessEngine } from './FitnessEngine';
export { PositionError } from './types';
export * from './types';
