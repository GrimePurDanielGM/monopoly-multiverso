import { describe, it, expect } from 'vitest';
import { engineFingerprint, ENGINE_NAME, ENGINE_VERSION } from './index';

describe('engine (fase 0)', () => {
  it('produce un fingerprint determinista', () => {
    const a = engineFingerprint();
    const b = engineFingerprint();
    expect(a).toEqual(b);
    expect(a.name).toBe(ENGINE_NAME);
    expect(a.version).toBe(ENGINE_VERSION);
    expect(typeof a.checksum).toBe('number');
  });
});
