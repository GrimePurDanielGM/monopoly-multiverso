import { useCallback, useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { peekGame, requestLateJoin, type PublicToken } from '../lib/api';
import { ensureAnonSession } from '../lib/session';
import { normalizeCode } from '../lib/codes';
import { useRequestStore } from '../store/request';
import { useRequestPolling } from '../hooks/useRequestPolling';
import { RecoveryRequestStatus } from '../components/RecoveryRequestStatus';

/** Solicitar entrar como NUEVO jugador en una partida activa (/sala/:code/entrar).
 *  Flujo distinto de recuperación de identidad y de reentrada de expulsados. */
export function LateJoinScreen() {
  const { code: codeParam = '' } = useParams();
  const code = normalizeCode(codeParam);
  const navigate = useNavigate();

  const [tokens, setTokens] = useState<PublicToken[]>([]);
  const [allowed, setAllowed] = useState<boolean | null>(null);
  const [name, setName] = useState('');
  const [token, setToken] = useState<string | null>(null);
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
      if (r.ok) {
        setAllowed(r.data.status === 'active' && r.data.allow_late_join);
        setTokens(r.data.available_tokens);
      } else setError(r.message);
    })();
    return () => { active = false; };
  }, [code]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!token || name.trim().length < 2 || busy) return;
    setBusy(true);
    setError(null);
    const r = await requestLateJoin(code, name.trim(), token, device.trim() || null);
    if (r.ok) start(r.data.request_ref, 'late_join', r.data.status);
    else setError(r.message);
    setBusy(false);
  }

  return (
    <section className="flex flex-col gap-4 lg:mx-auto lg:w-full lg:max-w-md">
      <h1 className="text-xl font-bold">Entrar en la partida</h1>
      <p className="text-sm text-slate-400">Sala {code}</p>

      {status ? (
        <RecoveryRequestStatus status={status} error={reqError} />
      ) : allowed === false ? (
        <p role="alert" className="rounded-lg bg-slate-800 px-3 py-2 text-sm text-slate-300">
          Esta partida no admite incorporaciones después de iniciar.
        </p>
      ) : (
        <form className="flex flex-col gap-4" onSubmit={submit} noValidate>
          <p className="text-sm text-slate-300">
            Entrarás con el saldo inicial, sin propiedades ni compensaciones, y necesitarás la aprobación del anfitrión.
          </p>
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-slate-300">Tu nombre</span>
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={24} autoComplete="off" placeholder="Marty"
              className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
          </label>
          <fieldset className="flex flex-col gap-2">
            <legend className="text-sm text-slate-300">Tu ficha</legend>
            <div role="radiogroup" aria-label="Ficha del nuevo jugador" className="grid grid-cols-4 gap-2">
              {tokens.map((t) => {
                const sel = token === t.id;
                return (
                  <button key={t.id} type="button" role="radio" aria-checked={sel} aria-label={t.label}
                    onClick={() => setToken(t.id)}
                    className={`flex flex-col items-center gap-1 rounded-lg border p-2 ${sel ? 'border-indigo-400 bg-indigo-950' : 'border-slate-700'}`}>
                    <span aria-hidden className="text-2xl leading-none">{t.icon}</span>
                    <span className="truncate text-[10px] text-slate-400">{t.label}</span>
                  </button>
                );
              })}
            </div>
          </fieldset>
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-slate-300">Dispositivo (opcional)</span>
            <input value={device} onChange={(e) => setDevice(e.target.value)} maxLength={40} autoComplete="off"
              className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
          </label>
          {error && <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">{error}</p>}
          <button type="submit" disabled={!token || name.trim().length < 2 || busy}
            className="min-h-[44px] rounded-xl bg-indigo-600 px-4 text-base font-semibold disabled:opacity-40">
            {busy ? 'Enviando…' : 'Solicitar entrar como nuevo jugador'}
          </button>
        </form>
      )}
    </section>
  );
}
