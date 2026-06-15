// Edge Function de Fase 0 (Deno). Importa el motor compartido por su alias de
// import map (-> ../../packages/engine/src/index.ts). NO hay copia del motor
// dentro de supabase/functions: es la misma fuente que consume la web.
import { engineFingerprint } from '@multiverso/engine';
import type { HealthcheckResponse } from '@multiverso/shared';

Deno.serve(() => {
  const fp = engineFingerprint();
  const body: HealthcheckResponse = {
    ok: true,
    engine: { name: fp.name, version: fp.version, checksum: fp.checksum },
    serverTime: new Date().toISOString(),
  };
  return new Response(JSON.stringify(body), {
    headers: { 'content-type': 'application/json' },
  });
});
