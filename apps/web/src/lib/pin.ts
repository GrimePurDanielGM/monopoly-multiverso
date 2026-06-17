// PIN de anfitrión: 6 dígitos. Espejo de la regla del backend (isWeakPin) para dar
// feedback inmediato; el Edge `create_game` es la autoridad final (devuelve WEAK_PIN).
// El PIN NUNCA se guarda en estado global, localStorage, logs ni URL.
export const PIN_LENGTH = 6;

/** true si el PIN es válido (6 dígitos y no trivial). */
export function isValidPin(pin: string): boolean {
  if (!/^\d{6}$/.test(pin)) return false;
  if (/^(\d)\1{5}$/.test(pin)) return false; // todos iguales
  if (pin === '123456') return false;
  return true;
}
