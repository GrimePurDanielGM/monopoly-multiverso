import { describe, it, expect, vi, afterEach } from 'vitest';
import { shareOrCopy, copyToClipboard } from './share';

afterEach(() => vi.unstubAllGlobals());

describe('share', () => {
  it('usa Web Share API cuando está disponible', async () => {
    const share = vi.fn(() => Promise.resolve());
    vi.stubGlobal('navigator', { userAgent: 'test', share });
    const m = await shareOrCopy({ title: 't', text: 'x', url: 'https://x/j/ABC234' });
    expect(m).toBe('share');
    expect(share).toHaveBeenCalled();
  });
  it('cae al portapapeles si no hay Web Share', async () => {
    const writeText = vi.fn(() => Promise.resolve());
    vi.stubGlobal('navigator', { userAgent: 'test', clipboard: { writeText } });
    const m = await shareOrCopy({ title: 't', text: 'x', url: 'https://x/j/ABC234' });
    expect(m).toBe('clipboard');
    expect(writeText).toHaveBeenCalledWith('https://x/j/ABC234');
  });
  it('copyToClipboard devuelve false si falla', async () => {
    vi.stubGlobal('navigator', { userAgent: 'test', clipboard: { writeText: () => Promise.reject(new Error('no')) } });
    expect(await copyToClipboard('x')).toBe(false);
  });
});
