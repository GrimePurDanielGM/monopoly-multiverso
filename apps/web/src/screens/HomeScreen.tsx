import { useNavigate } from 'react-router-dom';

/** Pantalla inicial: crear partida o unirse. */
export function HomeScreen() {
  const navigate = useNavigate();
  return (
    <section className="flex flex-1 flex-col justify-center gap-6 lg:mx-auto lg:w-full lg:max-w-md">
      <div className="text-center">
        <h1 className="text-2xl font-bold">Monopoly: El Multiverso</h1>
        <p className="mt-1 text-sm text-slate-400">Crea una sala o únete a la de tu grupo.</p>
      </div>
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
          onClick={() => navigate('/recuperar')}
          className="rounded-xl border border-slate-600 px-4 py-3 text-base font-semibold active:bg-slate-800"
        >
          Recuperar partida como anfitrión
        </button>
      </div>
    </section>
  );
}
