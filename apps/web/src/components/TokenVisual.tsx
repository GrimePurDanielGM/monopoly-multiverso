import type { PublicToken } from '../lib/api';
import { tokenEmoji } from '../lib/tokenVisual';

/** Imagen del peón si la hay (futuro, efecto 3D); si no, el emoji derivado del slug. Nunca muestra el slug. */
export function TokenVisual({ token, className = 'text-2xl leading-none' }: { token: PublicToken; className?: string }) {
  if (token.image_url) {
    return <img src={token.image_url} alt={token.image_alt ?? token.label} className={className} />;
  }
  return <span aria-hidden className={className}>{tokenEmoji(token.icon)}</span>;
}
