// Validación funcional de la configuración del lobby. El backend sigue siendo la autoridad
// (update_config exige v_min >= 2); esto solo evita envíos inválidos desde la UI.
export const MIN_FLOOR = 2; // mínimo de jugadores para iniciar (coincide con el backend)
export const MAX_CEIL = 16;

export interface ConfigInput {
  name: string;
  minPlayers: number;
  maxPlayers: number;
  initialMoney: number;
}

/** Lista de motivos por los que la configuración no es válida (vacía = válida). */
export function configErrors(input: ConfigInput, currentPlayers: number): string[] {
  const errs: string[] = [];
  const name = input.name.trim();
  if (name.length < 3 || name.length > 40) errs.push('El nombre debe tener entre 3 y 40 caracteres.');
  if (!Number.isInteger(input.minPlayers) || input.minPlayers < MIN_FLOOR) errs.push(`El mínimo no puede ser inferior a ${MIN_FLOOR}.`);
  if (!Number.isInteger(input.maxPlayers) || input.maxPlayers > MAX_CEIL) errs.push(`El máximo no puede superar ${MAX_CEIL}.`);
  if (input.minPlayers > input.maxPlayers) errs.push('El mínimo no puede ser mayor que el máximo.');
  if (input.maxPlayers < currentPlayers) errs.push('El máximo no puede ser inferior al número actual de jugadores.');
  if (!Number.isInteger(input.initialMoney) || input.initialMoney <= 0) errs.push('El dinero inicial debe ser un entero positivo.');
  return errs;
}

export function isConfigValid(input: ConfigInput, currentPlayers: number): boolean {
  return configErrors(input, currentPlayers).length === 0;
}
