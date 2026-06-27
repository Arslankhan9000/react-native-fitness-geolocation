import { Platform, Share } from 'react-native';
import { getFitnessGeolocationNative } from './native/getNativeModule';

const Native = getFitnessGeolocationNative();

export interface LogQuery {
  start?: number;
  end?: number;
  order?: number;
  limit?: number;
}

export const Logger = {
  async error(message: string): Promise<void> { await Native?.log?.('ERROR', message); },
  async warn(message: string): Promise<void> { await Native?.log?.('WARN', message); },
  async info(message: string): Promise<void> { await Native?.log?.('INFO', message); },
  async debug(message: string): Promise<void> { await Native?.log?.('DEBUG', message); },
  async getLog(query: LogQuery = {}): Promise<string> {
    return Native?.getLog?.(query) ?? '';
  },
  async destroyLog(): Promise<void> { await Native?.destroyLog?.(); },
  /** Share log via system sheet (email, AirDrop, etc.) */
  async emailLog(email: string, query: LogQuery = {}): Promise<void> {
    const log = await Logger.getLog(query);
    if (Platform.OS === 'ios' || Platform.OS === 'android') {
      await Share.share({ message: log, title: `FitnessGeolocation log → ${email}` });
    }
  },
  async uploadLog(url: string, query: LogQuery = {}): Promise<boolean> {
    return Native?.uploadLog?.(url, query) ?? false;
  },
};

export default Logger;
