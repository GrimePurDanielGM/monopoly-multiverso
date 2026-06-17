import { useState } from 'react';
import type { FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { recoverHost } from '../lib/api';
import { ensureAnonSession } from '../lib/session';
import { isValidCode, normalizeCode } from '../lib/codes';
import { isValidPin, PIN_LENGTH } from '../lib/pin';
import { LockedCountdown } from '../components/LockedCountdown';

/** Recuperación del rol de anfitrión por código + PIN (/recuperar). El PIN nunca se persiste. */
export function RecoverHostScreen() {
  const navigate = useNavigate();
  const [code, setCode] = useState('');
  const [pin, setPin] = useState(''); // SOLO estado local; nunca store/localStorage/URL/logs
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lockedUntil, setLockedUntil] = useState<string | null>(null);

  const locked = lockedUntil !== null;
  const canSubmit = isValidCode(code) && isValidPin(pin) && !busy && !locked;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setBusy(true);
    setError(null);
    const session = await ensureAnonSession();
    if (session !== 'ready') {
      setError('No se pudo iniciar sesión.');
      setBusy(false);
      return;
    }
    const c = normalizeCode(code);
    const r = await recoverHost(c, pin);
    if (r.ok) {
      setPin(''); // descartar el PIN en cuanto deja de necesitarse
      navigate(`/sala/${c}`);
      return;
    }
    if (r.lockedUntil) setLockedUntil(r.lockedUntil); // LOCKED (o INVALID_PIN que acaba de bloquear)
    setError(r.message);
    setBusy(false);
  }

  return (
    <section className="flex flex-col gap-4 lg:mx-auto lg:w-full lg:max-w-md">
      <h1 className="text-xl font-bold">Recuperar control de anfitrión</h1>
      <form className="flex flex-col gap-3" onSubmit={submit} noValidate>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Código de la sala</span>
          <input
            value={code}
            onChange={(e) => setCode(normalizeCode(e.target.value).slice(0, 6))}
            maxLength={6}
            autoCapitalize="characters"
            autoComplete="off"
            placeholder="ABC123"
            className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-center text-lg font-semibold tracking-[0.3em]"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">PIN de anfitrión ({PIN_LENGTH} dígitos)</span>
          <input
            value={pin}
            onChange={(e) => setPin(e.target.value.replace(/\D/g, '').slice(0, PIN_LENGTH))}
            inputMode="numeric"
            type="password"
            autoComplete="off"
            placeholder="••••••"
            className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base tracking-[0.4em]"
          />
        </label>
        {error && (
          <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
            {error}{' '}
            {locked && lockedUntil && (
              <LockedCountdown
                lockedUntil={lockedUntil}
                onExpire={() => {
                  setLockedUntil(null);
                  setError(null);
                }}
              />
            )}
          </p>
        )}
        <button type="submit" disabled={!canSubmit} className="min-h-[44px] rounded-xl bg-indigo-600 px-4 text-sm font-semibold disabled:opacity-40">
          {busy ? 'Comprobando…' : 'Recuperar control'}
        </button>
      </form>
    </section>
  );
}
