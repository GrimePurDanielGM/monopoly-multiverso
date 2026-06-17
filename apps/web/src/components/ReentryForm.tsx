import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { requestReentry } from '../lib/api';
import { ensureAnonSession } from '../lib/session';
import { useRequestStore } from '../store/request';
import { useRequestPolling } from '../hooks/useRequestPolling';
import { RecoveryRequestStatus } from './RecoveryRequestStatus';

/** Reentrada de un jugador expulsado: nombre nuevo + sondeo hasta aprobación. */
export function ReentryForm({ code, onApproved }: { code: string; onApproved: () => void }) {
  const [name, setName] = useState('');
  const [device, setDevice] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const status = useRequestStore((s) => s.status);
  const reqError = useRequestStore((s) => s.error);
  const start = useRequestStore((s) => s.start);

  useEffect(() => {
    useRequestStore.getState().reset();
    return () => useRequestStore.getState().reset();
  }, []);

  useRequestPolling(onApproved);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (name.trim().length < 2 || busy) return;
    setBusy(true);
    setError(null);
    const session = await ensureAnonSession();
    if (session !== 'ready') {
      setError('No se pudo iniciar sesión.');
      setBusy(false);
      return;
    }
    const r = await requestReentry(code, name.trim(), device.trim() || null);
    if (r.ok) start(r.data.request_ref, 'reentry', r.data.status);
    else setError(r.message);
    setBusy(false);
  }

  if (status) return <RecoveryRequestStatus status={status} error={reqError} />;

  return (
    <form className="flex flex-col gap-3" onSubmit={submit} noValidate>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-300">Nombre para volver a entrar</span>
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={24} autoComplete="off" className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-300">Dispositivo (opcional)</span>
        <input value={device} onChange={(e) => setDevice(e.target.value)} maxLength={40} autoComplete="off" className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
      </label>
      {error && (
        <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
          {error}
        </p>
      )}
      <button type="submit" disabled={name.trim().length < 2 || busy} className="min-h-[44px] rounded-xl bg-indigo-600 px-4 text-sm font-semibold disabled:opacity-40">
        {busy ? 'Enviando…' : 'Solicitar reentrada'}
      </button>
    </form>
  );
}
