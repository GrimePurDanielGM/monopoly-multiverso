import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { loadGameHistory, forgetGame, historyStatusLabel } from '../lib/gameHistory';

/** Fecha relativa breve ("hoy", "ayer", "hace N días") a partir de un ISO; cae a la fecha local si falla. */
function relativeDate(iso: string): string {
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return '';
  const days = Math.floor((Date.now() - then) / 86_400_000);
  if (days <= 0) return 'hoy';
  if (days === 1) return 'ayer';
  if (days < 30) return `hace ${days} días`;
  return new Date(iso).toLocaleDateString();
}

/** Pantalla inicial: historial local de partidas (si lo hay), crear o unirse. */
export function HomeScreen() {
  const navigate = useNavigate();
  const [games, setGames] = useState(() => loadGameHistory());

  const remove = (code: string) => { forgetGame(code); setGames(loadGameHistory()); };

  return (
    <section className="flex flex-1 flex-col justify-center gap-6 lg:mx-auto lg:w-full lg:max-w-md">
      <div className="text-center">
        <h1 className="text-2xl font-bold">Monopoly: El Multiverso</h1>
        <p className="mt-1 text-sm text-slate-400">Crea una sala o únete a la de tu grupo.</p>
      </div>

      {games.length > 0 && (
        <section aria-label="Mis partidas" className="flex flex-col gap-2">
          <h2 className="text-sm font-bold text-slate-300">Mis partidas</h2>
          <ul className="flex flex-col gap-2">
            {games.map((g) => (
              <li key={g.code} className="flex items-center gap-2 rounded-xl border border-slate-700 p-3">
                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-2">
                    <span className="font-mono font-semibold tracking-wider">{g.code}</span>
                    <span className={`rounded px-1.5 py-0.5 text-[11px] font-medium ${
                      g.status === 'finished' ? 'bg-slate-700 text-slate-300' : 'bg-emerald-900/60 text-emerald-200'}`}>
                      {historyStatusLabel(g.status)}
                    </span>
                  </p>
                  <p className="truncate text-xs text-slate-400">
                    {g.game_title ? `${g.game_title} · ` : ''}{g.display_name ? `${g.display_name} · ` : ''}
                    {relativeDate(g.last_seen_at)}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => navigate(`/sala/${g.code}`)}
                  className="min-h-[40px] shrink-0 rounded-lg bg-indigo-600 px-3 text-sm font-semibold active:bg-indigo-700"
                >
                  Entrar
                </button>
                <button
                  type="button"
                  aria-label={`Quitar ${g.code} de la lista`}
                  onClick={() => remove(g.code)}
                  className="min-h-[40px] shrink-0 rounded-lg border border-slate-600 px-2 text-xs text-slate-400 active:bg-slate-800"
                >
                  Quitar
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      <div className="flex flex-col gap-3">
        <button
          type="button"
          onClick={() => navigate('/crear')}
          className="rounded-xl bg-indigo-600 px-4 py-3 text-base font-semibold active:bg-indigo-700"
        >
          Crear partida
        </button>
        <button
          type="button"
          onClick={() => navigate('/unirse')}
          className="rounded-xl border border-slate-600 px-4 py-3 text-base font-semibold active:bg-slate-800"
        >
          Unirse con un código
        </button>
        <button
          type="button"
          onClick={() => navigate('/unirse')}
          className="rounded-xl border border-slate-600 px-4 py-3 text-base font-semibold active:bg-slate-800"
        >
          Recuperar mi jugador
        </button>
        <button
          type="button"
          onClick={() => navigate('/recuperar')}
          className="rounded-xl border border-slate-600 px-4 py-3 text-base font-semibold active:bg-slate-800"
        >
          Recuperar partida como anfitrión
        </button>
      </div>
    </section>
  );
}
