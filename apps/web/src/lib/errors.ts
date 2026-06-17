// Traducción de códigos de error del backend (Edge + RPC) a mensajes para el usuario.
// Se irá ampliando por bloques. Si el código no se reconoce, se muestra de forma genérica.
const MESSAGES: Record<string, string> = {
  // Edge create_game / sesión
  WEAK_PIN: 'El PIN debe tener 6 dígitos y no ser demasiado simple.',
  NOT_AUTHENTICATED: 'No hay sesión iniciada. Recarga la página e inténtalo de nuevo.',
  SERVER_MISCONFIGURED: 'El servidor no está configurado correctamente. Inténtalo más tarde.',
  UNCONFIGURED: 'La aplicación no tiene configurada la conexión con el servidor.',
  // Validación de nombres
  INVALID_GAME_NAME: 'El nombre de la partida debe tener entre 3 y 40 caracteres.',
  INVALID_NAME: 'El nombre debe tener entre 2 y 24 caracteres.',
  NAME_TAKEN: 'Ese nombre ya está en uso en la sala.',
  // Unión
  GAME_NOT_FOUND: 'No existe ninguna partida con ese código.',
  GAME_FULL: 'La sala está llena (máximo 16 jugadores).',
  GAME_CANCELLED: 'Esta partida fue cancelada.',
  GAME_NOT_JOINABLE: 'Esta partida ya no admite nuevas entradas.',
  KICKED_NEEDS_REENTRY: 'Fuiste expulsado de esta sala; usa la opción de reentrada.',
  // Sala / fichas / preparado
  NOT_ACTIVE_MEMBER: 'No formas parte de esta sala.',
  NOT_IN_LOBBY: 'La partida ya no está en la sala de espera.',
  TOKEN_INVALID: 'Esa ficha no está disponible.',
  TOKEN_TAKEN: 'Otra persona acaba de coger esa ficha.',
  INCOMPLETE_PLAYER: 'Elige una ficha antes de marcarte como preparado.',
  INVALID_SNAPSHOT: 'No se pudo leer el estado de la sala. Vuelve a intentarlo.',
  NETWORK: 'Problema de red. Comprueba tu conexión e inténtalo de nuevo.',
};

/** Mensaje legible para un código de error conocido (o genérico si no lo es). */
export function messageForError(code: string | null | undefined): string {
  if (!code) return 'Ha ocurrido un error inesperado.';
  return MESSAGES[code] ?? `No se pudo completar la operación (${code}).`;
}
