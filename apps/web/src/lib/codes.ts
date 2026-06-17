// Códigos de partida: 6 caracteres del mismo alfabeto que usa create_game_tx
// (sin I, L, O, 0, 1 para evitar confusiones). El servidor es la autoridad final;
// estas utilidades solo dan validación/normalización inmediata en el cliente.
export const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 6;

/** Normaliza como el servidor: recorta, mayúsculas y elimina espacios internos. */
export function normalizeCode(raw: string): string {
  return raw.toUpperCase().replace(/\s+/g, '');
}

/** Topic privado de Realtime para una sala, con el código normalizado. */
export function roomTopic(rawCode: string): string {
  return `room:${normalizeCode(rawCode)}`;
}

/** Guard de UX (no autoritativo): longitud correcta y solo caracteres del alfabeto. */
export function isValidCode(raw: string): boolean {
  const c = normalizeCode(raw);
  if (c.length !== CODE_LENGTH) return false;
  for (const ch of c) {
    if (!CODE_ALPHABET.includes(ch)) return false;
  }
  return true;
}
