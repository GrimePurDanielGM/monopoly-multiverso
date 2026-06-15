/**
 * Monopoly: El Multiverso — Motor de reglas (núcleo).
 *
 * REGLA ARQUITECTÓNICA: este paquete es la ÚNICA fuente de verdad de la lógica.
 * Debe ser puro e isomórfico: sin dependencias, sin APIs específicas de Node ni
 * de Deno, para poder importarse idénticamente desde la web (Vite/Node) y desde
 * las Edge Functions (Deno). En Fase 0 NO contiene reglas de Monopoly: solo una
 * función trivial que sirve para demostrar el reparto cliente/servidor.
 */

export const ENGINE_NAME = 'monopoly-multiverso-engine';
export const ENGINE_VERSION = '0.0.0';

export interface EngineFingerprint {
  readonly name: string;
  readonly version: string;
  readonly checksum: number;
}

/** Checksum determinista (FNV-like) — mismo input => mismo output en cualquier runtime. */
export function engineFingerprint(): EngineFingerprint {
  const seed = `${ENGINE_NAME}@${ENGINE_VERSION}`;
  let hash = 0;
  for (let i = 0; i < seed.length; i += 1) {
    hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
  }
  return { name: ENGINE_NAME, version: ENGINE_VERSION, checksum: hash };
}
