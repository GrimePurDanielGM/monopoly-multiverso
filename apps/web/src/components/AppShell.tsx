import { Link, Outlet } from 'react-router-dom';
import { useConnectionStore } from '../store/connection';
import { useSessionStore } from '../store/session';

/** Marco común: cabecera, avisos (offline / sin configurar) y contenido (Outlet). Mobile-first. */
export function AppShell() {
  const online = useConnectionStore((s) => s.online);
  const status = useSessionStore((s) => s.status);

  return (
    <div className="mx-auto flex min-h-full max-w-md flex-col bg-slate-900 text-slate-100">
      <header className="flex items-center justify-between px-5 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <Link to="/" className="text-base font-semibold">
          Monopoly: <span className="text-indigo-400">El Multiverso</span>
        </Link>
        <span
          aria-label={online ? 'En línea' : 'Sin conexión'}
          title={online ? 'En línea' : 'Sin conexión'}
          className={`h-2.5 w-2.5 rounded-full ${online ? 'bg-emerald-400' : 'bg-rose-500'}`}
        />
      </header>

      {!online && (
        <p role="status" className="bg-rose-950/60 px-5 py-1.5 text-center text-xs text-rose-200">
          Sin conexión. Reintentaremos al volver.
        </p>
      )}
      {status === 'unconfigured' && (
        <p role="status" className="bg-amber-950/60 px-5 py-1.5 text-center text-xs text-amber-200">
          Falta configurar <code>VITE_SUPABASE_URL</code> / <code>VITE_SUPABASE_ANON_KEY</code>.
        </p>
      )}

      <main className="flex flex-1 flex-col gap-4 px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-2">
        <Outlet />
      </main>
    </div>
  );
}
