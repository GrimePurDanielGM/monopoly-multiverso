// Validación pura del formulario de creación (testeable sin DOM).
// La ficha es OBLIGATORIA y debe pertenecer al catálogo cargado: nunca null, vacío ni desconocida.
import { isValidPin } from './pin';

export interface CreateReadyInput {
  gameName: string;
  hostName: string;
  pin: string;
  tokenId: string | null;
  tokenIds: readonly string[];
}

export function isCreateReady(p: CreateReadyInput): boolean {
  const name = p.gameName.trim();
  const host = p.hostName.trim();
  const nameOk = name.length >= 3 && name.length <= 40;
  const hostOk = host.length >= 2 && host.length <= 24;
  const pinOk = isValidPin(p.pin);
  const tokenOk = p.tokenId !== null && p.tokenId !== '' && p.tokenIds.includes(p.tokenId);
  return nameOk && hostOk && pinOk && tokenOk;
}
