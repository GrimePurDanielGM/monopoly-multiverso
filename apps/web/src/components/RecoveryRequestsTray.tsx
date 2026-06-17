import { useState } from 'react';
import { resolveRecovery, resolveReentry } from '../lib/api';
import type { SnapPlayer, SnapRequest } from '../lib/snapshot';
import { RecoveryRequestCard } from './RecoveryRequestCard';
import { ConfirmDialog } from './ConfirmDialog';
import { HostActionError } from './HostActionError';

/** Bandeja del anfitrión. Las solicitudes salen SOLO de snapshot.requests (sin SELECT directo). */
export function RecoveryRequestsTray({
  requests,
  players,
  reload,
}: {
  requests: SnapRequest[];
  players: SnapPlayer[];
  reload: () => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [acceptTarget, setAcceptTarget] = useState<SnapRequest | null>(null);

  if (requests.length === 0) return null;

  const nameFor = (r: SnapRequest): string => {
    const p = players.find((pl) => pl.public_ref === r.target_public_ref);
    return p ? p.name : r.target_public_ref;
  };

  async function resolve(r: SnapRequest, accept: boolean) {
    setBusy(true);
    setError(null);
    const res = r.kind === 'recovery' ? await resolveRecovery(r.request_ref, accept) : await resolveReentry(r.request_ref, accept);
    await reload(); // Broadcast/recovery_requested solo invalida; recargamos el snapshot autoritativo
    if (!res.ok) setError(res.message);
    setBusy(false);
    setAcceptTarget(null);
  }

  return (
    <section aria-label="Solicitudes pendientes" className="flex flex-col gap-2 rounded-xl border border-indigo-500/30 p-4">
      <h2 className="text-sm font-bold text-indigo-300">Solicitudes ({requests.length})</h2>
      <HostActionError message={error} />
      {requests.map((r) => (
        <RecoveryRequestCard
          key={r.request_ref}
          request={r}
          name={nameFor(r)}
          busy={busy}
          onAccept={() => setAcceptTarget(r)}
          onReject={() => void resolve(r, false)}
        />
      ))}
      <ConfirmDialog
        open={acceptTarget !== null}
        title="Aprobar solicitud"
        busy={busy}
        message={
          acceptTarget ? (
            <>
              ¿Aprobar la {acceptTarget.kind === 'recovery' ? 'recuperación' : 'reentrada'} de <b>{nameFor(acceptTarget)}</b>?
            </>
          ) : (
            ''
          )
        }
        confirmLabel="Aprobar"
        onConfirm={() => {
          if (acceptTarget) void resolve(acceptTarget, true);
        }}
        onCancel={() => setAcceptTarget(null)}
      />
    </section>
  );
}
