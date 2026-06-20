// Representación visual de las fichas (peones). El catálogo guarda un `icon` que es un IDENTIFICADOR
// interno (slug en inglés: 'car', 'hat-cowboy'…), NO algo para mostrar. En el lobby debe verse SOLO el
// nombre en español (`label`) + un emoji derivado del slug. Más adelante cada peón podrá traer una imagen
// propia (image_url/image_alt) con efecto 3D; mientras tanto se usa el emoji como sustituto.

/** Mapa slug→emoji (placeholder hasta tener las fotos reales). Ante un slug desconocido se usa 🎲. */
const ICON_EMOJI: Record<string, string> = {
  car: '🚗', 'car-classic': '🚙', board: '🛹', bolt: '⚡', radioactive: '☢️', clock: '🕰️', book: '📖',
  train: '🚂', guitar: '🎸', battery: '🔋', dog: '🐕', 'dog-scottie': '🐩', shoe: '👟', 'hat-cowboy': '🤠',
  'hat-top': '🎩', thimble: '🧵', boot: '🥾', ship: '🚢', wheelbarrow: '🛒', cat: '🐱', penguin: '🐧',
  't-rex': '🦖', rider: '🏇', 'spinning-wheel': '🧶', iron: '👕', 'peter-mayday': '🐾', babypool: '🏊',
};

/** Emoji para una ficha a partir de su slug de icono. Fallback 🎲 si no está mapeado. */
export function tokenEmoji(iconSlug: string): string {
  return ICON_EMOJI[iconSlug] ?? '🎲';
}
