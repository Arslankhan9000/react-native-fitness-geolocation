import { LogLevel, logLevelFromString, shouldPersistLog } from '../src/config/LogLevel';
import { resolveLoggerConfig } from '../src/config/resolveLoggerConfig';
import { normalizeConfig } from '../src/config/normalizeConfig';

describe('LogLevel', () => {
  it('maps string levels to numeric values', () => {
    expect(logLevelFromString('error')).toBe(LogLevel.Error);
    expect(logLevelFromString('VERBOSE')).toBe(LogLevel.Verbose);
  });

  it('filters persistence by configured verbosity', () => {
    expect(shouldPersistLog(LogLevel.Error, LogLevel.Off)).toBe(false);
    expect(shouldPersistLog(LogLevel.Error, LogLevel.Error)).toBe(true);
    expect(shouldPersistLog(LogLevel.Debug, LogLevel.Info)).toBe(false);
    expect(shouldPersistLog(LogLevel.Info, LogLevel.Verbose)).toBe(true);
  });
});

describe('resolveLoggerConfig', () => {
  it('prefers nested logger.debug over legacy root debug', () => {
    const cfg = resolveLoggerConfig({ debug: false, logger: { debug: true, logLevel: LogLevel.Verbose } });
    expect(cfg.debug).toBe(true);
    expect(cfg.logLevel).toBe(LogLevel.Verbose);
  });

  it('falls back to root debug when logger block omitted', () => {
    const cfg = resolveLoggerConfig({ debug: true, logger: { logMaxDays: 7 } });
    expect(cfg.debug).toBe(true);
    expect(cfg.logMaxDays).toBe(7);
  });
});

describe('normalizeConfig', () => {
  it('flattens compound groups and strips nested objects', () => {
    const flat = normalizeConfig({
      geolocation: { distanceFilter: 10, authorizationLevel: 'always' },
      http: { url: 'https://example.com', batchSize: 123 },
      app: { stopOnTerminate: false, notificationTitle: 'A' },
      persistence: { maxDaysToPersist: 9 },
      activity: { trackingMode: 'navigation' },
      logger: { debug: true, logLevel: LogLevel.Info },
    });

    expect(flat.distanceFilter).toBe(10);
    expect(flat.authorizationLevel).toBe('always');
    expect(flat.url).toBe('https://example.com');
    expect(flat.batchSize).toBe(123);
    expect(flat.stopOnTerminate).toBe(false);
    expect(flat.notificationTitle).toBe('A');
    expect(flat.maxDaysToPersist).toBe(9);
    expect(flat.trackingMode).toBe('navigation');

    expect((flat as any).geolocation).toBeUndefined();
    expect((flat as any).http).toBeUndefined();
    expect((flat as any).app).toBeUndefined();
    expect((flat as any).activity).toBeUndefined();
    expect((flat as any).persistence).toBeUndefined();
    expect(flat.logger?.debug).toBe(true);
  });

  it('nested values override root duplicates', () => {
    const flat = normalizeConfig({
      url: 'root',
      http: { url: 'nested' },
      distanceFilter: 1,
      geolocation: { distanceFilter: 2 },
    });
    expect(flat.url).toBe('nested');
    expect(flat.distanceFilter).toBe(2);
  });
});
