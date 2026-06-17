import { Link } from 'react-router-dom';

export function NotFoundScreen() {
  return (
    <section className="flex flex-1 flex-col items-center justify-center gap-3 text-center">
      <h1 className="text-xl font-bold">Página no encontrada</h1>
      <p className="text-sm text-slate-400">El enlace no es válido o la página no existe.</p>
      <Link to="/" className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold">
        Volver al inicio
      </Link>
    </section>
  );
}
