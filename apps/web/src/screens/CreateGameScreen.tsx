import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { createGame, listActiveTokens, type PublicToken } from '../lib/api';
import { ensureAnonSession } from '../lib/session';
import { isValidPin, PIN_LENGTH } from '../lib/pin';
import { isCreateReady } from '../lib/create';

const MIN_PLAYERS = 6;
const MAX_PLAYERS = 16;

/** Crear partida: nombre de sala + nombre de anfitrión + FICHA (obligatoria) + PIN de 6 dígitos. */
export function CreateGameScreen() {
  const navigate = useNavigate();
  // request_id estable durante TODO el intento -> create_game es idempotente ante reintentos
  // (no se regenera al fallar; reusarlo evita partidas duplicadas si la respuesta se perdió).
  const [requestId] = useState<string>(() => crypto.randomUUID());
  const [gameName, setGameName] = useState('');
  const [hostName, setHostName] = useState('');
  const [pin, setPin] = useState(''); // SOLO en estado local: nunca a store, localStorage, logs ni URL
  const [tokens, setTokens] = useState<PublicToken[]>([]);
  const [tokensError, setTokensError] = useState<string | null>(null);
  const [selectedTokenId, setSelectedTokenId] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Carga del catálogo provisional de fichas (lectura directa permitida de token_catalog).
  useEffect(() => {
    let active = true;
    void listActiveTokens().then((r) => {
      if (!active) return;
      if (r.ok) setTokens(r.data);
      else setTokensError(r.message);
    });
    return () => {
      active = false;
    };
  }, []);

  const tokenIds = tokens.map((t) => t.id);
  const ready = isCreateReady({ gameName, hostName, pin, tokenId: selectedTokenId, tokenIds });
  const canSubmit = ready && !submitting;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    // Guardas finales: nunca enviar sin ficha válida del catálogo.
    if (!canSubmit || selectedTokenId === null || !tokenIds.includes(selectedTokenId)) return;
    setSubmitting(true);
    setError(null);
    const session = await ensureAnonSession();
    if (session !== 'ready') {
      setError(session === 'unconfigured' ? 'La app no está configurada.' : 'No se pudo iniciar sesión.');
      setSubmitting(false);
      return;
    }
    const result = await createGame({
      name: gameName.trim(),
      host_name: hostName.trim(),
      pin,
      host_token: selectedTokenId,
      request_id: requestId,
    });
    if (result.ok) {
      setPin(''); // descartar el PIN en cuanto deja de necesitarse
      navigate(`/sala/${result.data.code}`);
      return;
    }
    // No se regenera request_id: el reintento del mismo intento reusa el mismo id (idempotente).
    setError(result.message);
    setSubmitting(false);
  }

  return (
    <section className="flex flex-col gap-4">
      <h1 className="text-xl font-bold">Crear partida</h1>
      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Nombre de la partida</span>
          <input
            value={gameName}
            onChange={(e) => setGameName(e.target.value)}
            maxLength={40}
            autoComplete="off"
            placeholder="La partida del sábado"
            className="rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-base"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Tu nombre (anfitrión)</span>
          <input
            value={hostName}
            onChange={(e) => setHostName(e.target.value)}
            maxLength={24}
            autoComplete="off"
            placeholder="Daniel"
            className="rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-base"
          />
        </label>

        <fieldset className="flex flex-col gap-2">
          <legend className="text-sm text-slate-300">Tu ficha</legend>
          {tokensError && (
            <p role="alert" className="text-sm text-rose-300">
              No se pudo cargar el catálogo de fichas. {tokensError}
            </p>
          )}
          <div role="radiogroup" aria-label="Ficha del anfitrión" className="grid grid-cols-4 gap-2">
            {tokens.map((t) => {
              const selected = selectedTokenId === t.id;
              return (
                <button
                  key={t.id}
                  type="button"
                  role="radio"
                  aria-checked={selected}
                  aria-label={t.label}
                  onClick={() => setSelectedTokenId(t.id)}
                  className={`flex flex-col items-center gap-1 rounded-lg border p-2 ${
                    selected ? 'border-indigo-400 bg-indigo-950' : 'border-slate-700 active:bg-slate-800'
                  }`}
                >
                  <span aria-hidden className="text-2xl leading-none">
                    {t.icon}
                  </span>
                  <span className="truncate text-[10px] text-slate-400">{t.label}</span>
                </button>
              );
            })}
          </div>
          {tokens.length > 0 && selectedTokenId === null && (
            <p className="text-xs text-slate-500">Elige una ficha para continuar.</p>
          )}
        </fieldset>

        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">PIN de anfitrión ({PIN_LENGTH} dígitos)</span>
          <input
            value={pin}
            onChange={(e) => setPin(e.target.value.replace(/\D/g, '').slice(0, PIN_LENGTH))}
            inputMode="numeric"
            autoComplete="off"
            type="password"
            placeholder="••••••"
            className="rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-base tracking-[0.4em]"
          />
          <span className="text-xs text-slate-500">
            Lo necesitarás para recuperar el control de la sala si cambias de dispositivo. No lo compartas.
          </span>
        </label>

        <p className="text-xs text-slate-500">
          Sala para {MIN_PLAYERS}–{MAX_PLAYERS} jugadores.
        </p>

        {error && (
          <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
            {error}
          </p>
        )}

        {pin.length > 0 && !isValidPin(pin) && (
          <p className="text-xs text-amber-300">El PIN debe tener 6 dígitos y no ser trivial.</p>
        )}

        <button
          type="submit"
          disabled={!canSubmit}
          className="rounded-xl bg-indigo-600 px-4 py-3 text-base font-semibold disabled:opacity-40 active:bg-indigo-700"
        >
          {submitting ? 'Creando…' : 'Crear y entrar'}
        </button>
      </form>
    </section>
  );
}
