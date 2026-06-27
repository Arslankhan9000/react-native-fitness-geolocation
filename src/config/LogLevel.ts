/**
 * Native SQLite log verbosity — mirrors Transistorsoft LogLevel semantics.
 *
 * Higher values include more detail. `Off` disables persistence entirely.
 */
export const LogLevel = {
  Off: 0,
  Error: 1,
  Warning: 2,
  Info: 3,
  Debug: 4,
  Verbose: 5,
} as const;

export type LogLevelValue = (typeof LogLevel)[keyof typeof LogLevel];

export function logLevelFromString(level: string): LogLevelValue {
  const u = level.toUpperCase();
  if (u === 'ERROR') return LogLevel.Error;
  if (u === 'WARN' || u === 'WARNING') return LogLevel.Warning;
  if (u === 'INFO') return LogLevel.Info;
  if (u === 'DEBUG') return LogLevel.Debug;
  if (u === 'VERBOSE' || u === 'TRACE') return LogLevel.Verbose;
  return LogLevel.Off;
}

export function shouldPersistLog(messageLevel: LogLevelValue, configured: LogLevelValue): boolean {
  if (configured === LogLevel.Off) return false;
  return messageLevel <= configured;
}
