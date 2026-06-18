import { useCallback, useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { getLobbySnapshotByCode, joinGame, peekGame, type PeekGameResult } from '../lib/api';
import { ensureAnonSession } from '../lib/session';
import { isValidCode, normalizeCode } from '../lib/codes';
import { QrScanner } from '../components/QrScanner';

/** Unirse por código o por enlace /j/:code. La ficha se elige luego, en la sala. */
export function JoinScreen() {
  const params = useParams();
  const navigate = useNavigate();
  const initialCode = params.code ? normalizeCode(params.code) : '';

  const [code, setCode] = useState(initialCode);
  const [peek, setPeek] = useState<PeekGameResult | null>(null);
  const [name, setName] = useState('');
  const [requestId] = useState<string>(() => crypto.randomUUID());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [scanOpen, setScanOpen] = useState(false);

  const runPeek = useCallback(async (raw: string) => {
    const c = normalizeCode(raw);
    if (!isValidCode(c)) {
      setError('El código tiene 6 caracteres.');
      return;
    }
    setBusy(true);
    setError(null);
    const session = await ensureAnonSession();
    if (session !== 'ready') {
      setError(session === 'unconfigured' ? 'La app no está configurada.' : 'No se pudo iniciar sesión.');
      setBusy(false);
      return;
    }
    // 1) ¿Esta sesión ya controla un jugador en la sala? -> reanudar (lobby o activa),
    //    sin volver a unirse ni elegir ficha. La autoridad es el snapshot (auth.uid).
    const mine = await getLobbySnapshotByCode(c);
    if (mine.ok) {
      navigate(`/sala/${c}`);
      return;
    }
    // 2) No soy miembro: el estado decide el flujo (unirse en lobby; recuperar en activa).
    const result = await peekGame(c);
    if (result.ok) {
      setCode(c);
      setPeek(result.data);
    } else {
      setError(result.message);
    }
    setBusy(false);
  }, [navigate]);

  // Si llegamos por enlace /j/:code, hacemos la vista previa automáticamente.
  useEffect(() => {
    if (initialCode) void runPeek(initialCode);
  }, [initialCode, runPeek]);

  async function onJoin(e: FormEvent) {
    e.preventDefault();
    if (!peek || name.trim().length < 2 || busy) return;
    setBusy(true);
    setError(null);
    const result = await joinGame(code, name.trim(), requestId);
    if (result.ok) {
      navigate(`/sala/${code}`);
      return;
    }
    setError(result.message);
    setBusy(false);
  }

  return (
    <section className="flex flex-col gap-4 lg:mx-auto lg:w-full lg:max-w-md">
      <h1 className="text-xl font-bold">Unirse a una partida</h1>

      {!peek && (
        <form
          className="flex flex-col gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            void runPeek(code);
          }}
          noValidate
        >
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-slate-300">Código de la sala</span>
            <input
              value={code}
              onChange={(e) => setCode(normalizeCode(e.target.value).slice(0, 6))}
              maxLength={6}
              autoCapitalize="characters"
              autoComplete="off"
              placeholder="ABC123"
              className="rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-center text-lg font-semibold tracking-[0.3em]"
            />
          </label>
          {error && (
            <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
              {error}
            </p>
          )}
          <button
            type="submit"
            disabled={!isValidCode(code) || busy}
            className="rounded-xl bg-indigo-600 px-4 py-3 text-base font-semibold disabled:opacity-40 active:bg-indigo-700"
          >
            {busy ? 'Buscando…' : 'Buscar sala'}
          </button>
          <button
            type="button"
            onClick={() => setScanOpen(true)}
            className="min-h-[44px] rounded-xl border border-slate-600 px-4 text-base font-semibold active:bg-slate-800"
          >
            Escanear QR
          </button>
        </form>
      )}

      <QrScanner
        open={scanOpen}
        onDetected={(c) => {
          setScanOpen(false);
          setCode(c);
          void runPeek(c);
        }}
        onClose={() => setScanOpen(false)}
      />

      {peek && (
        <div className="flex flex-col gap-4">
          <div className="rounded-xl border border-slate-700 p-4">
            <p className="text-base font-semibold">{peek.name}</p>
            <p className="mt-1 text-sm text-slate-400">
              {peek.player_count}/{peek.max_players} jugadores ·{' '}
              {peek.status === 'lobby' ? 'En sala de espera' : peek.status === 'active' ? 'Partida en curso' : 'Cancelada'}
            </p>
          </div>

          {peek.status === 'lobby' && peek.accepts_entries && (
            <form className="flex flex-col gap-3" onSubmit={onJoin} noValidate>
              <label className="flex flex-col gap-1 text-sm">
                <span className="text-slate-300">Tu nombre</span>
                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  maxLength={24}
                  autoComplete="off"
                  placeholder="Marty"
                  className="rounded-lg border border-slate-600 bg-slate-800 px-3 py-2 text-base"
                />
              </label>
              {error && (
                <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
                  {error}
                </p>
              )}
              <button
                type="submit"
                disabled={name.trim().length < 2 || busy}
                className="rounded-xl bg-indigo-600 px-4 py-3 text-base font-semibold disabled:opacity-40 active:bg-indigo-700"
              >
                {busy ? 'Entrando…' : 'Unirme'}
              </button>
            </form>
          )}

          {peek.status === 'lobby' && !peek.accepts_entries && (
            <p role="status" className="rounded-lg bg-slate-800 px-3 py-2 text-sm text-slate-300">
              Esta sala está llena y no admite nuevas entradas ahora mismo.
            </p>
          )}

          {/* Partida en curso: no se puede unir. Si ya jugabas, recupera tu jugador. */}
          {peek.status === 'active' && (
            <div className="flex flex-col gap-2">
              <p role="status" className="rounded-lg bg-slate-800 px-3 py-2 text-sm text-slate-300">
                Esta partida ya ha comenzado. Si ya formabas parte, recupera tu jugador.
              </p>
              <button
                type="button"
                onClick={() => navigate(`/sala/${code}/recuperar-jugador`)}
                className="min-h-[44px] rounded-xl bg-indigo-600 px-4 text-base font-semibold active:bg-indigo-700"
              >
                Recuperar mi jugador
              </button>
              <button
                type="button"
                onClick={() => navigate('/recuperar')}
                className="min-h-[44px] rounded-xl border border-slate-600 px-4 text-base font-semibold active:bg-slate-800"
              >
                Recuperar partida como anfitrión
              </button>
            </div>
          )}

          {peek.status === 'cancelled' && (
            <p role="status" className="rounded-lg bg-slate-800 px-3 py-2 text-sm text-slate-300">
              Esta partida fue cancelada.
            </p>
          )}

          <button
            type="button"
            onClick={() => {
              setPeek(null);
              setError(null);
            }}
            className="text-sm text-slate-400 underline"
          >
            Probar otro código
          </button>
        </div>
      )}
    </section>
  );
}
