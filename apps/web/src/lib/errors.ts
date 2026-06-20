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
  // Acciones del anfitrión
  NOT_HOST: 'Solo el anfitrión puede hacer esto.',
  VERSION_CONFLICT: 'Otro cambio se aplicó antes. Se ha recargado la sala; revísala e inténtalo de nuevo.',
  INVALID_PLAYER_LIMITS: 'Límites de jugadores no válidos.',
  MAX_EXCEEDS_TOKENS: 'El máximo supera el número de fichas disponibles.',
  TARGET_NOT_FOUND: 'Ese jugador ya no está en la sala.',
  CANNOT_KICK_HOST: 'No se puede expulsar al anfitrión.',
  NOT_ENOUGH_PLAYERS: 'Faltan jugadores para empezar.',
  PLAYERS_INCOMPLETE: 'Todos deben tener ficha y estar preparados.',
  PENDING_RECOVERIES: 'Hay solicitudes pendientes por resolver.',
  // Recuperaciones (Bloque 5)
  NO_RECOVERY: 'Esta sala no tiene recuperación de anfitrión configurada.',
  INVALID_PIN: 'PIN incorrecto.',
  LOCKED: 'Demasiados intentos. Inténtalo de nuevo más tarde.',
  SESSION_HAS_ACTIVE_PLAYER: 'Esta sesión ya controla un jugador en esta sala.',
  NOT_KICKED: 'No constas como expulsado de esta sala.',
  KICKED_USE_REENTRY: 'Fuiste expulsado; solicita la reentrada.',
  TARGET_NOT_ACTIVE: 'Esa identidad ya no está activa.',
  REQUEST_NOT_FOUND: 'La solicitud ya no existe.',
  BAD_REQUEST: 'Datos no válidos.',
  // Fase 2 — partida activa (banco / turnos / correcciones)
  NOT_ACTIVE: 'La partida no está en curso.',
  NOT_CURRENT_PLAYER: 'No es tu turno.',
  INSUFFICIENT_FUNDS: 'Saldo insuficiente para esta operación.',
  INVALID_AMOUNT: 'El importe no es válido (entero, mayor que 0 y hasta 10.000.000).',
  INVALID_DIRECTION: 'Operación de banca no válida.',
  UNKNOWN_PLAYER: 'Ese jugador no está en la partida.',
  SELF_TRANSFER: 'No puedes transferirte dinero a ti mismo.',
  REASON_REQUIRED: 'Indica un motivo (entre 3 y 500 caracteres).',
  NEGATIVE_NOT_ALLOWED: 'El saldo no puede ser negativo.',
  BALANCE_LIMIT: 'El saldo resultante supera el límite permitido.',
  UNKNOWN_LEDGER: 'Ese movimiento no existe.',
  CANNOT_REVERT_SEED: 'No se puede revertir este movimiento.',
  ALREADY_REVERTED: 'Ese movimiento ya fue revertido.',
  WOULD_GO_NEGATIVE: 'La reversión dejaría a un jugador con saldo negativo.',
  LEDGER_REF_EXHAUSTED: 'No se pudo registrar el movimiento. Inténtalo de nuevo.',
  REQUEST_ID_REQUIRED: 'Falta el identificador de la operación.',
  SNAPSHOT_INVALID: 'No se pudo leer el estado de la partida. Vuelve a intentarlo.',
  GAME_PAUSED: 'La partida está en pausa. El anfitrión debe reanudarla.',
  GAME_FINISHED: 'La partida ha finalizado.',
  LATE_JOIN_DISABLED: 'Esta partida no admite incorporaciones después de iniciar.',
  // Fase 2 — salida/expulsión de jugador
  HOST_CANNOT_LEAVE: 'El anfitrión no puede abandonar la partida (perdería el control).',
  CANNOT_REMOVE_HOST: 'No se puede sacar al anfitrión de la partida.',
  NO_REMAINING_PLAYERS: 'No hay jugadores restantes para repartir el saldo.',
  INVALID_RESOLUTION: 'Opción de reparto del saldo no válida.',
  TARGET_NOT_IN_GAME: 'Ese jugador ya no participa en la partida.',
  // Fase 3 — propiedades
  PROPERTY_NOT_FOUND: 'Esa propiedad no existe.',
  PROPERTY_NOT_BUYABLE: 'Esa casilla no se puede comprar.',
  PROPERTY_ALREADY_OWNED: 'Esa propiedad ya tiene dueño.',
  PROPERTY_NOT_OWNED: 'Esa propiedad no tiene propietario activo.',
  SELF_RENT: 'No puedes pagarte alquiler a ti mismo.',
  NO_RENT_DUE: 'Esa propiedad no cobra alquiler (aún sin dados).',
  // Fase 3 corrección — compra con aprobación, subasta, abandono, bancarrota
  PROPERTY_IN_AUCTION: 'Esa propiedad está en subasta.',
  AUCTION_ALREADY_ACTIVE: 'Ya hay una subasta activa de esa propiedad.',
  AUCTION_NOT_FOUND: 'Esa subasta ya no existe.',
  AUCTION_NOT_ACTIVE: 'La subasta ya no está activa.',
  BID_TOO_LOW: 'La puja debe superar la puja actual.',
  WINNER_INSUFFICIENT_FUNDS: 'El ganador no tiene saldo suficiente; la subasta sigue abierta.',
  WINNER_NOT_ACTIVE: 'El ganador ya no está activo en la partida.',
  BUYER_NOT_ACTIVE: 'El solicitante ya no está activo en la partida.',
  HOST_CANNOT_BANKRUPT: 'El anfitrión no puede declararse en bancarrota.',
  INVALID_CREDITOR: 'El acreedor no es válido.',
  INVALID_BANKRUPTCY_KIND: 'Tipo de bancarrota no válido.',
  // Fase 4 — movimiento y tablero
  INVALID_STEPS: 'El número de casillas debe estar entre 1 y 12.',
  NOT_ON_PROPERTY: 'Solo puedes solicitar comprar la propiedad en la que has caído durante tu turno.',
  NO_POSITION: 'Ese jugador todavía no tiene posición en el tablero.',
  INVALID_SPACE: 'Esa casilla no existe en el tablero.',
  INVALID_BOARD: 'Ese tablero no es válido.',
  BOARD_NOT_FOUND: 'No se encontró el tablero.',
  // Fase 4 — cruce entre tableros (intersección/guardián)
  JUNCTION_PENDING: 'Tienes que elegir por dónde seguir en la cárcel antes de continuar.',
  NO_PENDING_JUNCTION: 'No hay ninguna decisión de cruce pendiente.',
  NOT_YOUR_JUNCTION: 'Esa decisión de cruce no es tuya.',
  // Fase 5 — casillas especiales (cárcel, cartas, impuestos)
  IN_JAIL: 'Estás en la cárcel: paga la multa o usa una carta para salir.',
  JAIL_ACTION_ALREADY_TAKEN: 'Ya has intentado salir de la cárcel en este turno. Debes finalizar turno.',
  NOT_IN_JAIL: 'No estás en la cárcel.',
  NO_JAIL_CARD: 'No tienes ninguna carta para salir de la cárcel.',
  CARD_PENDING: 'Tienes una carta pendiente de resolver.',
  NO_PENDING_CARD: 'No tienes ninguna carta pendiente.',
  PAYMENT_PENDING: 'Tienes un pago pendiente: págalo o decláralo en bancarrota.',
  NO_PENDING_PAYMENT: 'No tienes ningún pago pendiente.',
};

/** Mensaje legible para un código de error conocido (o genérico si no lo es). */
export function messageForError(code: string | null | undefined): string {
  if (!code) return 'Ha ocurrido un error inesperado.';
  return MESSAGES[code] ?? `No se pudo completar la operación (${code}).`;
}
