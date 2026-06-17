import { Link } from 'react-router-dom';
import { requestResultMessage, type RequestStatus } from '../lib/requestState';

/** Muestra el estado de la solicitud del solicitante (pending/terminal). */
export function RecoveryRequestStatus({ status, error }: { status: RequestStatus | null; error: string | null }) {
  if (!status) return null;
  const terminalNonApproved = status === 'rejected' || status === 'cancelled' || status === 'expired';
  return (
    <div className="flex flex-col gap-2 rounded-xl border border-slate-700 p-4">
      <p role="status" className="text-sm">
        {requestResultMessage(status)}
      </p>
      {status === 'pending' && error && <p className="text-xs text-amber-300">Reintentando… ({error})</p>}
      {terminalNonApproved && (
        <Link to="/" className="rounded-lg bg-indigo-600 px-3 py-2 text-center text-sm font-semibold">
          Volver al inicio
        </Link>
      )}
    </div>
  );
}
