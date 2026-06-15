import { useEffect, useState } from 'react';
import { engineFingerprint } from '@multiverso/engine';
import { supabaseConfigured } from '../lib/supabase';
import { runRealtimeProbe, type RealtimeProbeResult } from '../lib/realtime';
import { useConnectionStore } from '../store/connection';

export function App() {
  const fp = engineFingerprint();
  const online = useConnectionStore((s) => s.online);
  const setOnline = useConnectionStore((s) => s.setOnline);
  const [probe, setProbe] = useState<RealtimeProbeResult | null>(null);
  const [running, setRunning] = useState(false);

  useEffect(() => {
    const on = () => setOnline(true);
    const off = () => setOnline(false);
    window.addEventListener('online', on);
    window.addEventListener('offline', off);
    return () => {
      window.removeEventListener('online', on);
      window.removeEventListener('offline', off);
    };
  }, [setOnline]);

  const runProbe = async () => {
    setRunning(true);
    const result = await runRealtimeProbe(setProbe);
    setProbe(result);
    setRunning(false);
  };

  return (
    <main className="mx-auto flex min-h-full max-w-md flex-col gap-4 bg-slate-900 p-5 text-slate-100">
      <header className="pt-2">
        <h1 className="text-xl font-semibold">Monopoly: El Multiverso</h1>
        <p className="text-sm text-slate-400">Esqueleto de Fase 0 — sin reglas de juego.</p>
      </header>

      <section className="rounded-xl border border-slate-700 p-4">
        <h2 className="text-sm font-medium text-slate-300">Motor compartido</h2>
        <p className="mt-1 break-all text-sm">
          {fp.name} v{fp.version} · checksum {fp.checksum}
        </p>
        <p className="mt-1 text-xs text-slate-500">
          Importado desde <code>@multiverso/engine</code> (misma fuente que la Edge Function).
        </p>
      </section>

      <section className="rounded-xl border border-slate-700 p-4">
        <h2 className="text-sm font-medium text-slate-300">Estado</h2>
        <ul className="mt-1 space-y-1 text-sm">
          <li>Conexión del dispositivo: {online ? '🟢 online' : '🔴 offline'}</li>
          <li>Supabase configurado: {supabaseConfigured ? '🟢 sí' : '🟡 no (define las VITE_*)'}</li>
        </ul>
      </section>

      <section className="rounded-xl border border-slate-700 p-4">
        <h2 className="text-sm font-medium text-slate-300">Prueba de Realtime</h2>
        <button
          onClick={runProbe}
          disabled={running || !supabaseConfigured}
          className="mt-2 w-full rounded-lg bg-indigo-600 px-3 py-2 text-sm font-medium disabled:opacity-40"
        >
          {running ? 'Ejecutando…' : 'Ejecutar prueba de Realtime'}
        </button>
        {probe && (
          <pre className="mt-3 max-h-48 overflow-auto rounded-lg bg-slate-950 p-3 text-xs text-slate-300">
            {probe.log.join('\n')}
          </pre>
        )}
      </section>
    </main>
  );
}
