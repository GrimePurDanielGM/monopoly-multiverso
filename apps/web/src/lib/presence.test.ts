import { describe, it, expect } from 'vitest';
import { filterPresentRefs, presenceRefsFromState } from './presence';

describe('presence', () => {
  it('extrae public_ref del presenceState crudo', () => {
    const state = { 'P-AAAAAAAAAA': [{ public_ref: 'P-AAAAAAAAAA' }], k: [{ public_ref: 'P-BBBBBBBBBB' }] };
    expect(presenceRefsFromState(state).sort()).toEqual(['P-AAAAAAAAAA', 'P-BBBBBBBBBB']);
  });
  it('ignora presence desconocida, con formato inválido o vacía', () => {
    const known = new Set(['P-AAAAAAAAAA']);
    const raw = ['P-AAAAAAAAAA', 'P-1234567890' /* válido pero no en snapshot */, 'malo', '', 'p-aaaaaaaaaa' /* minúsculas */];
    expect(filterPresentRefs(raw, known)).toEqual(['P-AAAAAAAAAA']);
  });
});
