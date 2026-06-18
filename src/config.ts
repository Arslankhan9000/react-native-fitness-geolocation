import type { GeolocationConfiguration } from './types';

const DEFAULT_CONFIG: GeolocationConfiguration = {
  skipPermissionRequests: false,
  authorizationLevel: 'whenInUse',
  locationProvider: 'auto',
  enableBackgroundLocationUpdates: true,
};

let globalConfig: GeolocationConfiguration = { ...DEFAULT_CONFIG };

export function setConfiguration(config: GeolocationConfiguration): void {
  globalConfig = { ...globalConfig, ...config };
}

export function getConfiguration(): GeolocationConfiguration {
  return globalConfig;
}

export function shouldSkipPermissionRequests(): boolean {
  return globalConfig.skipPermissionRequests === true;
}
