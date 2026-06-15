/**
 * Tipos y contratos compartidos entre web y servidor.
 * En Fase 0 solo se define el contrato del healthcheck. Los tipos de la base de
 * datos se generarán con `supabase gen types typescript` cuando exista esquema.
 */
export interface HealthcheckResponse {
  readonly ok: true;
  readonly engine: { name: string; version: string; checksum: number };
  readonly serverTime: string;
}
