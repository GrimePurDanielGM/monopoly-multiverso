// Dominio canónico para enlaces de unión y QR. Configurable por entorno para poder
// cambiar a un dominio propio sin tocar código. Por defecto, el dominio provisional.
const DEFAULT_BASE_URL = 'https://monopoly-multiverso-web.vercel.app';

function stripTrailingSlashes(s: string): string {
  return s.replace(/\/+$/, '');
}

export const PUBLIC_BASE_URL: string = stripTrailingSlashes(
  (import.meta.env.VITE_PUBLIC_BASE_URL as string | undefined)?.trim() || DEFAULT_BASE_URL,
);

/** Construye el enlace de unión a partir de una base explícita (función pura, testeable). */
export function buildJoinLink(base: string, code: string): string {
  return `${stripTrailingSlashes(base)}/j/${code}`;
}

/** Enlace de unión canónico: {VITE_PUBLIC_BASE_URL}/j/{CODE}. */
export function joinLink(code: string): string {
  return buildJoinLink(PUBLIC_BASE_URL, code);
}
