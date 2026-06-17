import { useCallback, useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { peekGame, requestRecovery, type PublicPlayer } from '../lib/api';
import { ensureAnonSession } from '../lib/session';
import { normalizeCode } from '../lib/codes';
import { useRequestStore } from '../store/request';
import { useRequestPolling } from '../hooks/useRequestPolling';
import { RecoveryIdentityPicker } from '../components/RecoveryIdentityPicker';
import { RecoveryRequestStatus } from '../components/RecoveryRequestStatus';

/** Recuperar una identidad ACTIVA desde otro dispositivo (/sala/:code/recuperar-jugador). */
export function RecoveryScreen() {
  const { code: codeParam = '' } = useParams();
  const code = normalizeCode(codeParam);
  const navigate = useNavigate();

  const [players, setPlayers] = useState<PublicPlayer[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
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

  const onApproved = useCallback(() => navigate(`/sala/${code}`), [navigate, code]);
  useRequestPolling(onApproved);

  useEffect(() => {
    let active = true;
    void (async () => {
      await ensureAnonSession();
      const r = await peekGame(code);
      if (!active) return;
      if (r.ok) setPlayers(r.data.players.filter((p) => !p.kicked));
      else setError(r.message);
    })();
    return () => {
      active = false;
    };
  }, [code]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!selected || busy) return;
    setBusy(true);
    setError(null);
    const r = await requestRecovery(code, selected, device.trim() || null);
    if (r.ok) start(r.data.request_ref, 'recovery', r.data.status);
    else setError(r.message);
    setBusy(false);
  }

  return (
    <section className="flex flex-col gap-4">
      <h1 className="text-xl font-bold">Recuperar mi jugador</h1>
      <p className="text-sm text-slate-400">Sala {code}</p>
      {status ? (
        <RecoveryRequestStatus status={status} error={reqError} />
      ) : (
        <form className="flex flex-col gap-3" onSubmit={submit} noValidate>
          <p className="text-sm text-slate-300">Elige tu identidad anterior:</p>
          <RecoveryIdentityPicker players={players} selected={selected} onSelect={setSelected} />
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-slate-300">Dispositivo (opcional)</span>
            <input value={device} onChange={(e) => setDevice(e.target.value)} maxLength={40} autoComplete="off" className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
          </label>
          {error && (
            <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
              {error}
            </p>
          )}
          <button type="submit" disabled={!selected || busy} className="min-h-[44px] rounded-xl bg-indigo-600 px-4 text-sm font-semibold disabled:opacity-40">
            {busy ? 'Enviando…' : 'Solicitar recuperación'}
          </button>
        </form>
      )}
    </section>
  );
}
