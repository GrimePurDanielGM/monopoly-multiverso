import { describe, it, expect } from 'vitest';
import { messageForError } from './errors';

describe('messageForError', () => {
  it('mapea códigos conocidos a mensajes en español', () => {
    expect(messageForError('GAME_FULL')).toMatch(/llena/i);
    expect(messageForError('NAME_TAKEN')).toMatch(/nombre/i);
    expect(messageForError('WEAK_PIN')).toMatch(/PIN/);
  });
  it('devuelve mensaje genérico para códigos desconocidos', () => {
    expect(messageForError('ZZZ_RARO')).toMatch(/ZZZ_RARO/);
    expect(messageForError(null)).toMatch(/inesperado/i);
  });
});
